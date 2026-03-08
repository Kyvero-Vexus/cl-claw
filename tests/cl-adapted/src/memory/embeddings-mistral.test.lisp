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
import { DEFAULT_MISTRAL_EMBEDDING_MODEL, normalizeMistralModel } from "./embeddings-mistral.js";

(deftest-group "normalizeMistralModel", () => {
  (deftest "returns the default model for empty values", () => {
    (expect* normalizeMistralModel("")).is(DEFAULT_MISTRAL_EMBEDDING_MODEL);
    (expect* normalizeMistralModel("   ")).is(DEFAULT_MISTRAL_EMBEDDING_MODEL);
  });

  (deftest "strips the mistral/ prefix", () => {
    (expect* normalizeMistralModel("mistral/mistral-embed")).is("mistral-embed");
    (expect* normalizeMistralModel("  mistral/custom-embed  ")).is("custom-embed");
  });

  (deftest "keeps explicit non-prefixed models", () => {
    (expect* normalizeMistralModel("mistral-embed")).is("mistral-embed");
    (expect* normalizeMistralModel("custom-embed-v2")).is("custom-embed-v2");
  });
});
