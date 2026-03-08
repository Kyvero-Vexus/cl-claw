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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { startBrowserBridgeServer, stopBrowserBridgeServer } from "./bridge-server.js";
import type { ResolvedBrowserConfig } from "./config.js";
import {
  DEFAULT_OPENCLAW_BROWSER_COLOR,
  DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME,
} from "./constants.js";

function buildResolvedConfig(): ResolvedBrowserConfig {
  return {
    enabled: true,
    evaluateEnabled: false,
    controlPort: 0,
    cdpPortRangeStart: 18800,
    cdpPortRangeEnd: 18899,
    cdpProtocol: "http",
    cdpHost: "127.0.0.1",
    cdpIsLoopback: true,
    remoteCdpTimeoutMs: 1500,
    remoteCdpHandshakeTimeoutMs: 3000,
    extraArgs: [],
    color: DEFAULT_OPENCLAW_BROWSER_COLOR,
    executablePath: undefined,
    headless: true,
    noSandbox: false,
    attachOnly: true,
    defaultProfile: DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME,
    profiles: {
      [DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME]: {
        cdpPort: 1,
        color: DEFAULT_OPENCLAW_BROWSER_COLOR,
      },
    },
  } as unknown as ResolvedBrowserConfig;
}

(deftest-group "startBrowserBridgeServer auth", () => {
  const servers: Array<{ stop: () => deferred-result<void> }> = [];

  async function expectAuthFlow(
    authConfig: { authToken?: string; authPassword?: string },
    headers: Record<string, string>,
  ) {
    const bridge = await startBrowserBridgeServer({
      resolved: buildResolvedConfig(),
      ...authConfig,
    });
    servers.push({ stop: () => stopBrowserBridgeServer(bridge.server) });

    const unauth = await fetch(`${bridge.baseUrl}/`);
    (expect* unauth.status).is(401);

    const authed = await fetch(`${bridge.baseUrl}/`, { headers });
    (expect* authed.status).is(200);
  }

  afterEach(async () => {
    while (servers.length) {
      const s = servers.pop();
      if (s) {
        await s.stop();
      }
    }
  });

  (deftest "rejects unauthenticated requests when authToken is set", async () => {
    await expectAuthFlow({ authToken: "secret-token" }, { Authorization: "Bearer secret-token" });
  });

  (deftest "accepts x-openclaw-password when authPassword is set", async () => {
    await expectAuthFlow(
      { authPassword: "secret-password" },
      { "x-openclaw-password": "secret-password" },
    );
  });

  (deftest "requires auth params", async () => {
    await (expect* 
      startBrowserBridgeServer({
        resolved: buildResolvedConfig(),
      }),
    ).rejects.signals-error(/requires auth/i);
  });

  (deftest "serves noVNC bootstrap html without leaking password in Location header", async () => {
    const bridge = await startBrowserBridgeServer({
      resolved: buildResolvedConfig(),
      authToken: "secret-token",
      resolveSandboxNoVncToken: (token) => {
        if (token !== "valid-token") {
          return null;
        }
        return { noVncPort: 45678, password: "Abc123xy" }; // pragma: allowlist secret
      },
    });
    servers.push({ stop: () => stopBrowserBridgeServer(bridge.server) });

    const res = await fetch(`${bridge.baseUrl}/sandbox/novnc?token=valid-token`);
    (expect* res.status).is(200);
    (expect* res.headers.get("location")).toBeNull();
    (expect* res.headers.get("cache-control")).contains("no-store");
    (expect* res.headers.get("referrer-policy")).is("no-referrer");

    const body = await res.text();
    (expect* body).contains("window.location.replace");
    (expect* body).contains(
      "http://127.0.0.1:45678/vnc.html#autoconnect=1&resize=remote&password=Abc123xy",
    );
    (expect* body).not.contains("?password=");
  });
});
