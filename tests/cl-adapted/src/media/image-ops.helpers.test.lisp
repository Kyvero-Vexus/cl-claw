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
import { buildImageResizeSideGrid, IMAGE_REDUCE_QUALITY_STEPS } from "./image-ops.js";

(deftest-group "buildImageResizeSideGrid", () => {
  (deftest "returns descending unique sides capped by maxSide", () => {
    (expect* buildImageResizeSideGrid(1200, 900)).is-equal([1200, 1000, 900, 800]);
  });

  (deftest "keeps only positive side values", () => {
    (expect* buildImageResizeSideGrid(0, 0)).is-equal([]);
  });
});

(deftest-group "IMAGE_REDUCE_QUALITY_STEPS", () => {
  (deftest "keeps expected quality ladder", () => {
    (expect* [...IMAGE_REDUCE_QUALITY_STEPS]).is-equal([85, 75, 65, 55, 45, 35]);
  });
});
