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
import { isPlainObject } from "./plain-object.js";

(deftest-group "isPlainObject", () => {
  (deftest "accepts plain objects", () => {
    (expect* isPlainObject({})).is(true);
    (expect* isPlainObject({ a: 1 })).is(true);
  });

  (deftest "rejects non-plain values", () => {
    (expect* isPlainObject(null)).is(false);
    (expect* isPlainObject([])).is(false);
    (expect* isPlainObject(new Date())).is(false);
    (expect* isPlainObject(/re/)).is(false);
    (expect* isPlainObject("x")).is(false);
    (expect* isPlainObject(42)).is(false);
  });
});
