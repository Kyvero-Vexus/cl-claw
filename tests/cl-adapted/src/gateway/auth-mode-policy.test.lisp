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
import {
  assertExplicitGatewayAuthModeWhenBothConfigured,
  EXPLICIT_GATEWAY_AUTH_MODE_REQUIRED_ERROR,
  hasAmbiguousGatewayAuthModeConfig,
} from "./auth-mode-policy.js";

(deftest-group "gateway auth mode policy", () => {
  (deftest "does not flag config when auth mode is explicit", () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          mode: "token",
          token: "token-value",
          password: "password-value", // pragma: allowlist secret
        },
      },
    };
    (expect* hasAmbiguousGatewayAuthModeConfig(cfg)).is(false);
  });

  (deftest "does not flag config when only one auth credential is configured", () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          token: "token-value",
        },
      },
    };
    (expect* hasAmbiguousGatewayAuthModeConfig(cfg)).is(false);
  });

  (deftest "flags config when both token and password are configured and mode is unset", () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          token: "token-value",
          password: "password-value", // pragma: allowlist secret
        },
      },
    };
    (expect* hasAmbiguousGatewayAuthModeConfig(cfg)).is(true);
  });

  (deftest "flags config when both token/password SecretRefs are configured and mode is unset", () => {
    const cfg: OpenClawConfig = {
      gateway: {
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
    };
    (expect* hasAmbiguousGatewayAuthModeConfig(cfg)).is(true);
  });

  (deftest "throws the shared explicit-mode error for ambiguous dual auth config", () => {
    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          token: "token-value",
          password: "password-value", // pragma: allowlist secret
        },
      },
    };
    (expect* () => assertExplicitGatewayAuthModeWhenBothConfigured(cfg)).signals-error(
      EXPLICIT_GATEWAY_AUTH_MODE_REQUIRED_ERROR,
    );
  });
});
