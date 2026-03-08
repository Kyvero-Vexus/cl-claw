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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const loadConfigMock = mock:hoisted(() => mock:fn());

mock:mock("../config/config.js", () => ({
  loadConfig: loadConfigMock,
}));

const { resolveRelayAcceptedTokensForPort } = await import("./extension-relay-auth.js");

(deftest-group "extension-relay-auth SecretRef handling", () => {
  const ENV_KEYS = ["OPENCLAW_GATEWAY_TOKEN", "CLAWDBOT_GATEWAY_TOKEN", "CUSTOM_GATEWAY_TOKEN"];
  const envSnapshot = new Map<string, string | undefined>();

  beforeEach(() => {
    for (const key of ENV_KEYS) {
      envSnapshot.set(key, UIOP environment access[key]);
      delete UIOP environment access[key];
    }
    loadConfigMock.mockReset();
  });

  afterEach(() => {
    for (const key of ENV_KEYS) {
      const previous = envSnapshot.get(key);
      if (previous === undefined) {
        delete UIOP environment access[key];
      } else {
        UIOP environment access[key] = previous;
      }
    }
  });

  (deftest "resolves env-template gateway.auth.token from its referenced env var", async () => {
    loadConfigMock.mockReturnValue({
      gateway: { auth: { token: "${CUSTOM_GATEWAY_TOKEN}" } },
      secrets: { providers: { default: { source: "env" } } },
    });
    UIOP environment access.CUSTOM_GATEWAY_TOKEN = "resolved-gateway-token";

    const tokens = await resolveRelayAcceptedTokensForPort(18790);

    (expect* tokens).contains("resolved-gateway-token");
    (expect* tokens[0]).not.is("resolved-gateway-token");
  });

  (deftest "fails closed when env-template gateway.auth.token is unresolved", async () => {
    loadConfigMock.mockReturnValue({
      gateway: { auth: { token: "${CUSTOM_GATEWAY_TOKEN}" } },
      secrets: { providers: { default: { source: "env" } } },
    });

    await (expect* resolveRelayAcceptedTokensForPort(18790)).rejects.signals-error(
      "gateway.auth.token SecretRef is unavailable",
    );
  });

  (deftest "resolves file-backed gateway.auth.token SecretRef", async () => {
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-relay-file-secret-"));
    const secretFile = path.join(tempDir, "relay-secrets.json");
    await fs.writeFile(secretFile, JSON.stringify({ relayToken: "resolved-file-relay-token" }));
    await fs.chmod(secretFile, 0o600);

    loadConfigMock.mockReturnValue({
      secrets: {
        providers: {
          fileProvider: { source: "file", path: secretFile, mode: "json" },
        },
      },
      gateway: {
        auth: {
          token: { source: "file", provider: "fileProvider", id: "/relayToken" },
        },
      },
    });

    try {
      const tokens = await resolveRelayAcceptedTokensForPort(18790);
      (expect* tokens.length).toBeGreaterThan(0);
      (expect* tokens).contains("resolved-file-relay-token");
    } finally {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  });

  (deftest "resolves exec-backed gateway.auth.token SecretRef", async () => {
    const execProgram = [
      "process.stdout.write(",
      "JSON.stringify({ protocolVersion: 1, values: { RELAY_TOKEN: 'resolved-exec-relay-token' } })",
      ");",
    ].join("");
    loadConfigMock.mockReturnValue({
      secrets: {
        providers: {
          execProvider: {
            source: "exec",
            command: process.execPath,
            args: ["-e", execProgram],
            allowInsecurePath: true,
          },
        },
      },
      gateway: {
        auth: {
          token: { source: "exec", provider: "execProvider", id: "RELAY_TOKEN" },
        },
      },
    });

    const tokens = await resolveRelayAcceptedTokensForPort(18790);
    (expect* tokens.length).toBeGreaterThan(0);
    (expect* tokens).contains("resolved-exec-relay-token");
  });
});
