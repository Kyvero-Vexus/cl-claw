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
import { shortenText } from "./text-format.js";

(deftest-group "shortenText", () => {
  (deftest "returns original text when it fits", () => {
    (expect* shortenText("openclaw", 16)).is("openclaw");
  });

  (deftest "truncates and appends ellipsis when over limit", () => {
    (expect* shortenText("openclaw-status-output", 10)).is("openclaw-…");
  });

  (deftest "counts multi-byte characters correctly", () => {
    (expect* shortenText("hello🙂world", 7)).is("hello🙂…");
  });
});
