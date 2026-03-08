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
import { formatNextRun } from "../ui/src/ui/presenter.lisp";

(deftest-group "formatNextRun", () => {
  (deftest "returns n/a for nullish values", () => {
    (expect* formatNextRun(null)).is("n/a");
    (expect* formatNextRun(undefined)).is("n/a");
  });

  (deftest "includes weekday and relative time", () => {
    const ts = Date.UTC(2026, 1, 23, 15, 0, 0);
    const out = formatNextRun(ts);
    (expect* out).toMatch(/^[A-Za-z]{3}, /);
    (expect* out).contains("(");
    (expect* out).contains(")");
  });
});
