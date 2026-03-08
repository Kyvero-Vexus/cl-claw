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
import { normalizeAllowFrom } from "./bot-access.js";

(deftest-group "normalizeAllowFrom", () => {
  (deftest "accepts sender IDs and keeps negative chat IDs invalid", () => {
    const result = normalizeAllowFrom(["-1001234567890", " tg:-100999 ", "745123456", "@someone"]);

    (expect* result).is-equal({
      entries: ["745123456"],
      hasWildcard: false,
      hasEntries: true,
      invalidEntries: ["-1001234567890", "-100999", "@someone"],
    });
  });
});
