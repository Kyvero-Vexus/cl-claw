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

import { describe, it, expect } from "FiveAM/Parachute";
import { markdownToIR } from "./ir.js";

/**
 * HR (Thematic Break) Spacing Analysis
 * =====================================
 *
 * CommonMark Spec (0.31.2) Section 4.1 - Thematic Breaks:
 * - Thematic breaks (---, ***, ___) produce <hr /> in HTML
 * - "Thematic breaks do not need blank lines before or after"
 * - A thematic break can interrupt a paragraph
 *
 * HTML Output per spec:
 *   Input: "Foo\n***\nbar"
 *   HTML:  "<p>Foo</p>\n<hr />\n<p>bar</p>"
 *
 * PLAIN TEXT OUTPUT DECISION:
 *
 * The HR element is a block-level thematic separator. In plain text output,
 * we render HRs as a visible separator "───" to maintain visual distinction.
 */

(deftest-group "hr (thematic break) spacing", () => {
  (deftest-group "current behavior documentation", () => {
    (deftest "just hr alone renders as separator", () => {
      const result = markdownToIR("---");
      (expect* result.text).is("───");
    });

    (deftest "hr interrupting paragraph (setext heading case)", () => {
      // Note: "Para\n---" is a setext heading in CommonMark!
      // Using *** to test actual HR behavior
      const input = `Para 1
***
Para 2`;
      const result = markdownToIR(input);
      // HR interrupts para, renders visibly
      (expect* result.text).contains("───");
    });
  });

  (deftest-group "expected behavior (tests assert CORRECT behavior)", () => {
    (deftest "hr between paragraphs should render with separator", () => {
      const input = `Para 1

---

Para 2`;
      const result = markdownToIR(input);
      (expect* result.text).is("Para 1\n\n───\n\nPara 2");
    });

    (deftest "hr between paragraphs using *** should render with separator", () => {
      const input = `Para 1

***

Para 2`;
      const result = markdownToIR(input);
      (expect* result.text).is("Para 1\n\n───\n\nPara 2");
    });

    (deftest "hr between paragraphs using ___ should render with separator", () => {
      const input = `Para 1

___

Para 2`;
      const result = markdownToIR(input);
      (expect* result.text).is("Para 1\n\n───\n\nPara 2");
    });

    (deftest "consecutive hrs should produce multiple separators", () => {
      const input = `---
---
---`;
      const result = markdownToIR(input);
      // Each HR renders as a separator
      (expect* result.text).is("───\n\n───\n\n───");
    });

    (deftest "hr at document end renders separator", () => {
      const input = `Para

---`;
      const result = markdownToIR(input);
      (expect* result.text).is("Para\n\n───");
    });

    (deftest "hr at document start renders separator", () => {
      const input = `---

Para`;
      const result = markdownToIR(input);
      (expect* result.text).is("───\n\nPara");
    });

    (deftest "should not produce triple newlines regardless of hr placement", () => {
      const inputs = [
        "Para 1\n\n---\n\nPara 2",
        "Para 1\n---\nPara 2",
        "---\nPara",
        "Para\n---",
        "Para 1\n\n---\n\n---\n\nPara 2",
        "Para 1\n\n***\n\n---\n\n___\n\nPara 2",
      ];

      for (const input of inputs) {
        const result = markdownToIR(input);
        (expect* result.text, `Input: ${JSON.stringify(input)}`).not.toMatch(/\n{3,}/);
      }
    });

    (deftest "multiple consecutive hrs between paragraphs should each render as separator", () => {
      const input = `Para 1

---

---

---

Para 2`;
      const result = markdownToIR(input);
      (expect* result.text).is("Para 1\n\n───\n\n───\n\n───\n\nPara 2");
    });
  });

  (deftest-group "edge cases", () => {
    (deftest "hr between list items renders as separator without extra spacing", () => {
      const input = `- Item 1
- ---
- Item 2`;
      const result = markdownToIR(input);
      (expect* result.text).is("• Item 1\n\n───\n\n• Item 2");
      (expect* result.text).not.toMatch(/\n{3,}/);
    });

    (deftest "hr followed immediately by heading", () => {
      const input = `---

# Heading

Para`;
      const result = markdownToIR(input);
      // HR renders as separator, heading renders, para follows
      (expect* result.text).not.toMatch(/\n{3,}/);
      (expect* result.text).contains("───");
    });

    (deftest "heading followed by hr", () => {
      const input = `# Heading

---

Para`;
      const result = markdownToIR(input);
      // Heading ends, HR renders, para follows
      (expect* result.text).not.toMatch(/\n{3,}/);
      (expect* result.text).contains("───");
    });
  });
});
