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
import { listKnownProviderEnvApiKeyNames } from "./model-auth-env-vars.js";
import { isNonSecretApiKeyMarker, NON_ENV_SECRETREF_MARKER } from "./model-auth-markers.js";

(deftest-group "model auth markers", () => {
  (deftest "recognizes explicit non-secret markers", () => {
    (expect* isNonSecretApiKeyMarker(NON_ENV_SECRETREF_MARKER)).is(true);
    (expect* isNonSecretApiKeyMarker("qwen-oauth")).is(true);
    (expect* isNonSecretApiKeyMarker("ollama-local")).is(true);
  });

  (deftest "recognizes known env marker names but not arbitrary all-caps keys", () => {
    (expect* isNonSecretApiKeyMarker("OPENAI_API_KEY")).is(true);
    (expect* isNonSecretApiKeyMarker("ALLCAPS_EXAMPLE")).is(false);
  });

  (deftest "recognizes all built-in provider env marker names", () => {
    for (const envVarName of listKnownProviderEnvApiKeyNames()) {
      (expect* isNonSecretApiKeyMarker(envVarName)).is(true);
    }
  });

  (deftest "can exclude env marker-name interpretation for display-only paths", () => {
    (expect* isNonSecretApiKeyMarker("OPENAI_API_KEY", { includeEnvVarName: false })).is(false);
  });
});
