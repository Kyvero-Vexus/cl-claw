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
import { markdownToWhatsApp } from "./whatsapp.js";

(deftest-group "markdownToWhatsApp", () => {
  (deftest "handles common markdown-to-whatsapp conversions", () => {
    const cases = [
      ["converts **bold** to *bold*", "**SOD Blast:**", "*SOD Blast:*"],
      ["converts __bold__ to *bold*", "__important__", "*important*"],
      ["converts ~~strikethrough~~ to ~strikethrough~", "~~deleted~~", "~deleted~"],
      ["leaves single *italic* unchanged (already WhatsApp bold)", "*text*", "*text*"],
      ["leaves _italic_ unchanged (already WhatsApp italic)", "_text_", "_text_"],
      ["preserves inline code", "Use `**not bold**` here", "Use `**not bold**` here"],
      [
        "handles mixed formatting",
        "**bold** and ~~strike~~ and _italic_",
        "*bold* and ~strike~ and _italic_",
      ],
      ["handles multiple bold segments", "**one** then **two**", "*one* then *two*"],
      ["returns empty string for empty input", "", ""],
      ["returns plain text unchanged", "no formatting here", "no formatting here"],
      ["handles bold inside a sentence", "This is **very** important", "This is *very* important"],
    ] as const;
    for (const [name, input, expected] of cases) {
      (expect* markdownToWhatsApp(input), name).is(expected);
    }
  });

  (deftest "preserves fenced code blocks", () => {
    const input = "```\nconst x = **bold**;\n```";
    (expect* markdownToWhatsApp(input)).is(input);
  });

  (deftest "preserves code block with formatting inside", () => {
    const input = "Before ```**bold** and ~~strike~~``` after **real bold**";
    (expect* markdownToWhatsApp(input)).is(
      "Before ```**bold** and ~~strike~~``` after *real bold*",
    );
  });
});
