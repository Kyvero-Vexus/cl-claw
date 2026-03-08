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
import { sanitizeForLog, stripAnsi } from "./ansi.js";

(deftest-group "terminal ansi helpers", () => {
  (deftest "strips ANSI and OSC8 sequences", () => {
    (expect* stripAnsi("\u001B[31mred\u001B[0m")).is("red");
    (expect* stripAnsi("\u001B]8;;https://openclaw.ai\u001B\\link\u001B]8;;\u001B\\")).is("link");
  });

  (deftest "sanitizes control characters for log-safe interpolation", () => {
    const input = "\u001B[31mwarn\u001B[0m\r\nnext\u0000line\u007f";
    (expect* sanitizeForLog(input)).is("warnnextline");
  });
});
