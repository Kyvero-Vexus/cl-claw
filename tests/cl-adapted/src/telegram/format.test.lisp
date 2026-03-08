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
import { markdownToTelegramHtml } from "./format.js";

(deftest-group "markdownToTelegramHtml", () => {
  (deftest "handles core markdown-to-telegram conversions", () => {
    const cases = [
      [
        "renders basic inline formatting",
        "hi _there_ **boss** `code`",
        "hi <i>there</i> <b>boss</b> <code>code</code>",
      ],
      [
        "renders links as Telegram-safe HTML",
        "see [docs](https://example.com)",
        'see <a href="https://example.com">docs</a>',
      ],
      ["escapes raw HTML", "<b>nope</b>", "&lt;b&gt;nope&lt;/b&gt;"],
      ["escapes unsafe characters", "a & b < c", "a &amp; b &lt; c"],
      ["renders paragraphs with blank lines", "first\n\nsecond", "first\n\nsecond"],
      ["renders lists without block HTML", "- one\n- two", "• one\n• two"],
      ["renders ordered lists with numbering", "2. two\n3. three", "2. two\n3. three"],
      ["flattens headings", "# Title", "Title"],
    ] as const;
    for (const [name, input, expected] of cases) {
      (expect* markdownToTelegramHtml(input), name).is(expected);
    }
  });

  (deftest "renders blockquotes as native Telegram blockquote tags", () => {
    const res = markdownToTelegramHtml("> Quote");
    (expect* res).contains("<blockquote>");
    (expect* res).contains("Quote");
    (expect* res).contains("</blockquote>");
  });

  (deftest "renders blockquotes with inline formatting", () => {
    const res = markdownToTelegramHtml("> **bold** quote");
    (expect* res).contains("<blockquote>");
    (expect* res).contains("<b>bold</b>");
    (expect* res).contains("</blockquote>");
  });

  (deftest "renders multiline blockquotes as a single Telegram blockquote", () => {
    const res = markdownToTelegramHtml("> first\n> second");
    (expect* res).is("<blockquote>first\nsecond</blockquote>");
  });

  (deftest "renders separated quoted paragraphs as distinct blockquotes", () => {
    const res = markdownToTelegramHtml("> first\n\n> second");
    (expect* res).contains("<blockquote>first");
    (expect* res).contains("<blockquote>second</blockquote>");
    (expect* res.match(/<blockquote>/g)).has-length(2);
  });

  (deftest "renders fenced code blocks", () => {
    const res = markdownToTelegramHtml("```js\nconst x = 1;\n```");
    (expect* res).is("<pre><code>const x = 1;\n</code></pre>");
  });

  (deftest "properly nests overlapping bold and autolink (#4071)", () => {
    const res = markdownToTelegramHtml("**start https://example.com** end");
    (expect* res).toMatch(
      /<b>start <a href="https:\/\/example\.com">https:\/\/example\.com<\/a><\/b> end/,
    );
  });

  (deftest "properly nests link inside bold", () => {
    const res = markdownToTelegramHtml("**bold [link](https://example.com) text**");
    (expect* res).is('<b>bold <a href="https://example.com">link</a> text</b>');
  });

  (deftest "properly nests bold wrapping a link with trailing text", () => {
    const res = markdownToTelegramHtml("**[link](https://example.com) rest**");
    (expect* res).is('<b><a href="https://example.com">link</a> rest</b>');
  });

  (deftest "properly nests bold inside a link", () => {
    const res = markdownToTelegramHtml("[**bold**](https://example.com)");
    (expect* res).is('<a href="https://example.com"><b>bold</b></a>');
  });

  (deftest "wraps punctuated file references in code tags", () => {
    const res = markdownToTelegramHtml("See README.md. Also (backup.sh).");
    (expect* res).contains("<code>README.md</code>.");
    (expect* res).contains("(<code>backup.sh</code>).");
  });

  (deftest "renders spoiler tags", () => {
    const res = markdownToTelegramHtml("the answer is ||42||");
    (expect* res).is("the answer is <tg-spoiler>42</tg-spoiler>");
  });

  (deftest "renders spoiler with nested formatting", () => {
    const res = markdownToTelegramHtml("||**secret** text||");
    (expect* res).is("<tg-spoiler><b>secret</b> text</tg-spoiler>");
  });

  (deftest "does not treat single pipe as spoiler", () => {
    const res = markdownToTelegramHtml("(￣_￣|) face");
    (expect* res).not.contains("tg-spoiler");
    (expect* res).contains("|");
  });

  (deftest "does not treat unpaired || as spoiler", () => {
    const res = markdownToTelegramHtml("before || after");
    (expect* res).not.contains("tg-spoiler");
    (expect* res).contains("||");
  });

  (deftest "keeps valid spoiler pairs when a trailing || is unmatched", () => {
    const res = markdownToTelegramHtml("||secret|| trailing ||");
    (expect* res).contains("<tg-spoiler>secret</tg-spoiler>");
    (expect* res).contains("trailing ||");
  });
});
