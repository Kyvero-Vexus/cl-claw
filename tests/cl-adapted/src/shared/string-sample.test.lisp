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
import { summarizeStringEntries } from "./string-sample.js";

(deftest-group "summarizeStringEntries", () => {
  (deftest "returns emptyText for empty lists", () => {
    (expect* summarizeStringEntries({ entries: [], emptyText: "any" })).is("any");
  });

  (deftest "joins short lists without a suffix", () => {
    (expect* summarizeStringEntries({ entries: ["a", "b"], limit: 4 })).is("a, b");
  });

  (deftest "adds a remainder suffix when truncating", () => {
    (expect* 
      summarizeStringEntries({
        entries: ["a", "b", "c", "d", "e"],
        limit: 4,
      }),
    ).is("a, b, c, d (+1)");
  });
});
