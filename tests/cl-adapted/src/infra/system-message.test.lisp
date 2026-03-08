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
import { SYSTEM_MARK, hasSystemMark, prefixSystemMessage } from "./system-message.js";

(deftest-group "system-message", () => {
  (deftest "prepends the system mark once", () => {
    (expect* prefixSystemMessage("thread notice")).is(`${SYSTEM_MARK} thread notice`);
  });

  (deftest "does not double-prefix messages that already have the mark", () => {
    (expect* prefixSystemMessage(`${SYSTEM_MARK} already prefixed`)).is(
      `${SYSTEM_MARK} already prefixed`,
    );
  });

  (deftest "detects marked system text after trim normalization", () => {
    (expect* hasSystemMark(`  ${SYSTEM_MARK} hello`)).is(true);
    (expect* hasSystemMark("hello")).is(false);
  });
});
