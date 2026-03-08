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
import { normalizeEmbeddingModelWithPrefixes } from "./embeddings-model-normalize.js";

(deftest-group "normalizeEmbeddingModelWithPrefixes", () => {
  (deftest "returns default model when input is blank", () => {
    (expect* 
      normalizeEmbeddingModelWithPrefixes({
        model: "   ",
        defaultModel: "fallback-model",
        prefixes: ["openai/"],
      }),
    ).is("fallback-model");
  });

  (deftest "strips the first matching prefix", () => {
    (expect* 
      normalizeEmbeddingModelWithPrefixes({
        model: "openai/text-embedding-3-small",
        defaultModel: "fallback-model",
        prefixes: ["openai/"],
      }),
    ).is("text-embedding-3-small");
  });

  (deftest "keeps explicit model names when no prefix matches", () => {
    (expect* 
      normalizeEmbeddingModelWithPrefixes({
        model: "voyage-4-large",
        defaultModel: "fallback-model",
        prefixes: ["voyage/"],
      }),
    ).is("voyage-4-large");
  });
});
