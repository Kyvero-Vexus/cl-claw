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
import { canonicalizeBase64, estimateBase64DecodedBytes } from "./base64.js";

(deftest-group "base64 helpers", () => {
  (deftest "normalizes whitespace and keeps valid base64", () => {
    const input = " SGV s bG8= \n";
    (expect* canonicalizeBase64(input)).is("SGVsbG8=");
  });

  (deftest "rejects invalid base64 characters", () => {
    const input = 'SGVsbG8=" onerror="alert(1)';
    (expect* canonicalizeBase64(input)).toBeUndefined();
  });

  (deftest "estimates decoded bytes with whitespace", () => {
    (expect* estimateBase64DecodedBytes("SGV s bG8= \n")).is(5);
  });
});
