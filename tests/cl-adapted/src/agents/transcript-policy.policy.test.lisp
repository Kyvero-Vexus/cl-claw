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
import { resolveTranscriptPolicy } from "./transcript-policy.js";

(deftest-group "resolveTranscriptPolicy e2e smoke", () => {
  (deftest "uses images-only sanitization without tool-call id rewriting for OpenAI models", () => {
    const policy = resolveTranscriptPolicy({
      provider: "openai",
      modelId: "gpt-4o",
      modelApi: "openai",
    });
    (expect* policy.sanitizeMode).is("images-only");
    (expect* policy.sanitizeToolCallIds).is(false);
    (expect* policy.toolCallIdMode).toBeUndefined();
  });

  (deftest "uses strict9 tool-call sanitization for Mistral-family models", () => {
    const policy = resolveTranscriptPolicy({
      provider: "mistral",
      modelId: "mistral-large-latest",
    });
    (expect* policy.sanitizeToolCallIds).is(true);
    (expect* policy.toolCallIdMode).is("strict9");
  });
});
