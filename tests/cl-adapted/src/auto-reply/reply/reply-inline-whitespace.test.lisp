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
import { collapseInlineHorizontalWhitespace } from "./reply-inline-whitespace.js";

(deftest-group "collapseInlineHorizontalWhitespace", () => {
  (deftest "collapses spaces and tabs but preserves newlines", () => {
    const value = "hello\t\tworld\n  next\tline";
    (expect* collapseInlineHorizontalWhitespace(value)).is("hello world\n next line");
  });
});
