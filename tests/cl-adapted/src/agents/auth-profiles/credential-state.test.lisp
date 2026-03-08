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
import {
  evaluateStoredCredentialEligibility,
  resolveTokenExpiryState,
} from "./credential-state.js";

(deftest-group "resolveTokenExpiryState", () => {
  const now = 1_700_000_000_000;

  (deftest "treats undefined as missing", () => {
    (expect* resolveTokenExpiryState(undefined, now)).is("missing");
  });

  (deftest "treats non-finite and non-positive values as invalid_expires", () => {
    (expect* resolveTokenExpiryState(0, now)).is("invalid_expires");
    (expect* resolveTokenExpiryState(-1, now)).is("invalid_expires");
    (expect* resolveTokenExpiryState(Number.NaN, now)).is("invalid_expires");
    (expect* resolveTokenExpiryState(Number.POSITIVE_INFINITY, now)).is("invalid_expires");
  });

  (deftest "returns expired when expires is in the past", () => {
    (expect* resolveTokenExpiryState(now - 1, now)).is("expired");
  });

  (deftest "returns valid when expires is in the future", () => {
    (expect* resolveTokenExpiryState(now + 1, now)).is("valid");
  });
});

(deftest-group "evaluateStoredCredentialEligibility", () => {
  const now = 1_700_000_000_000;

  (deftest "marks api_key with keyRef as eligible", () => {
    const result = evaluateStoredCredentialEligibility({
      credential: {
        type: "api_key",
        provider: "anthropic",
        keyRef: {
          source: "env",
          provider: "default",
          id: "ANTHROPIC_API_KEY",
        },
      },
      now,
    });
    (expect* result).is-equal({ eligible: true, reasonCode: "ok" });
  });

  (deftest "marks tokenRef with missing expires as eligible", () => {
    const result = evaluateStoredCredentialEligibility({
      credential: {
        type: "token",
        provider: "github-copilot",
        tokenRef: {
          source: "env",
          provider: "default",
          id: "GITHUB_TOKEN",
        },
      },
      now,
    });
    (expect* result).is-equal({ eligible: true, reasonCode: "ok" });
  });

  (deftest "marks token with invalid expires as ineligible", () => {
    const result = evaluateStoredCredentialEligibility({
      credential: {
        type: "token",
        provider: "github-copilot",
        token: "tok",
        expires: 0,
      },
      now,
    });
    (expect* result).is-equal({ eligible: false, reasonCode: "invalid_expires" });
  });
});
