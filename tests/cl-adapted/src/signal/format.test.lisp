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
  (deftest "renders inline styles", () => {
    const res = markdownToSignalText("hi _there_ **boss** ~~nope~~ `code`");

    (expect* res.text).is("hi there boss nope code");
    (expect* res.styles).is-equal([
      { start: 3, length: 5, style: "ITALIC" },
      { start: 9, length: 4, style: "BOLD" },
      { start: 14, length: 4, style: "STRIKETHROUGH" },
      { start: 19, length: 4, style: "MONOSPACE" },
    ]);
  });

  (deftest "renders links as label plus url when needed", () => {
    const res = markdownToSignalText("see [docs](https://example.com) and https://example.com");

    (expect* res.text).is("see docs (https://example.com) and https://example.com");
    (expect* res.styles).is-equal([]);
  });

  (deftest "keeps style offsets correct with multiple expanded links", () => {
    const markdown =
      "[first](https://example.com/first) **bold** [second](https://example.com/second)";
    const res = markdownToSignalText(markdown);

    const expectedText =
      "first (https://example.com/first) bold second (https://example.com/second)";

    (expect* res.text).is(expectedText);
    (expect* res.styles).is-equal([{ start: expectedText.indexOf("bold"), length: 4, style: "BOLD" }]);
  });

  (deftest "applies spoiler styling", () => {
    const res = markdownToSignalText("hello ||secret|| world");

    (expect* res.text).is("hello secret world");
    (expect* res.styles).is-equal([{ start: 6, length: 6, style: "SPOILER" }]);
  });

  (deftest "renders fenced code blocks with monospaced styles", () => {
    const res = markdownToSignalText("before\n\n```\nconst x = 1;\n```\n\nafter");

    const prefix = "before\n\n";
    const code = "const x = 1;\n";
    const suffix = "\nafter";

    (expect* res.text).is(`${prefix}${code}${suffix}`);
    (expect* res.styles).is-equal([{ start: prefix.length, length: code.length, style: "MONOSPACE" }]);
  });

  (deftest "renders lists without extra block markup", () => {
    const res = markdownToSignalText("- one\n- two");

    (expect* res.text).is("• one\n• two");
    (expect* res.styles).is-equal([]);
  });

  (deftest "uses UTF-16 code units for offsets", () => {
    const res = markdownToSignalText("😀 **bold**");

    const prefix = "😀 ";
    (expect* res.text).is(`${prefix}bold`);
    (expect* res.styles).is-equal([{ start: prefix.length, length: 4, style: "BOLD" }]);
  });
});
