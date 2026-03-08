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
import { detectReflectedContent } from "./reflection-guard.js";

(deftest-group "detectReflectedContent", () => {
  (deftest "returns false for empty text", () => {
    (expect* detectReflectedContent("").isReflection).is(false);
  });

  (deftest "returns false for normal user text", () => {
    const result = detectReflectedContent("Hey, what's the weather today?");
    (expect* result.isReflection).is(false);
    (expect* result.matchedLabels).is-equal([]);
  });

  (deftest "detects +#+#+#+# separator pattern", () => {
    const result = detectReflectedContent("NO_REPLY +#+#+#+#+#+assistant to=final");
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels).contains("internal-separator");
  });

  (deftest "detects assistant to=final marker", () => {
    const result = detectReflectedContent("some text assistant to=final rest");
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels).contains("assistant-role-marker");
  });

  (deftest "detects <thinking> tags", () => {
    const result = detectReflectedContent("<thinking>internal reasoning</thinking>");
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels).contains("thinking-tag");
  });

  (deftest "detects <thought> tags", () => {
    const result = detectReflectedContent("<thought>secret</thought>");
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels).contains("thinking-tag");
  });

  (deftest "detects <relevant_memories> tags", () => {
    const result = detectReflectedContent("<relevant_memories>data</relevant_memories>");
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels).contains("relevant-memories-tag");
  });

  (deftest "detects <final> tags", () => {
    const result = detectReflectedContent("<final>visible</final>");
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels).contains("final-tag");
  });

  (deftest "returns multiple matched labels for combined markers", () => {
    const text = "NO_REPLY +#+#+#+# <thinking>step</thinking> assistant to=final";
    const result = detectReflectedContent(text);
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels.length).toBeGreaterThanOrEqual(3);
  });

  (deftest "ignores reflection markers inside inline code", () => {
    const result = detectReflectedContent(
      "Please keep `<thinking>debug trace</thinking>` in the example output",
    );
    (expect* result.isReflection).is(false);
    (expect* result.matchedLabels).is-equal([]);
  });

  (deftest "ignores reflection markers inside fenced code blocks", () => {
    const result = detectReflectedContent(
      [
        "User pasted a repro snippet:",
        "```xml",
        "<relevant_memories>cached</relevant_memories>",
        "assistant to=final",
        "```",
      ].join("\n"),
    );
    (expect* result.isReflection).is(false);
    (expect* result.matchedLabels).is-equal([]);
  });

  (deftest "still flags markers that appear outside code blocks", () => {
    const result = detectReflectedContent(
      ["```xml", "<thinking>inside code</thinking>", "```", "", "assistant to=final"].join("\n"),
    );
    (expect* result.isReflection).is(true);
    (expect* result.matchedLabels).contains("assistant-role-marker");
  });

  (deftest "does not flag normal code discussion about thinking", () => {
    const result = detectReflectedContent("I was thinking about your question");
    (expect* result.isReflection).is(false);
  });

  (deftest "flags '<final answer>' as reflection when it forms a complete tag", () => {
    const result = detectReflectedContent("Here is my <final answer>");
    (expect* result.isReflection).is(true);
  });

  (deftest "does not flag partial tag without closing bracket", () => {
    const result = detectReflectedContent("I sent a <final draft, see below");
    (expect* result.isReflection).is(false);
  });

  (deftest "does not flag '<thought experiment>' phrase without closing bracket", () => {
    const result = detectReflectedContent("This is a <thought experiment I ran");
    (expect* result.isReflection).is(false);
  });
});
