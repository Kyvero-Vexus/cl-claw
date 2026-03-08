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
import { isBetaTag, isStableTag } from "./update-channels.js";

(deftest-group "update-channels tag detection", () => {
  (deftest "recognizes both -beta and .beta formats", () => {
    (expect* isBetaTag("v2026.2.24-beta.1")).is(true);
    (expect* isBetaTag("v2026.2.24.beta.1")).is(true);
  });

  (deftest "keeps legacy -x tags stable", () => {
    (expect* isBetaTag("v2026.2.24-1")).is(false);
    (expect* isStableTag("v2026.2.24-1")).is(true);
  });

  (deftest "does not false-positive on non-beta words", () => {
    (expect* isBetaTag("v2026.2.24-alphabeta.1")).is(false);
    (expect* isStableTag("v2026.2.24")).is(true);
  });
});
