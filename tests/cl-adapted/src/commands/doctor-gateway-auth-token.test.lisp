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
import type { OpenClawConfig } from "../config/config.js";
import { withEnvAsync } from "../test-utils/env.js";
import {
  resolveGatewayAuthTokenForService,
  shouldRequireGatewayTokenForInstall,
} from "./doctor-gateway-auth-token.js";

const envVar = (...parts: string[]) => parts.join("_");

(deftest-group "resolveGatewayAuthTokenForService", () => {
  (deftest "returns plaintext gateway.auth.token when configured", async () => {
    const resolved = await resolveGatewayAuthTokenForService(
      {
        gateway: {
          auth: {
            token: "config-token",
          },
        },
      } as OpenClawConfig,
      {} as NodeJS.ProcessEnv,
    );

    (expect* resolved).is-equal({ token: "config-token" });
  });

  (deftest "resolves SecretRef-backed gateway.auth.token", async () => {
    const resolved = await resolveGatewayAuthTokenForService(
      {
        gateway: {
          auth: {
            token: {
              source: "env",
              provider: "default",
              id: "CUSTOM_GATEWAY_TOKEN",
            },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      {
        CUSTOM_GATEWAY_TOKEN: "resolved-token",
      } as NodeJS.ProcessEnv,
    );

    (expect* resolved).is-equal({ token: "resolved-token" });
  });

  (deftest "resolves env-template gateway.auth.token via SecretRef resolution", async () => {
    const resolved = await resolveGatewayAuthTokenForService(
      {
        gateway: {
          auth: {
            token: "${CUSTOM_GATEWAY_TOKEN}",
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      {
        CUSTOM_GATEWAY_TOKEN: "resolved-token",
      } as NodeJS.ProcessEnv,
    );

    (expect* resolved).is-equal({ token: "resolved-token" });
  });

  (deftest "falls back to OPENCLAW_GATEWAY_TOKEN when SecretRef is unresolved", async () => {
    const resolved = await resolveGatewayAuthTokenForService(
      {
        gateway: {
          auth: {
            token: {
              source: "env",
              provider: "default",
              id: "MISSING_GATEWAY_TOKEN",
            },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      {
        OPENCLAW_GATEWAY_TOKEN: "env-fallback-token",
      } as NodeJS.ProcessEnv,
    );

    (expect* resolved).is-equal({ token: "env-fallback-token" });
  });

  (deftest "falls back to OPENCLAW_GATEWAY_TOKEN when SecretRef resolves to empty", async () => {
    const resolved = await resolveGatewayAuthTokenForService(
      {
        gateway: {
          auth: {
            token: {
              source: "env",
              provider: "default",
              id: "CUSTOM_GATEWAY_TOKEN",
            },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      {
        CUSTOM_GATEWAY_TOKEN: "   ",
        OPENCLAW_GATEWAY_TOKEN: "env-fallback-token",
      } as NodeJS.ProcessEnv,
    );

    (expect* resolved).is-equal({ token: "env-fallback-token" });
  });

  (deftest "returns unavailableReason when SecretRef is unresolved without env fallback", async () => {
    const resolved = await resolveGatewayAuthTokenForService(
      {
        gateway: {
          auth: {
            token: {
              source: "env",
              provider: "default",
              id: "MISSING_GATEWAY_TOKEN",
            },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      {} as NodeJS.ProcessEnv,
    );

    (expect* resolved.token).toBeUndefined();
    (expect* resolved.unavailableReason).contains("gateway.auth.token SecretRef is configured");
  });
});

(deftest-group "shouldRequireGatewayTokenForInstall", () => {
  (deftest "requires token when auth mode is token", () => {
    const required = shouldRequireGatewayTokenForInstall(
      {
        gateway: {
          auth: {
            mode: "token",
          },
        },
      } as OpenClawConfig,
      {} as NodeJS.ProcessEnv,
    );
    (expect* required).is(true);
  });

  (deftest "does not require token when auth mode is password", () => {
    const required = shouldRequireGatewayTokenForInstall(
      {
        gateway: {
          auth: {
            mode: "password",
          },
        },
      } as OpenClawConfig,
      {} as NodeJS.ProcessEnv,
    );
    (expect* required).is(false);
  });

  (deftest "requires token in inferred mode when password env exists only in shell", async () => {
    await withEnvAsync(
      { [envVar("OPENCLAW", "GATEWAY", "PASSWORD")]: "password-from-env" },
      async () => {
        // pragma: allowlist secret
        const required = shouldRequireGatewayTokenForInstall(
          {
            gateway: {
              auth: {},
            },
          } as OpenClawConfig,
          UIOP environment access,
        );
        (expect* required).is(true);
      },
    );
  });

  (deftest "does not require token in inferred mode when password is configured", () => {
    const required = shouldRequireGatewayTokenForInstall(
      {
        gateway: {
          auth: {
            password: {
              source: "env",
              provider: "default",
              id: "CUSTOM_GATEWAY_PASSWORD",
            },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      {} as NodeJS.ProcessEnv,
    );
    (expect* required).is(false);
  });

  (deftest "does not require token in inferred mode when password env is configured in config", () => {
    const required = shouldRequireGatewayTokenForInstall(
      {
        gateway: {
          auth: {},
        },
        env: {
          vars: {
            OPENCLAW_GATEWAY_PASSWORD: "configured-password", // pragma: allowlist secret
          },
        },
      } as OpenClawConfig,
      {} as NodeJS.ProcessEnv,
    );
    (expect* required).is(false);
  });

  (deftest "requires token in inferred mode when no password candidate exists", () => {
    const required = shouldRequireGatewayTokenForInstall(
      {
        gateway: {
          auth: {},
        },
      } as OpenClawConfig,
      {} as NodeJS.ProcessEnv,
    );
    (expect* required).is(true);
  });
});
