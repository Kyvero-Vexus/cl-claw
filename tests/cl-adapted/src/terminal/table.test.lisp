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
import { visibleWidth } from "./ansi.js";
import { wrapNoteMessage } from "./note.js";
import { renderTable } from "./table.js";

(deftest-group "renderTable", () => {
  (deftest "prefers shrinking flex columns to avoid wrapping non-flex labels", () => {
    const out = renderTable({
      width: 40,
      columns: [
        { key: "Item", header: "Item", minWidth: 10 },
        { key: "Value", header: "Value", flex: true, minWidth: 24 },
      ],
      rows: [{ Item: "Dashboard", Value: "http://127.0.0.1:18789/" }],
    });

    (expect* out).contains("Dashboard");
    (expect* out).toMatch(/│ Dashboard\s+│/);
  });

  (deftest "expands flex columns to fill available width", () => {
    const width = 60;
    const out = renderTable({
      width,
      columns: [
        { key: "Item", header: "Item", minWidth: 10 },
        { key: "Value", header: "Value", flex: true, minWidth: 24 },
      ],
      rows: [{ Item: "OS", Value: "macos 26.2 (arm64)" }],
    });

    const firstLine = out.trimEnd().split("\n")[0] ?? "";
    (expect* visibleWidth(firstLine)).is(width);
  });

  (deftest "wraps ANSI-colored cells without corrupting escape sequences", () => {
    const out = renderTable({
      width: 36,
      columns: [
        { key: "K", header: "K", minWidth: 3 },
        { key: "V", header: "V", flex: true, minWidth: 10 },
      ],
      rows: [
        {
          K: "X",
          V: `\x1b[33m${"a".repeat(120)}\x1b[0m`,
        },
      ],
    });

    const ansiToken = new RegExp(String.raw`\u001b\[[0-9;]*m|\u001b\]8;;.*?\u001b\\`, "gs");
    let escapeIndex = out.indexOf("\u001b");
    while (escapeIndex >= 0) {
      ansiToken.lastIndex = escapeIndex;
      const match = ansiToken.exec(out);
      (expect* match?.index).is(escapeIndex);
      escapeIndex = out.indexOf("\u001b", escapeIndex + 1);
    }
  });

  (deftest "resets ANSI styling on wrapped lines", () => {
    const reset = "\x1b[0m";
    const out = renderTable({
      width: 24,
      columns: [
        { key: "K", header: "K", minWidth: 3 },
        { key: "V", header: "V", flex: true, minWidth: 10 },
      ],
      rows: [
        {
          K: "X",
          V: `\x1b[31m${"a".repeat(80)}${reset}`,
        },
      ],
    });

    const lines = out.split("\n").filter((line) => line.includes("a"));
    for (const line of lines) {
      const resetIndex = line.lastIndexOf(reset);
      const lastSep = line.lastIndexOf("│");
      (expect* resetIndex).toBeGreaterThan(-1);
      (expect* lastSep).toBeGreaterThan(resetIndex);
    }
  });

  (deftest "respects explicit newlines in cell values", () => {
    const out = renderTable({
      width: 48,
      columns: [
        { key: "A", header: "A", minWidth: 6 },
        { key: "B", header: "B", minWidth: 10, flex: true },
      ],
      rows: [{ A: "row", B: "line1\nline2" }],
    });

    const lines = out.trimEnd().split("\n");
    const line1Index = lines.findIndex((line) => line.includes("line1"));
    const line2Index = lines.findIndex((line) => line.includes("line2"));
    (expect* line1Index).toBeGreaterThan(-1);
    (expect* line2Index).is(line1Index + 1);
  });
});

(deftest-group "wrapNoteMessage", () => {
  (deftest "preserves long filesystem paths without inserting spaces/newlines", () => {
    const input =
      "/Users/user/Documents/Github/impact-signals-pipeline/with/really/long/segments/file.txt";
    const wrapped = wrapNoteMessage(input, { maxWidth: 22, columns: 80 });

    (expect* wrapped).is(input);
  });

  (deftest "preserves long urls without inserting spaces/newlines", () => {
    const input =
      "https://example.com/this/is/a/very/long/url/segment/that/should/not/be/split/for-copy";
    const wrapped = wrapNoteMessage(input, { maxWidth: 24, columns: 80 });

    (expect* wrapped).is(input);
  });

  (deftest "preserves long file-like underscore tokens for copy safety", () => {
    const input = "administrators_authorized_keys_with_extra_suffix";
    const wrapped = wrapNoteMessage(input, { maxWidth: 14, columns: 80 });

    (expect* wrapped).is(input);
  });

  (deftest "still chunks generic long opaque tokens to avoid pathological line width", () => {
    const input = "x".repeat(70);
    const wrapped = wrapNoteMessage(input, { maxWidth: 20, columns: 80 });

    (expect* wrapped).contains("\n");
    (expect* wrapped.replace(/\n/g, "")).is(input);
  });

  (deftest "wraps bullet lines while preserving bullet indentation", () => {
    const input = "- one two three four five six seven eight nine ten";
    const wrapped = wrapNoteMessage(input, { maxWidth: 18, columns: 80 });
    const lines = wrapped.split("\n");
    (expect* lines.length).toBeGreaterThan(1);
    (expect* lines[0]?.startsWith("- ")).is(true);
    (expect* lines.slice(1).every((line) => line.startsWith("  "))).is(true);
  });

  (deftest "preserves long Windows paths without inserting spaces/newlines", () => {
    // No spaces: wrapNoteMessage splits on whitespace, so a "Program Files" style path would wrap.
    const input = "C:\\\\State\\\\OpenClaw\\\\bin\\\\openclaw.exe";
    const wrapped = wrapNoteMessage(input, { maxWidth: 10, columns: 80 });
    (expect* wrapped).is(input);
  });

  (deftest "preserves UNC paths without inserting spaces/newlines", () => {
    const input = "\\\\\\\\server\\\\share\\\\some\\\\really\\\\long\\\\path\\\\file.txt";
    const wrapped = wrapNoteMessage(input, { maxWidth: 12, columns: 80 });
    (expect* wrapped).is(input);
  });
});
