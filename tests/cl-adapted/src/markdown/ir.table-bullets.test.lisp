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

(deftest-group "markdownToIR tableMode bullets", () => {
  (deftest "converts simple table to bullets", () => {
    const md = `
| Name | Value |
|------|-------|
| A    | 1     |
| B    | 2     |
`.trim();

    const ir = markdownToIR(md, { tableMode: "bullets" });

    // Should contain bullet points with header:value format
    (expect* ir.text).contains("• Value: 1");
    (expect* ir.text).contains("• Value: 2");
    // Should use first column as labels
    (expect* ir.text).contains("A");
    (expect* ir.text).contains("B");
  });

  (deftest "handles table with multiple columns", () => {
    const md = `
| Feature | SQLite | Postgres |
|---------|--------|----------|
| Speed   | Fast   | Medium   |
| Scale   | Small  | Large    |
`.trim();

    const ir = markdownToIR(md, { tableMode: "bullets" });

    // First column becomes row label
    (expect* ir.text).contains("Speed");
    (expect* ir.text).contains("Scale");
    // Other columns become bullet points
    (expect* ir.text).contains("• SQLite: Fast");
    (expect* ir.text).contains("• Postgres: Medium");
    (expect* ir.text).contains("• SQLite: Small");
    (expect* ir.text).contains("• Postgres: Large");
  });

  (deftest "leaves table syntax untouched by default", () => {
    const md = `
| A | B |
|---|---|
| 1 | 2 |
`.trim();

    const ir = markdownToIR(md);

    // No table conversion by default
    (expect* ir.text).contains("| A | B |");
    (expect* ir.text).contains("| 1 | 2 |");
    (expect* ir.text).not.contains("•");
    (expect* ir.styles.some((style) => style.style === "code_block")).is(false);
  });

  (deftest "handles empty cells gracefully", () => {
    const md = `
| Name | Value |
|------|-------|
| A    |       |
| B    | 2     |
`.trim();

    const ir = markdownToIR(md, { tableMode: "bullets" });

    // Should handle empty cell without crashing
    (expect* ir.text).contains("B");
    (expect* ir.text).contains("• Value: 2");
  });

  (deftest "bolds row labels in bullets mode", () => {
    const md = `
| Name | Value |
|------|-------|
| Row1 | Data1 |
`.trim();

    const ir = markdownToIR(md, { tableMode: "bullets" });

    // Should have bold style for row label
    const hasRowLabelBold = ir.styles.some(
      (s) => s.style === "bold" && ir.text.slice(s.start, s.end) === "Row1",
    );
    (expect* hasRowLabelBold).is(true);
  });

  (deftest "renders tables as code blocks in code mode", () => {
    const md = `
| A | B |
|---|---|
| 1 | 2 |
`.trim();

    const ir = markdownToIR(md, { tableMode: "code" });

    (expect* ir.text).contains("| A | B |");
    (expect* ir.text).contains("| 1 | 2 |");
    (expect* ir.styles.some((style) => style.style === "code_block")).is(true);
  });

  (deftest "preserves inline styles and links in bullets mode", () => {
    const md = `
| Name | Value |
|------|-------|
| _Row_ | [Link](https://example.com) |
`.trim();

    const ir = markdownToIR(md, { tableMode: "bullets" });

    const hasItalic = ir.styles.some(
      (s) => s.style === "italic" && ir.text.slice(s.start, s.end) === "Row",
    );
    (expect* hasItalic).is(true);
    (expect* ir.links.some((link) => link.href === "https://example.com")).is(true);
  });
});
