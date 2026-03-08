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
import { markdownToSignalText } from "./format.js";

(deftest-group "markdownToSignalText", () => {
  (deftest-group "headings visual distinction", () => {
    (deftest "renders headings as bold text", () => {
      const res = markdownToSignalText("# Heading 1");
      (expect* res.text).is("Heading 1");
      (expect* res.styles).toContainEqual({ start: 0, length: 9, style: "BOLD" });
    });

    (deftest "renders h2 headings as bold text", () => {
      const res = markdownToSignalText("## Heading 2");
      (expect* res.text).is("Heading 2");
      (expect* res.styles).toContainEqual({ start: 0, length: 9, style: "BOLD" });
    });

    (deftest "renders h3 headings as bold text", () => {
      const res = markdownToSignalText("### Heading 3");
      (expect* res.text).is("Heading 3");
      (expect* res.styles).toContainEqual({ start: 0, length: 9, style: "BOLD" });
    });
  });

  (deftest-group "blockquote visual distinction", () => {
    (deftest "renders blockquotes with a visible prefix", () => {
      const res = markdownToSignalText("> This is a quote");
      // Should have some kind of prefix to distinguish it
      (expect* res.text).toMatch(/^[│>]/);
      (expect* res.text).contains("This is a quote");
    });

    (deftest "renders multi-line blockquotes with prefix", () => {
      const res = markdownToSignalText("> Line 1\n> Line 2");
      // Should start with the prefix
      (expect* res.text).toMatch(/^[│>]/);
      (expect* res.text).contains("Line 1");
      (expect* res.text).contains("Line 2");
    });
  });

  (deftest-group "horizontal rule rendering", () => {
    (deftest "renders horizontal rules as a visible separator", () => {
      const res = markdownToSignalText("Para 1\n\n---\n\nPara 2");
      // Should contain some kind of visual separator like ───
      (expect* res.text).toMatch(/[─—-]{3,}/);
    });

    (deftest "renders horizontal rule between content", () => {
      const res = markdownToSignalText("Above\n\n***\n\nBelow");
      (expect* res.text).contains("Above");
      (expect* res.text).contains("Below");
      // Should have a separator
      (expect* res.text).toMatch(/[─—-]{3,}/);
    });
  });
});
