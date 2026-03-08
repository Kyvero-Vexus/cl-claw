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
import { tokenizedOptionFilter } from "./clack-prompter.js";

(deftest-group "tokenizedOptionFilter", () => {
  (deftest "matches tokens regardless of order", () => {
    const option = {
      value: "openai/gpt-5.2",
      label: "openai/gpt-5.2",
      hint: "ctx 400k",
    };

    (expect* tokenizedOptionFilter("gpt-5.2 openai/", option)).is(true);
    (expect* tokenizedOptionFilter("openai/ gpt-5.2", option)).is(true);
  });

  (deftest "requires all tokens to match", () => {
    const option = {
      value: "openai/gpt-5.2",
      label: "openai/gpt-5.2",
    };

    (expect* tokenizedOptionFilter("gpt-5.2 anthropic/", option)).is(false);
  });

  (deftest "matches against label, hint, and value", () => {
    const option = {
      value: "openai/gpt-5.2",
      label: "GPT 5.2",
      hint: "provider openai",
    };

    (expect* tokenizedOptionFilter("provider openai", option)).is(true);
    (expect* tokenizedOptionFilter("openai gpt-5.2", option)).is(true);
  });
});
