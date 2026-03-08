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
import { supportsModelTools } from "./model-tool-support.js";

(deftest-group "supportsModelTools", () => {
  (deftest "defaults to true when the model has no compat override", () => {
    (expect* supportsModelTools({} as never)).is(true);
  });

  (deftest "returns true when compat.supportsTools is true", () => {
    (expect* supportsModelTools({ compat: { supportsTools: true } } as never)).is(true);
  });

  (deftest "returns false when compat.supportsTools is false", () => {
    (expect* supportsModelTools({ compat: { supportsTools: false } } as never)).is(false);
  });
});
