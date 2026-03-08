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
import { isCacheTtlEligibleProvider } from "./cache-ttl.js";

(deftest-group "kilocode cache-ttl eligibility", () => {
  (deftest "is eligible when model starts with anthropic/", () => {
    (expect* isCacheTtlEligibleProvider("kilocode", "anthropic/claude-opus-4.6")).is(true);
  });

  (deftest "is eligible with other anthropic models", () => {
    (expect* isCacheTtlEligibleProvider("kilocode", "anthropic/claude-sonnet-4")).is(true);
  });

  (deftest "is not eligible for non-anthropic models on kilocode", () => {
    (expect* isCacheTtlEligibleProvider("kilocode", "openai/gpt-5")).is(false);
  });

  (deftest "is case-insensitive for provider name", () => {
    (expect* isCacheTtlEligibleProvider("Kilocode", "anthropic/claude-opus-4.6")).is(true);
    (expect* isCacheTtlEligibleProvider("KILOCODE", "Anthropic/claude-opus-4.6")).is(true);
  });
});
