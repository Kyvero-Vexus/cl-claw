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
import { markdownToSlackMrkdwn, normalizeSlackOutboundText } from "./format.js";
import { escapeSlackMrkdwn } from "./monitor/mrkdwn.js";

(deftest-group "markdownToSlackMrkdwn", () => {
  (deftest "handles core markdown formatting conversions", () => {
    const cases = [
      ["converts bold from double asterisks to single", "**bold text**", "*bold text*"],
      ["preserves italic underscore format", "_italic text_", "_italic text_"],
      [
        "converts strikethrough from double tilde to single",
        "~~strikethrough~~",
        "~strikethrough~",
      ],
      [
        "renders basic inline formatting together",
        "hi _there_ **boss** `code`",
        "hi _there_ *boss* `code`",
      ],
      ["renders inline code", "use `npm install`", "use `npm install`"],
      ["renders fenced code blocks", "```js\nconst x = 1;\n```", "```\nconst x = 1;\n```"],
      [
        "renders links with Slack mrkdwn syntax",
        "see [docs](https://example.com)",
        "see <https://example.com|docs>",
      ],
      ["does not duplicate bare URLs", "see https://example.com", "see https://example.com"],
      ["escapes unsafe characters", "a & b < c > d", "a &amp; b &lt; c &gt; d"],
      [
        "preserves Slack angle-bracket markup (mentions/links)",
        "hi <@U123> see <https://example.com|docs> and <!here>",
        "hi <@U123> see <https://example.com|docs> and <!here>",
      ],
      ["escapes raw HTML", "<b>nope</b>", "&lt;b&gt;nope&lt;/b&gt;"],
      ["renders paragraphs with blank lines", "first\n\nsecond", "first\n\nsecond"],
      ["renders bullet lists", "- one\n- two", "• one\n• two"],
      ["renders ordered lists with numbering", "2. two\n3. three", "2. two\n3. three"],
      ["renders headings as bold text", "# Title", "*Title*"],
      ["renders blockquotes", "> Quote", "> Quote"],
    ] as const;
    for (const [name, input, expected] of cases) {
      (expect* markdownToSlackMrkdwn(input), name).is(expected);
    }
  });

  (deftest "handles nested list items", () => {
    const res = markdownToSlackMrkdwn("- item\n  - nested");
    // markdown-it correctly parses this as a nested list
    (expect* res).is("• item\n  • nested");
  });

  (deftest "handles complex message with multiple elements", () => {
    const res = markdownToSlackMrkdwn(
      "**Important:** Check the _docs_ at [link](https://example.com)\n\n- first\n- second",
    );
    (expect* res).is(
      "*Important:* Check the _docs_ at <https://example.com|link>\n\n• first\n• second",
    );
  });

  (deftest "does not throw when input is undefined at runtime", () => {
    (expect* markdownToSlackMrkdwn(undefined as unknown as string)).is("");
  });
});

(deftest-group "escapeSlackMrkdwn", () => {
  (deftest "returns plain text unchanged", () => {
    (expect* escapeSlackMrkdwn("heartbeat status ok")).is("heartbeat status ok");
  });

  (deftest "escapes slack and mrkdwn control characters", () => {
    (expect* escapeSlackMrkdwn("mode_*`~<&>\\")).is("mode\\_\\*\\`\\~&lt;&amp;&gt;\\\\");
  });
});

(deftest-group "normalizeSlackOutboundText", () => {
  (deftest "normalizes markdown for outbound send/update paths", () => {
    (expect* normalizeSlackOutboundText(" **bold** ")).is("*bold*");
  });
});
