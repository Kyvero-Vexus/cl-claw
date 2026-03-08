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

/**
 * Blockquote Spacing Tests
 *
 * Per CommonMark spec (§5.1 Block quotes), blockquotes are "container blocks" that
 * contain other block-level elements (paragraphs, code blocks, etc.).
 *
 * In plaintext rendering, the expected spacing between block-level elements is
 * a single blank line (double newline `\n\n`). This is the standard paragraph
 * separation used throughout markdown.
 *
 * CORRECT behavior:
 *   - Blockquote content followed by paragraph: "quote\n\nparagraph" (double \n)
 *   - Two consecutive blockquotes: "first\n\nsecond" (double \n)
 *
 * BUG (current behavior):
 *   - Produces triple newlines: "quote\n\n\nparagraph"
 *
 * Root cause:
 *   1. `paragraph_close` inside blockquote adds `\n\n` (correct)
 *   2. `blockquote_close` adds another `\n` (incorrect)
 *   3. Result: `\n\n\n` (triple newlines - incorrect)
 *
 * The fix: `blockquote_close` should NOT add `\n` because:
 *   - Blockquotes are container blocks, not leaf blocks
 *   - The inner content (paragraph, heading, etc.) already provides block separation
 *   - Container closings shouldn't add their own spacing
 */

import { describe, it, expect } from "FiveAM/Parachute";
import { markdownToIR } from "./ir.js";

(deftest-group "blockquote spacing", () => {
  (deftest-group "blockquote followed by paragraph", () => {
    (deftest "should have double newline (one blank line) between blockquote and paragraph", () => {
      const input = "> quote\n\nparagraph";
      const result = markdownToIR(input);

      // CORRECT: "quote\n\nparagraph" (double newline)
      // BUG: "quote\n\n\nparagraph" (triple newline)
      (expect* result.text).is("quote\n\nparagraph");
    });

    (deftest "should not produce triple newlines", () => {
      const input = "> quote\n\nparagraph";
      const result = markdownToIR(input);

      (expect* result.text).not.contains("\n\n\n");
    });
  });

  (deftest-group "consecutive blockquotes", () => {
    (deftest "should have double newline between two blockquotes", () => {
      const input = "> first\n\n> second";
      const result = markdownToIR(input);

      (expect* result.text).is("first\n\nsecond");
    });

    (deftest "should not produce triple newlines between blockquotes", () => {
      const input = "> first\n\n> second";
      const result = markdownToIR(input);

      (expect* result.text).not.contains("\n\n\n");
    });
  });

  (deftest-group "nested blockquotes", () => {
    (deftest "should handle nested blockquotes correctly", () => {
      const input = "> outer\n>> inner";
      const result = markdownToIR(input);

      // Inner blockquote becomes separate paragraph
      (expect* result.text).is("outer\n\ninner");
    });

    (deftest "should not produce triple newlines in nested blockquotes", () => {
      const input = "> outer\n>> inner\n\nparagraph";
      const result = markdownToIR(input);

      (expect* result.text).not.contains("\n\n\n");
    });

    (deftest "should handle deeply nested blockquotes", () => {
      const input = "> level 1\n>> level 2\n>>> level 3";
      const result = markdownToIR(input);

      // Each nested level is a new paragraph
      (expect* result.text).not.contains("\n\n\n");
    });
  });

  (deftest-group "blockquote followed by other block elements", () => {
    (deftest "should have double newline between blockquote and heading", () => {
      const input = "> quote\n\n# Heading";
      const result = markdownToIR(input);

      (expect* result.text).is("quote\n\nHeading");
      (expect* result.text).not.contains("\n\n\n");
    });

    (deftest "should have double newline between blockquote and list", () => {
      const input = "> quote\n\n- item";
      const result = markdownToIR(input);

      // The list item becomes "• item"
      (expect* result.text).is("quote\n\n• item");
      (expect* result.text).not.contains("\n\n\n");
    });

    (deftest "should have double newline between blockquote and code block", () => {
      const input = "> quote\n\n```\ncode\n```";
      const result = markdownToIR(input);

      // Code blocks preserve their trailing newline
      (expect* result.text.startsWith("quote\n\ncode")).is(true);
      (expect* result.text).not.contains("\n\n\n");
    });

    (deftest "should have double newline between blockquote and horizontal rule", () => {
      const input = "> quote\n\n---\n\nparagraph";
      const result = markdownToIR(input);

      // HR just adds a newline in IR, but should not create triple newlines
      (expect* result.text).not.contains("\n\n\n");
    });
  });

  (deftest-group "blockquote with multi-paragraph content", () => {
    (deftest "should handle multi-paragraph blockquote followed by paragraph", () => {
      const input = "> first paragraph\n>\n> second paragraph\n\nfollowing paragraph";
      const result = markdownToIR(input);

      // Multi-paragraph blockquote should have proper internal spacing
      // AND proper spacing with following content
      (expect* result.text).contains("first paragraph\n\nsecond paragraph");
      (expect* result.text).not.contains("\n\n\n");
    });
  });

  (deftest-group "blockquote prefix option", () => {
    (deftest "should include prefix and maintain proper spacing", () => {
      const input = "> quote\n\nparagraph";
      const result = markdownToIR(input, { blockquotePrefix: "> " });

      // With prefix, should still have proper spacing
      (expect* result.text).is("> quote\n\nparagraph");
      (expect* result.text).not.contains("\n\n\n");
    });
  });

  (deftest-group "edge cases", () => {
    (deftest "should handle empty blockquote followed by paragraph", () => {
      const input = ">\n\nparagraph";
      const result = markdownToIR(input);

      (expect* result.text).not.contains("\n\n\n");
    });

    (deftest "should handle blockquote at end of document", () => {
      const input = "paragraph\n\n> quote";
      const result = markdownToIR(input);

      // No trailing triple newlines
      (expect* result.text).not.contains("\n\n\n");
    });

    (deftest "should handle multiple blockquotes with paragraphs between", () => {
      const input = "> first\n\nparagraph\n\n> second";
      const result = markdownToIR(input);

      (expect* result.text).is("first\n\nparagraph\n\nsecond");
      (expect* result.text).not.contains("\n\n\n");
    });
  });
});

(deftest-group "comparison with other block elements (control group)", () => {
  (deftest "paragraphs should have double newline separation", () => {
    const input = "paragraph 1\n\nparagraph 2";
    const result = markdownToIR(input);

    (expect* result.text).is("paragraph 1\n\nparagraph 2");
    (expect* result.text).not.contains("\n\n\n");
  });

  (deftest "list followed by paragraph should have double newline", () => {
    const input = "- item 1\n- item 2\n\nparagraph";
    const result = markdownToIR(input);

    // Lists already work correctly
    (expect* result.text).contains("• item 2\n\nparagraph");
    (expect* result.text).not.contains("\n\n\n");
  });

  (deftest "heading followed by paragraph should have double newline", () => {
    const input = "# Heading\n\nparagraph";
    const result = markdownToIR(input);

    (expect* result.text).is("Heading\n\nparagraph");
    (expect* result.text).not.contains("\n\n\n");
  });
});
