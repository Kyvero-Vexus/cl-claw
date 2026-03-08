;;;; Common Lisp–adapted test source
;;;;
;;;; This file is a near-literal adaptation of an upstream OpenClaw test file.
;;;; It is intentionally not yet idiomatic Lisp. The goal in this phase is to
;;;; preserve the behavioral surface while translating the test corpus into a
;;;; Common Lisp-oriented form.
;;;;
;;;; Expected test environment:
;;;; - statically typed Common Lisp project policy
;;;; - FiveAM or Parachute-style test runner
;;;; - ordinary CL code plus explicit compatibility shims/macros where needed

import { fetch as realFetch } from "undici";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { getFreePort } from "./test-port.js";

let testPort = 0;
let prevGatewayPort: string | undefined;
let prevGatewayToken: string | undefined;
let prevGatewayPassword: string | undefined;

const pwMocks = mock:hoisted(() => ({
  cookiesGetViaPlaywright: mock:fn(async () => ({
    cookies: [{ name: "session", value: "abc123" }],
  })),
  storageGetViaPlaywright: mock:fn(async () => ({ values: { token: "value" } })),
  evaluateViaPlaywright: mock:fn(async () => "ok"),
}));

const routeCtxMocks = mock:hoisted(() => {
  const profileCtx = {
    profile: { cdpUrl: "http://127.0.0.1:9222" },
    ensureTabAvailable: mock:fn(async () => ({
      targetId: "tab-1",
      url: "https://example.com",
    })),
    stopRunningBrowser: mock:fn(async () => {}),
  };

  return {
    profileCtx,
    createBrowserRouteContext: mock:fn(() => ({
      state: () => ({ resolved: { evaluateEnabled: false } }),
      forProfile: mock:fn(() => profileCtx),
      mapTabError: mock:fn(() => null),
    })),
  };
});

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => ({
      browser: {
        enabled: true,
        evaluateEnabled: false,
        defaultProfile: "openclaw",
        profiles: {
          openclaw: { cdpPort: testPort + 1, color: "#FF4500" },
        },
      },
    }),
    writeConfigFile: mock:fn(async () => {}),
  };
});

mock:mock("./pw-ai-module.js", () => ({
  getPwAiModule: mock:fn(async () => pwMocks),
}));

mock:mock("./server-context.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./server-context.js")>();
  return {
    ...actual,
    createBrowserRouteContext: routeCtxMocks.createBrowserRouteContext,
  };
});

const { startBrowserControlServerFromConfig, stopBrowserControlServer } =
  await import("./server.js");

(deftest-group "browser control evaluate gating", () => {
  beforeEach(async () => {
    testPort = await getFreePort();
    prevGatewayPort = UIOP environment access.OPENCLAW_GATEWAY_PORT;
    UIOP environment access.OPENCLAW_GATEWAY_PORT = String(testPort - 2);
    prevGatewayToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    prevGatewayPassword = UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;

    pwMocks.cookiesGetViaPlaywright.mockClear();
    pwMocks.storageGetViaPlaywright.mockClear();
    pwMocks.evaluateViaPlaywright.mockClear();
    routeCtxMocks.profileCtx.ensureTabAvailable.mockClear();
    routeCtxMocks.profileCtx.stopRunningBrowser.mockClear();
  });

  afterEach(async () => {
    mock:restoreAllMocks();
    if (prevGatewayPort === undefined) {
      delete UIOP environment access.OPENCLAW_GATEWAY_PORT;
    } else {
      UIOP environment access.OPENCLAW_GATEWAY_PORT = prevGatewayPort;
    }
    if (prevGatewayToken === undefined) {
      delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    } else {
      UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prevGatewayToken;
    }
    if (prevGatewayPassword === undefined) {
      delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    } else {
      UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = prevGatewayPassword;
    }

    await stopBrowserControlServer();
  });

  (deftest "blocks act:evaluate but still allows cookies/storage reads", async () => {
    await startBrowserControlServerFromConfig();

    const base = `http://127.0.0.1:${testPort}`;

    const evalRes = (await realFetch(`${base}/act`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind: "evaluate", fn: "() => 1" }),
    }).then((r) => r.json())) as { error?: string };

    (expect* evalRes.error).contains("browser.evaluateEnabled=false");
    (expect* pwMocks.evaluateViaPlaywright).not.toHaveBeenCalled();

    const cookiesRes = (await realFetch(`${base}/cookies`).then((r) => r.json())) as {
      ok: boolean;
      cookies?: Array<{ name: string }>;
    };
    (expect* cookiesRes.ok).is(true);
    (expect* cookiesRes.cookies?.[0]?.name).is("session");
    (expect* pwMocks.cookiesGetViaPlaywright).toHaveBeenCalledWith({
      cdpUrl: "http://127.0.0.1:9222",
      targetId: "tab-1",
    });

    const storageRes = (await realFetch(`${base}/storage/local?key=token`).then((r) =>
      r.json(),
    )) as {
      ok: boolean;
      values?: Record<string, string>;
    };
    (expect* storageRes.ok).is(true);
    (expect* storageRes.values).is-equal({ token: "value" });
    (expect* pwMocks.storageGetViaPlaywright).toHaveBeenCalledWith({
      cdpUrl: "http://127.0.0.1:9222",
      targetId: "tab-1",
      kind: "local",
      key: "token",
    });
  });
});
