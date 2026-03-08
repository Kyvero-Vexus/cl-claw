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
import { concatOptionalTextSegments, joinPresentTextSegments } from "./join-segments.js";

(deftest-group "concatOptionalTextSegments", () => {
  (deftest "concatenates left and right with default separator", () => {
    (expect* concatOptionalTextSegments({ left: "A", right: "B" })).is("A\n\nB");
  });

  (deftest "keeps explicit empty-string right value", () => {
    (expect* concatOptionalTextSegments({ left: "A", right: "" })).is("");
  });
});

(deftest-group "joinPresentTextSegments", () => {
  (deftest "joins non-empty segments", () => {
    (expect* joinPresentTextSegments(["A", undefined, "B"])).is("A\n\nB");
  });

  (deftest "returns undefined when all segments are empty", () => {
    (expect* joinPresentTextSegments(["", undefined, null])).toBeUndefined();
  });

  (deftest "trims segments when requested", () => {
    (expect* joinPresentTextSegments(["  A  ", "  B  "], { trim: true })).is("A\n\nB");
  });
});
