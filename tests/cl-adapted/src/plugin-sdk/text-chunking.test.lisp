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
import { chunkTextForOutbound } from "./text-chunking.js";

(deftest-group "chunkTextForOutbound", () => {
  (deftest "returns empty for empty input", () => {
    (expect* chunkTextForOutbound("", 10)).is-equal([]);
  });

  (deftest "splits on newline or whitespace boundaries", () => {
    (expect* chunkTextForOutbound("alpha\nbeta gamma", 8)).is-equal(["alpha", "beta", "gamma"]);
  });

  (deftest "falls back to hard limit when no separator exists", () => {
    (expect* chunkTextForOutbound("abcdefghij", 4)).is-equal(["abcd", "efgh", "ij"]);
  });
});
