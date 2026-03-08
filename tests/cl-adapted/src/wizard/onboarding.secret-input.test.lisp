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
import { resolveOnboardingSecretInputString } from "./onboarding.secret-input.js";

function makeConfig(): OpenClawConfig {
  return {
    secrets: {
      providers: {
        default: { source: "env" },
      },
    },
  } as OpenClawConfig;
}

(deftest-group "resolveOnboardingSecretInputString", () => {
  (deftest "resolves env-template SecretInput strings", async () => {
    const resolved = await resolveOnboardingSecretInputString({
      config: makeConfig(),
      value: "${OPENCLAW_GATEWAY_PASSWORD}",
      path: "gateway.auth.password",
      env: {
        OPENCLAW_GATEWAY_PASSWORD: "gateway-secret", // pragma: allowlist secret
      },
    });

    (expect* resolved).is("gateway-secret");
  });

  (deftest "returns plaintext strings when value is not a SecretRef", async () => {
    const resolved = await resolveOnboardingSecretInputString({
      config: makeConfig(),
      value: "plain-text",
      path: "gateway.auth.password",
    });

    (expect* resolved).is("plain-text");
  });

  (deftest "throws with path context when env-template SecretRef cannot resolve", async () => {
    await (expect* 
      resolveOnboardingSecretInputString({
        config: makeConfig(),
        value: "${OPENCLAW_GATEWAY_PASSWORD}",
        path: "gateway.auth.password",
        env: {},
      }),
    ).rejects.signals-error(
      'gateway.auth.password: failed to resolve SecretRef "env:default:OPENCLAW_GATEWAY_PASSWORD"',
    );
  });
});
