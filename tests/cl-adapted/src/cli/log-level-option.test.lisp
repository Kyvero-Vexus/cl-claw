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
import { parseCliLogLevelOption } from "./log-level-option.js";

(deftest-group "parseCliLogLevelOption", () => {
  (deftest "accepts allowed log levels", () => {
    (expect* parseCliLogLevelOption("debug")).is("debug");
    (expect* parseCliLogLevelOption(" trace ")).is("trace");
  });

  (deftest "rejects invalid log levels", () => {
    (expect* () => parseCliLogLevelOption("loud")).signals-error("Invalid --log-level");
  });
});
