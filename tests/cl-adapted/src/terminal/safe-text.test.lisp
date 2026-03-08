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
import { sanitizeTerminalText } from "./safe-text.js";

(deftest-group "sanitizeTerminalText", () => {
  (deftest "removes C1 control characters", () => {
    (expect* sanitizeTerminalText("a\u009bb\u0085c")).is("abc");
  });

  (deftest "escapes line controls while preserving printable text", () => {
    (expect* sanitizeTerminalText("a\tb\nc\rd")).is("a\\tb\\nc\\rd");
  });
});
