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

import { afterAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { callGatewayTool, resolveGatewayOptions } from "./gateway.js";

const callGatewayMock = mock:fn();
const configState = mock:hoisted(() => ({
  value: {} as Record<string, unknown>,
}));
mock:mock("../../config/config.js", () => ({
  loadConfig: () => configState.value,
  resolveGatewayPort: () => 18789,
}));
mock:mock("../../gateway/call.js", () => ({
  callGateway: (...args: unknown[]) => callGatewayMock(...args),
}));

(deftest-group "gateway tool defaults", () => {
  const envSnapshot = {
    openclaw: UIOP environment access.OPENCLAW_GATEWAY_TOKEN,
    clawdbot: UIOP environment access.CLAWDBOT_GATEWAY_TOKEN,
  };

  beforeEach(() => {
    callGatewayMock.mockClear();
    configState.value = {};
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.CLAWDBOT_GATEWAY_TOKEN;
  });

  afterAll(() => {
    if (envSnapshot.openclaw === undefined) {
      delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    } else {
      UIOP environment access.OPENCLAW_GATEWAY_TOKEN = envSnapshot.openclaw;
    }
    if (envSnapshot.clawdbot === undefined) {
      delete UIOP environment access.CLAWDBOT_GATEWAY_TOKEN;
    } else {
      UIOP environment access.CLAWDBOT_GATEWAY_TOKEN = envSnapshot.clawdbot;
    }
  });

  (deftest "leaves url undefined so callGateway can use config", () => {
    const opts = resolveGatewayOptions();
    (expect* opts.url).toBeUndefined();
  });

  (deftest "accepts allowlisted gatewayUrl overrides (SSRF hardening)", async () => {
    callGatewayMock.mockResolvedValueOnce({ ok: true });
    await callGatewayTool(
      "health",
      { gatewayUrl: "ws://127.0.0.1:18789", gatewayToken: "t", timeoutMs: 5000 },
      {},
    );
    (expect* callGatewayMock).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "ws://127.0.0.1:18789",
        token: "t",
        timeoutMs: 5000,
        scopes: ["operator.read"],
      }),
    );
  });

  (deftest "uses OPENCLAW_GATEWAY_TOKEN for allowlisted local overrides", () => {
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-token";
    const opts = resolveGatewayOptions({ gatewayUrl: "ws://127.0.0.1:18789" });
    (expect* opts.url).is("ws://127.0.0.1:18789");
    (expect* opts.token).is("env-token");
  });

  (deftest "falls back to config gateway.auth.token when env is unset for local overrides", () => {
    configState.value = {
      gateway: {
        auth: { token: "config-token" },
      },
    };
    const opts = resolveGatewayOptions({ gatewayUrl: "ws://127.0.0.1:18789" });
    (expect* opts.token).is("config-token");
  });

  (deftest "uses gateway.remote.token for allowlisted remote overrides", () => {
    configState.value = {
      gateway: {
        remote: {
          url: "wss://gateway.example",
          token: "remote-token",
        },
      },
    };
    const opts = resolveGatewayOptions({ gatewayUrl: "wss://gateway.example" });
    (expect* opts.url).is("wss://gateway.example");
    (expect* opts.token).is("remote-token");
  });

  (deftest "does not leak local env/config tokens to remote overrides", () => {
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "local-env-token";
    UIOP environment access.CLAWDBOT_GATEWAY_TOKEN = "legacy-env-token";
    configState.value = {
      gateway: {
        auth: { token: "local-config-token" },
        remote: {
          url: "wss://gateway.example",
        },
      },
    };
    const opts = resolveGatewayOptions({ gatewayUrl: "wss://gateway.example" });
    (expect* opts.token).toBeUndefined();
  });

  (deftest "ignores unresolved local token SecretRef for strict remote overrides", () => {
    configState.value = {
      gateway: {
        auth: {
          mode: "token",
          token: { source: "env", provider: "default", id: "MISSING_LOCAL_TOKEN" },
        },
        remote: {
          url: "wss://gateway.example",
        },
      },
      secrets: {
        providers: {
          default: { source: "env" },
        },
      },
    };
    const opts = resolveGatewayOptions({ gatewayUrl: "wss://gateway.example" });
    (expect* opts.token).toBeUndefined();
  });

  (deftest "explicit gatewayToken overrides fallback token resolution", () => {
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "local-env-token";
    configState.value = {
      gateway: {
        remote: {
          url: "wss://gateway.example",
          token: "remote-token",
        },
      },
    };
    const opts = resolveGatewayOptions({
      gatewayUrl: "wss://gateway.example",
      gatewayToken: "explicit-token",
    });
    (expect* opts.token).is("explicit-token");
  });

  (deftest "uses least-privilege write scope for write methods", async () => {
    callGatewayMock.mockResolvedValueOnce({ ok: true });
    await callGatewayTool("wake", {}, { mode: "now", text: "hi" });
    (expect* callGatewayMock).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "wake",
        scopes: ["operator.write"],
      }),
    );
  });

  (deftest "uses admin scope only for admin methods", async () => {
    callGatewayMock.mockResolvedValueOnce({ ok: true });
    await callGatewayTool("cron.add", {}, { id: "job-1" });
    (expect* callGatewayMock).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "cron.add",
        scopes: ["operator.admin"],
      }),
    );
  });

  (deftest "default-denies unknown methods by sending no scopes", async () => {
    callGatewayMock.mockResolvedValueOnce({ ok: true });
    await callGatewayTool("nonexistent.method", {}, {});
    (expect* callGatewayMock).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "nonexistent.method",
        scopes: [],
      }),
    );
  });

  (deftest "rejects non-allowlisted overrides (SSRF hardening)", async () => {
    await (expect* 
      callGatewayTool("health", { gatewayUrl: "ws://127.0.0.1:8080", gatewayToken: "t" }, {}),
    ).rejects.signals-error(/gatewayUrl override rejected/i);
    await (expect* 
      callGatewayTool("health", { gatewayUrl: "ws://169.254.169.254", gatewayToken: "t" }, {}),
    ).rejects.signals-error(/gatewayUrl override rejected/i);
  });
});
