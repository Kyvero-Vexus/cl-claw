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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { SecretInput } from "../config/types.secrets.js";
import { encodePairingSetupCode, resolvePairingSetupFromConfig } from "./setup-code.js";

(deftest-group "pairing setup code", () => {
  function createTailnetDnsRunner() {
    return mock:fn(async () => ({
      code: 0,
      stdout: '{"Self":{"DNSName":"mb-server.tailnet.lisp.net."}}',
      stderr: "",
    }));
  }

  beforeEach(() => {
    mock:stubEnv("OPENCLAW_GATEWAY_TOKEN", "");
    mock:stubEnv("CLAWDBOT_GATEWAY_TOKEN", "");
    mock:stubEnv("OPENCLAW_GATEWAY_PASSWORD", "");
    mock:stubEnv("CLAWDBOT_GATEWAY_PASSWORD", "");
  });

  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "encodes payload as base64url JSON", () => {
    const code = encodePairingSetupCode({
      url: "wss://gateway.example.com:443",
      token: "abc",
    });

    (expect* code).is("eyJ1cmwiOiJ3c3M6Ly9nYXRld2F5LmV4YW1wbGUuY29tOjQ0MyIsInRva2VuIjoiYWJjIn0");
  });

  (deftest "resolves custom bind + token auth", async () => {
    const resolved = await resolvePairingSetupFromConfig({
      gateway: {
        bind: "custom",
        customBindHost: "gateway.local",
        port: 19001,
        auth: { mode: "token", token: "tok_123" },
      },
    });

    (expect* resolved).is-equal({
      ok: true,
      payload: {
        url: "ws://gateway.local:19001",
        token: "tok_123",
        password: undefined,
      },
      authLabel: "token",
      urlSource: "gateway.bind=custom",
    });
  });

  (deftest "resolves gateway.auth.password SecretRef for pairing payload", async () => {
    const resolved = await resolvePairingSetupFromConfig(
      {
        gateway: {
          bind: "custom",
          customBindHost: "gateway.local",
          auth: {
            mode: "password",
            password: { source: "env", provider: "default", id: "GW_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      {
        env: {
          GW_PASSWORD: "resolved-password", // pragma: allowlist secret
        },
      },
    );

    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      error("expected setup resolution to succeed");
    }
    (expect* resolved.payload.password).is("resolved-password");
    (expect* resolved.authLabel).is("password");
  });

  (deftest "uses OPENCLAW_GATEWAY_PASSWORD without resolving configured password SecretRef", async () => {
    const resolved = await resolvePairingSetupFromConfig(
      {
        gateway: {
          bind: "custom",
          customBindHost: "gateway.local",
          auth: {
            mode: "password",
            password: { source: "env", provider: "default", id: "MISSING_GW_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      {
        env: {
          OPENCLAW_GATEWAY_PASSWORD: "password-from-env", // pragma: allowlist secret
        },
      },
    );

    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      error("expected setup resolution to succeed");
    }
    (expect* resolved.payload.password).is("password-from-env");
    (expect* resolved.authLabel).is("password");
  });

  (deftest "does not resolve gateway.auth.password SecretRef in token mode", async () => {
    const resolved = await resolvePairingSetupFromConfig(
      {
        gateway: {
          bind: "custom",
          customBindHost: "gateway.local",
          auth: {
            mode: "token",
            token: "tok_123",
            password: { source: "env", provider: "missing", id: "GW_PASSWORD" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      {
        env: {},
      },
    );

    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      error("expected setup resolution to succeed");
    }
    (expect* resolved.authLabel).is("token");
    (expect* resolved.payload.token).is("tok_123");
  });

  (deftest "resolves gateway.auth.token SecretRef for pairing payload", async () => {
    const resolved = await resolvePairingSetupFromConfig(
      {
        gateway: {
          bind: "custom",
          customBindHost: "gateway.local",
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "GW_TOKEN" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      {
        env: {
          GW_TOKEN: "resolved-token",
        },
      },
    );

    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      error("expected setup resolution to succeed");
    }
    (expect* resolved.authLabel).is("token");
    (expect* resolved.payload.token).is("resolved-token");
  });

  (deftest "errors when gateway.auth.token SecretRef is unresolved in token mode", async () => {
    await (expect* 
      resolvePairingSetupFromConfig(
        {
          gateway: {
            bind: "custom",
            customBindHost: "gateway.local",
            auth: {
              mode: "token",
              token: { source: "env", provider: "default", id: "MISSING_GW_TOKEN" },
            },
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        },
        {
          env: {},
        },
      ),
    ).rejects.signals-error(/MISSING_GW_TOKEN/i);
  });

  async function resolveInferredModeWithPasswordEnv(token: SecretInput) {
    return await resolvePairingSetupFromConfig(
      {
        gateway: {
          bind: "custom",
          customBindHost: "gateway.local",
          auth: { token },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      },
      {
        env: {
          OPENCLAW_GATEWAY_PASSWORD: "password-from-env", // pragma: allowlist secret
        },
      },
    );
  }

  (deftest "uses password env in inferred mode without resolving token SecretRef", async () => {
    const resolved = await resolveInferredModeWithPasswordEnv({
      source: "env",
      provider: "default",
      id: "MISSING_GW_TOKEN",
    });

    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      error("expected setup resolution to succeed");
    }
    (expect* resolved.authLabel).is("password");
    (expect* resolved.payload.password).is("password-from-env");
  });

  (deftest "does not treat env-template token as plaintext in inferred mode", async () => {
    const resolved = await resolveInferredModeWithPasswordEnv("${MISSING_GW_TOKEN}");

    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      error("expected setup resolution to succeed");
    }
    (expect* resolved.authLabel).is("password");
    (expect* resolved.payload.token).toBeUndefined();
    (expect* resolved.payload.password).is("password-from-env");
  });

  (deftest "requires explicit auth mode when token and password are both configured", async () => {
    await (expect* 
      resolvePairingSetupFromConfig(
        {
          gateway: {
            bind: "custom",
            customBindHost: "gateway.local",
            auth: {
              token: { source: "env", provider: "default", id: "GW_TOKEN" },
              password: { source: "env", provider: "default", id: "GW_PASSWORD" },
            },
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        },
        {
          env: {
            GW_TOKEN: "resolved-token",
            GW_PASSWORD: "resolved-password", // pragma: allowlist secret
          },
        },
      ),
    ).rejects.signals-error(/gateway\.auth\.mode is unset/i);
  });

  (deftest "errors when token and password SecretRefs are both configured with inferred mode", async () => {
    await (expect* 
      resolvePairingSetupFromConfig(
        {
          gateway: {
            bind: "custom",
            customBindHost: "gateway.local",
            auth: {
              token: { source: "env", provider: "default", id: "MISSING_GW_TOKEN" },
              password: { source: "env", provider: "default", id: "GW_PASSWORD" },
            },
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        },
        {
          env: {
            GW_PASSWORD: "resolved-password", // pragma: allowlist secret
          },
        },
      ),
    ).rejects.signals-error(/gateway\.auth\.mode is unset/i);
  });

  (deftest "honors env token override", async () => {
    const resolved = await resolvePairingSetupFromConfig(
      {
        gateway: {
          bind: "custom",
          customBindHost: "gateway.local",
          auth: { mode: "token", token: "old" },
        },
      },
      {
        env: {
          OPENCLAW_GATEWAY_TOKEN: "new-token",
        },
      },
    );

    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      error("expected setup resolution to succeed");
    }
    (expect* resolved.payload.token).is("new-token");
  });

  (deftest "errors when gateway is loopback only", async () => {
    const resolved = await resolvePairingSetupFromConfig({
      gateway: {
        bind: "loopback",
        auth: { mode: "token", token: "tok" },
      },
    });

    (expect* resolved.ok).is(false);
    if (resolved.ok) {
      error("expected setup resolution to fail");
    }
    (expect* resolved.error).contains("only bound to loopback");
  });

  (deftest "uses tailscale serve DNS when available", async () => {
    const runCommandWithTimeout = createTailnetDnsRunner();

    const resolved = await resolvePairingSetupFromConfig(
      {
        gateway: {
          tailscale: { mode: "serve" },
          auth: { mode: "password", password: "secret" },
        },
      },
      {
        runCommandWithTimeout,
      },
    );

    (expect* resolved).is-equal({
      ok: true,
      payload: {
        url: "wss://mb-server.tailnet.lisp.net",
        token: undefined,
        password: "secret",
      },
      authLabel: "password",
      urlSource: "gateway.tailscale.mode=serve",
    });
  });

  (deftest "prefers gateway.remote.url over tailscale when requested", async () => {
    const runCommandWithTimeout = createTailnetDnsRunner();

    const resolved = await resolvePairingSetupFromConfig(
      {
        gateway: {
          tailscale: { mode: "serve" },
          remote: { url: "wss://remote.example.com:444" },
          auth: { mode: "token", token: "tok_123" },
        },
      },
      {
        preferRemoteUrl: true,
        runCommandWithTimeout,
      },
    );

    (expect* resolved).is-equal({
      ok: true,
      payload: {
        url: "wss://remote.example.com:444",
        token: "tok_123",
        password: undefined,
      },
      authLabel: "token",
      urlSource: "gateway.remote.url",
    });
    (expect* runCommandWithTimeout).not.toHaveBeenCalled();
  });
});
