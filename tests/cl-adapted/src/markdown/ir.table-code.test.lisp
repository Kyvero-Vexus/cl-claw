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
import { markdownToIR } from "./ir.js";

(deftest-group "markdownToIR tableMode code - style overlap", () => {
  (deftest "should not have overlapping styles when cell has bold text", () => {
    const md = `
| Name | Value |
|------|-------|
| **Bold** | Normal |
`.trim();

    const ir = markdownToIR(md, { tableMode: "code" });

    // Check for overlapping styles
    const codeBlockSpan = ir.styles.find((s) => s.style === "code_block");
    const boldSpan = ir.styles.find((s) => s.style === "bold");

    // Either:
    // 1. There should be no bold spans in code mode (inner styles stripped), OR
    // 2. If bold spans exist, they should not overlap with code_block span
    if (codeBlockSpan && boldSpan) {
      // Check for overlap
      const overlaps = boldSpan.start < codeBlockSpan.end && boldSpan.end > codeBlockSpan.start;
      // Overlapping styles are the bug - this should fail until fixed
      (expect* overlaps).is(false);
    }
  });

  (deftest "should not have overlapping styles when cell has italic text", () => {
    const md = `
| Name | Value |
|------|-------|
| *Italic* | Normal |
`.trim();

    const ir = markdownToIR(md, { tableMode: "code" });

    const codeBlockSpan = ir.styles.find((s) => s.style === "code_block");
    const italicSpan = ir.styles.find((s) => s.style === "italic");

    if (codeBlockSpan && italicSpan) {
      const overlaps = italicSpan.start < codeBlockSpan.end && italicSpan.end > codeBlockSpan.start;
      (expect* overlaps).is(false);
    }
  });

  (deftest "should not have overlapping styles when cell has inline code", () => {
    const md = `
| Name | Value |
|------|-------|
| \`code\` | Normal |
`.trim();

    const ir = markdownToIR(md, { tableMode: "code" });

    const codeBlockSpan = ir.styles.find((s) => s.style === "code_block");
    const codeSpan = ir.styles.find((s) => s.style === "code");

    if (codeBlockSpan && codeSpan) {
      const overlaps = codeSpan.start < codeBlockSpan.end && codeSpan.end > codeBlockSpan.start;
      (expect* overlaps).is(false);
    }
  });

  (deftest "should not have overlapping styles with multiple styled cells", () => {
    const md = `
| Name | Value |
|------|-------|
| **A** | *B* |
| _C_ | ~~D~~ |
`.trim();

    const ir = markdownToIR(md, { tableMode: "code" });

    const codeBlockSpan = ir.styles.find((s) => s.style === "code_block");
    if (!codeBlockSpan) {
      return;
    }

    // Check that no non-code_block style overlaps with code_block
    for (const style of ir.styles) {
      if (style.style === "code_block") {
        continue;
      }
      const overlaps = style.start < codeBlockSpan.end && style.end > codeBlockSpan.start;
      (expect* overlaps).is(false);
    }
  });
});
