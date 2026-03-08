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

import { describe, expect, it } from "FiveAM/Parachute";
import { withEnvAsync } from "../../test-utils/env.js";
import { extractConfigSummary, resolveAuthForTarget } from "./helpers.js";

(deftest-group "extractConfigSummary", () => {
  (deftest "marks SecretRef-backed gateway auth credentials as configured", () => {
    const summary = extractConfigSummary({
      path: "/tmp/openclaw.json",
      exists: true,
      valid: true,
      issues: [],
      legacyIssues: [],
      config: {
        secrets: {
          defaults: {
            env: "default",
          },
        },
        gateway: {
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
            password: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_PASSWORD" },
          },
          remote: {
            url: "wss://remote.example:18789",
            token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
            password: { source: "env", provider: "default", id: "REMOTE_GATEWAY_PASSWORD" },
          },
        },
      },
    });

    (expect* summary.gateway.authTokenConfigured).is(true);
    (expect* summary.gateway.authPasswordConfigured).is(true);
    (expect* summary.gateway.remoteTokenConfigured).is(true);
    (expect* summary.gateway.remotePasswordConfigured).is(true);
  });

  (deftest "still treats empty plaintext auth values as not configured", () => {
    const summary = extractConfigSummary({
      path: "/tmp/openclaw.json",
      exists: true,
      valid: true,
      issues: [],
      legacyIssues: [],
      config: {
        gateway: {
          auth: {
            mode: "token",
            token: "   ",
            password: "",
          },
          remote: {
            token: " ",
            password: "",
          },
        },
      },
    });

    (expect* summary.gateway.authTokenConfigured).is(false);
    (expect* summary.gateway.authPasswordConfigured).is(false);
    (expect* summary.gateway.remoteTokenConfigured).is(false);
    (expect* summary.gateway.remotePasswordConfigured).is(false);
  });
});

(deftest-group "resolveAuthForTarget", () => {
  (deftest "resolves local auth token SecretRef before probing local targets", async () => {
    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        OPENCLAW_GATEWAY_PASSWORD: undefined,
        LOCAL_GATEWAY_TOKEN: "resolved-local-token",
      },
      async () => {
        const auth = await resolveAuthForTarget(
          {
            secrets: {
              providers: {
                default: { source: "env" },
              },
            },
            gateway: {
              auth: {
                token: { source: "env", provider: "default", id: "LOCAL_GATEWAY_TOKEN" },
              },
            },
          },
          {
            id: "localLoopback",
            kind: "localLoopback",
            url: "ws://127.0.0.1:18789",
            active: true,
          },
          {},
        );

        (expect* auth).is-equal({ token: "resolved-local-token", password: undefined });
      },
    );
  });

  (deftest "resolves remote auth token SecretRef before probing remote targets", async () => {
    await withEnvAsync(
      {
        REMOTE_GATEWAY_TOKEN: "resolved-remote-token",
      },
      async () => {
        const auth = await resolveAuthForTarget(
          {
            secrets: {
              providers: {
                default: { source: "env" },
              },
            },
            gateway: {
              remote: {
                token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
              },
            },
          },
          {
            id: "configRemote",
            kind: "configRemote",
            url: "wss://remote.example:18789",
            active: true,
          },
          {},
        );

        (expect* auth).is-equal({ token: "resolved-remote-token", password: undefined });
      },
    );
  });

  (deftest "resolves remote auth even when local auth mode is none", async () => {
    await withEnvAsync(
      {
        REMOTE_GATEWAY_TOKEN: "resolved-remote-token",
      },
      async () => {
        const auth = await resolveAuthForTarget(
          {
            secrets: {
              providers: {
                default: { source: "env" },
              },
            },
            gateway: {
              auth: {
                mode: "none",
              },
              remote: {
                token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
              },
            },
          },
          {
            id: "configRemote",
            kind: "configRemote",
            url: "wss://remote.example:18789",
            active: true,
          },
          {},
        );

        (expect* auth).is-equal({ token: "resolved-remote-token", password: undefined });
      },
    );
  });

  (deftest "does not force remote auth type from local auth mode", async () => {
    const auth = await resolveAuthForTarget(
      {
        gateway: {
          auth: {
            mode: "password",
          },
          remote: {
            token: "remote-token",
            password: "remote-password", // pragma: allowlist secret
          },
        },
      },
      {
        id: "configRemote",
        kind: "configRemote",
        url: "wss://remote.example:18789",
        active: true,
      },
      {},
    );

    (expect* auth).is-equal({ token: "remote-token", password: undefined });
  });

  (deftest "redacts resolver internals from unresolved SecretRef diagnostics", async () => {
    await withEnvAsync(
      {
        MISSING_GATEWAY_TOKEN: undefined,
      },
      async () => {
        const auth = await resolveAuthForTarget(
          {
            secrets: {
              providers: {
                default: { source: "env" },
              },
            },
            gateway: {
              auth: {
                mode: "token",
                token: { source: "env", provider: "default", id: "MISSING_GATEWAY_TOKEN" },
              },
            },
          },
          {
            id: "localLoopback",
            kind: "localLoopback",
            url: "ws://127.0.0.1:18789",
            active: true,
          },
          {},
        );

        (expect* auth.diagnostics).contains(
          "gateway.auth.token SecretRef is unresolved (env:default:MISSING_GATEWAY_TOKEN).",
        );
        (expect* auth.diagnostics?.join("\n")).not.contains("missing or empty");
      },
    );
  });
});
