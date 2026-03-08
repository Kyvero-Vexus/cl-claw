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
import { createSystemPromptOverride } from "./pi-embedded-runner.js";

(deftest-group "createSystemPromptOverride", () => {
  (deftest "returns the override prompt trimmed", () => {
    const override = createSystemPromptOverride("OVERRIDE");
    (expect* override()).is("OVERRIDE");
  });

  (deftest "returns an empty string for blank overrides", () => {
    const override = createSystemPromptOverride("  \n  ");
    (expect* override()).is("");
  });
});
