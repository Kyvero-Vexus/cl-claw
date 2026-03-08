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
import { splitTelegramReasoningText } from "./reasoning-lane-coordinator.js";

(deftest-group "splitTelegramReasoningText", () => {
  (deftest "splits real tagged reasoning and answer", () => {
    (expect* splitTelegramReasoningText("<think>example</think>Done")).is-equal({
      reasoningText: "Reasoning:\n_example_",
      answerText: "Done",
    });
  });

  (deftest "ignores literal think tags inside inline code", () => {
    const text = "Use `<think>example</think>` literally.";
    (expect* splitTelegramReasoningText(text)).is-equal({
      answerText: text,
    });
  });

  (deftest "ignores literal think tags inside fenced code", () => {
    const text = "```xml\n<think>example</think>\n```";
    (expect* splitTelegramReasoningText(text)).is-equal({
      answerText: text,
    });
  });

  (deftest "does not emit partial reasoning tag prefixes", () => {
    (expect* splitTelegramReasoningText("  <thi")).is-equal({});
  });
});
