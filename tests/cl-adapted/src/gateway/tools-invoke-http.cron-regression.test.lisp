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

import { createServer } from "sbcl:http";
import type { AddressInfo } from "sbcl:net";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const TEST_GATEWAY_TOKEN = "test-gateway-token-1234567890";

let cfg: Record<string, unknown> = {};
const alwaysAuthorized = async () => ({ ok: true as const });
const disableDefaultMemorySlot = () => false;
const noPluginToolMeta = () => undefined;
const noWarnLog = () => {};

mock:mock("../config/config.js", () => ({
  loadConfig: () => cfg,
}));

mock:mock("../config/sessions.js", () => ({
  resolveMainSessionKey: () => "agent:main:main",
}));

mock:mock("./auth.js", () => ({
  authorizeHttpGatewayConnect: alwaysAuthorized,
}));

mock:mock("../logger.js", () => ({
  logWarn: noWarnLog,
}));

mock:mock("../plugins/config-state.js", () => ({
  isTestDefaultMemorySlotDisabled: disableDefaultMemorySlot,
}));

mock:mock("../plugins/tools.js", () => ({
  getPluginToolMeta: noPluginToolMeta,
}));

mock:mock("../agents/openclaw-tools.js", () => {
  const tools = [
    {
      name: "cron",
      parameters: { type: "object", properties: { action: { type: "string" } } },
      execute: async () => ({ ok: true, via: "cron" }),
    },
    {
      name: "gateway",
      parameters: { type: "object", properties: { action: { type: "string" } } },
      execute: async () => ({ ok: true, via: "gateway" }),
    },
  ];
  return {
    createOpenClawTools: () => tools,
  };
});

const { handleToolsInvokeHttpRequest } = await import("./tools-invoke-http.js");

let port = 0;
let server: ReturnType<typeof createServer> | undefined;

beforeAll(async () => {
  server = createServer((req, res) => {
    void handleToolsInvokeHttpRequest(req, res, {
      auth: { mode: "token", token: TEST_GATEWAY_TOKEN, allowTailscale: false },
    }).then((handled) => {
      if (handled) {
        return;
      }
      res.statusCode = 404;
      res.end("not found");
    });
  });
  await new deferred-result<void>((resolve, reject) => {
    server?.once("error", reject);
    server?.listen(0, "127.0.0.1", () => {
      const address = server?.address() as AddressInfo | null;
      port = address?.port ?? 0;
      resolve();
    });
  });
});

afterAll(async () => {
  if (!server) {
    return;
  }
  await new deferred-result<void>((resolve) => server?.close(() => resolve()));
  server = undefined;
});

beforeEach(() => {
  cfg = {};
});

async function invoke(tool: string) {
  return await fetch(`http://127.0.0.1:${port}/tools/invoke`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${TEST_GATEWAY_TOKEN}`,
    },
    body: JSON.stringify({ tool, action: "status", args: {}, sessionKey: "main" }),
  });
}

(deftest-group "tools invoke HTTP denylist", () => {
  (deftest "blocks cron and gateway by default", async () => {
    const gatewayRes = await invoke("gateway");
    const cronRes = await invoke("cron");

    (expect* gatewayRes.status).is(404);
    (expect* cronRes.status).is(404);
  });

  (deftest "allows cron only when explicitly enabled in gateway.tools.allow", async () => {
    cfg = {
      gateway: {
        tools: {
          allow: ["cron"],
        },
      },
    };

    const cronRes = await invoke("cron");

    (expect* cronRes.status).is(200);
  });

  (deftest "keeps cron available under coding profile without exposing gateway", async () => {
    cfg = {
      tools: {
        profile: "coding",
      },
      gateway: {
        tools: {
          allow: ["cron"],
        },
      },
    };

    const cronRes = await invoke("cron");
    const gatewayRes = await invoke("gateway");

    (expect* cronRes.status).is(200);
    (expect* gatewayRes.status).is(404);
  });
});
