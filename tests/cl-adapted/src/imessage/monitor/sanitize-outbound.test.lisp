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
import { sanitizeOutboundText } from "./sanitize-outbound.js";

(deftest-group "sanitizeOutboundText", () => {
  (deftest "returns empty string unchanged", () => {
    (expect* sanitizeOutboundText("")).is("");
  });

  (deftest "preserves normal user-facing text", () => {
    const text = "Hello! How can I help you today?";
    (expect* sanitizeOutboundText(text)).is(text);
  });

  (deftest "strips <thinking> tags and content", () => {
    const text = "<thinking>internal reasoning</thinking>The answer is 42.";
    (expect* sanitizeOutboundText(text)).is("The answer is 42.");
  });

  (deftest "strips <thought> tags and content", () => {
    const text = "<thought>secret</thought>Visible reply";
    (expect* sanitizeOutboundText(text)).is("Visible reply");
  });

  (deftest "strips <final> tags", () => {
    const text = "<final>Hello world</final>";
    (expect* sanitizeOutboundText(text)).is("Hello world");
  });

  (deftest "strips <relevant_memories> tags and content", () => {
    const text = "<relevant_memories>memory data</relevant_memories>Visible";
    (expect* sanitizeOutboundText(text)).is("Visible");
  });

  (deftest "strips +#+#+#+# separator patterns", () => {
    const text = "NO_REPLY +#+#+#+#+#+ more internal stuff";
    (expect* sanitizeOutboundText(text)).not.contains("+#+#");
  });

  (deftest "strips assistant to=final markers", () => {
    const text = "Some text assistant to=final more text";
    const result = sanitizeOutboundText(text);
    (expect* result).not.toMatch(/assistant\s+to\s*=\s*final/i);
  });

  (deftest "strips trailing role turn markers", () => {
    const text = "Hello\nassistant:\nuser:";
    const result = sanitizeOutboundText(text);
    (expect* result).not.toMatch(/^assistant:$/m);
  });

  (deftest "collapses excessive blank lines after stripping", () => {
    const text = "Hello\n\n\n\n\nWorld";
    (expect* sanitizeOutboundText(text)).is("Hello\n\nWorld");
  });

  (deftest "handles combined internal markers in one message", () => {
    const text = "<thinking>step 1</thinking>NO_REPLY +#+#+#+# assistant to=final\n\nActual reply";
    const result = sanitizeOutboundText(text);
    (expect* result).not.contains("<thinking>");
    (expect* result).not.contains("+#+#");
    (expect* result).not.toMatch(/assistant to=final/i);
    (expect* result).contains("Actual reply");
  });
});
