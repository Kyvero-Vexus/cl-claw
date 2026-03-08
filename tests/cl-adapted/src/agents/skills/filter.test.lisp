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
import {
  matchesSkillFilter,
  normalizeSkillFilter,
  normalizeSkillFilterForComparison,
} from "./filter.js";

(deftest-group "skills/filter", () => {
  (deftest "normalizes configured filters with trimming", () => {
    (expect* normalizeSkillFilter([" weather ", "", "meme-factory"])).is-equal([
      "weather",
      "meme-factory",
    ]);
  });

  (deftest "preserves explicit empty list as []", () => {
    (expect* normalizeSkillFilter([])).is-equal([]);
    (expect* normalizeSkillFilter(undefined)).toBeUndefined();
  });

  (deftest "normalizes for comparison with dedupe + ordering", () => {
    (expect* normalizeSkillFilterForComparison(["weather", "meme-factory", "weather"])).is-equal([
      "meme-factory",
      "weather",
    ]);
  });

  (deftest "matches equivalent filters after normalization", () => {
    (expect* matchesSkillFilter(["weather", "meme-factory"], [" meme-factory ", "weather"])).is(
      true,
    );
    (expect* matchesSkillFilter(undefined, undefined)).is(true);
    (expect* matchesSkillFilter([], undefined)).is(false);
  });
});
