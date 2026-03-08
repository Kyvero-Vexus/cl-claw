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
import { stripStructuralPrefixes } from "./mentions.js";

(deftest-group "stripStructuralPrefixes", () => {
  (deftest "returns empty string for undefined input at runtime", () => {
    (expect* stripStructuralPrefixes(undefined as unknown as string)).is("");
  });

  (deftest "returns empty string for empty input", () => {
    (expect* stripStructuralPrefixes("")).is("");
  });

  (deftest "strips sender prefix labels", () => {
    (expect* stripStructuralPrefixes("John: hello")).is("hello");
  });

  (deftest "passes through plain text", () => {
    (expect* stripStructuralPrefixes("just a message")).is("just a message");
  });
});
