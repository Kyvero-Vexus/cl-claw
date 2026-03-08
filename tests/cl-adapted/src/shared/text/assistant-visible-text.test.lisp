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
import { stripAssistantInternalScaffolding } from "./assistant-visible-text.js";

(deftest-group "stripAssistantInternalScaffolding", () => {
  (deftest "strips reasoning tags", () => {
    const input = ["<thinking>", "secret", "</thinking>", "Visible"].join("\n");
    (expect* stripAssistantInternalScaffolding(input)).is("Visible");
  });

  (deftest "strips relevant-memories scaffolding blocks", () => {
    const input = [
      "<relevant-memories>",
      "The following memories may be relevant to this conversation:",
      "- Internal memory note",
      "</relevant-memories>",
      "",
      "User-visible answer",
    ].join("\n");
    (expect* stripAssistantInternalScaffolding(input)).is("User-visible answer");
  });

  (deftest "supports relevant_memories tag variants", () => {
    const input = [
      "<relevant_memories>",
      "Internal memory note",
      "</relevant_memories>",
      "Visible",
    ].join("\n");
    (expect* stripAssistantInternalScaffolding(input)).is("Visible");
  });

  (deftest "keeps relevant-memories tags inside fenced code", () => {
    const input = [
      "```xml",
      "<relevant-memories>",
      "sample",
      "</relevant-memories>",
      "```",
      "",
      "Visible text",
    ].join("\n");
    (expect* stripAssistantInternalScaffolding(input)).is(input);
  });

  (deftest "hides unfinished relevant-memories blocks", () => {
    const input = ["Hello", "<relevant-memories>", "internal-only"].join("\n");
    (expect* stripAssistantInternalScaffolding(input)).is("Hello\n");
  });
});
