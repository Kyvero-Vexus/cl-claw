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
import { summarizeAllowedValues } from "./allowed-values.js";

(deftest-group "summarizeAllowedValues", () => {
  (deftest "does not collapse mixed-type entries that stringify similarly", () => {
    const summary = summarizeAllowedValues([1, "1", 1, "1"]);
    (expect* summary).not.toBeNull();
    if (!summary) {
      return;
    }
    (expect* summary.hiddenCount).is(0);
    (expect* summary.formatted).contains('1, "1"');
    (expect* summary.values).has-length(2);
  });

  (deftest "keeps distinct long values even when labels truncate the same way", () => {
    const prefix = "a".repeat(200);
    const summary = summarizeAllowedValues([`${prefix}x`, `${prefix}y`]);
    (expect* summary).not.toBeNull();
    if (!summary) {
      return;
    }
    (expect* summary.hiddenCount).is(0);
    (expect* summary.values).has-length(2);
    (expect* summary.values[0]).not.is(summary.values[1]);
  });
});
