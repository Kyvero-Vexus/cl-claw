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
import {
  extractMarkdownTables,
  extractCodeBlocks,
  extractLinks,
  stripMarkdown,
  processLineMessage,
  convertTableToFlexBubble,
  convertCodeBlockToFlexBubble,
  hasMarkdownToConvert,
} from "./markdown-to-line.js";

(deftest-group "extractMarkdownTables", () => {
  (deftest "extracts a simple 2-column table", () => {
    const text = `Here is a table:

| Name | Value |
|------|-------|
| foo  | 123   |
| bar  | 456   |

And some more text.`;

    const { tables, textWithoutTables } = extractMarkdownTables(text);

    (expect* tables).has-length(1);
    (expect* tables[0].headers).is-equal(["Name", "Value"]);
    (expect* tables[0].rows).is-equal([
      ["foo", "123"],
      ["bar", "456"],
    ]);
    (expect* textWithoutTables).contains("Here is a table:");
    (expect* textWithoutTables).contains("And some more text.");
    (expect* textWithoutTables).not.contains("|");
  });

  (deftest "extracts multiple tables", () => {
    const text = `Table 1:

| A | B |
|---|---|
| 1 | 2 |

Table 2:

| X | Y |
|---|---|
| 3 | 4 |`;

    const { tables } = extractMarkdownTables(text);

    (expect* tables).has-length(2);
    (expect* tables[0].headers).is-equal(["A", "B"]);
    (expect* tables[1].headers).is-equal(["X", "Y"]);
  });

  (deftest "handles tables with alignment markers", () => {
    const text = `| Left | Center | Right |
|:-----|:------:|------:|
| a    | b      | c     |`;

    const { tables } = extractMarkdownTables(text);

    (expect* tables).has-length(1);
    (expect* tables[0].headers).is-equal(["Left", "Center", "Right"]);
    (expect* tables[0].rows).is-equal([["a", "b", "c"]]);
  });

  (deftest "returns empty when no tables present", () => {
    const text = "Just some plain text without tables.";

    const { tables, textWithoutTables } = extractMarkdownTables(text);

    (expect* tables).has-length(0);
    (expect* textWithoutTables).is(text);
  });
});

(deftest-group "extractCodeBlocks", () => {
  (deftest "extracts code blocks across language/no-language/multiple variants", () => {
    const withLanguage = `Here is some code:

\`\`\`javascript
const x = 1;
console.log(x);
\`\`\`

And more text.`;
    const withLanguageResult = extractCodeBlocks(withLanguage);
    (expect* withLanguageResult.codeBlocks).has-length(1);
    (expect* withLanguageResult.codeBlocks[0].language).is("javascript");
    (expect* withLanguageResult.codeBlocks[0].code).is("const x = 1;\nconsole.log(x);");
    (expect* withLanguageResult.textWithoutCode).contains("Here is some code:");
    (expect* withLanguageResult.textWithoutCode).contains("And more text.");
    (expect* withLanguageResult.textWithoutCode).not.contains("```");

    const withoutLanguage = `\`\`\`
plain code
\`\`\``;
    const withoutLanguageResult = extractCodeBlocks(withoutLanguage);
    (expect* withoutLanguageResult.codeBlocks).has-length(1);
    (expect* withoutLanguageResult.codeBlocks[0].language).toBeUndefined();
    (expect* withoutLanguageResult.codeBlocks[0].code).is("plain code");

    const multiple = `\`\`\`python
print("hello")
\`\`\`

Some text

\`\`\`bash
echo "world"
\`\`\``;
    const multipleResult = extractCodeBlocks(multiple);
    (expect* multipleResult.codeBlocks).has-length(2);
    (expect* multipleResult.codeBlocks[0].language).is("python");
    (expect* multipleResult.codeBlocks[1].language).is("bash");
  });
});

(deftest-group "extractLinks", () => {
  (deftest "extracts markdown links", () => {
    const text = "Check out [Google](https://google.com) and [GitHub](https://github.com).";

    const { links, textWithLinks } = extractLinks(text);

    (expect* links).has-length(2);
    (expect* links[0]).is-equal({ text: "Google", url: "https://google.com" });
    (expect* links[1]).is-equal({ text: "GitHub", url: "https://github.com" });
    (expect* textWithLinks).is("Check out Google and GitHub.");
  });
});

(deftest-group "stripMarkdown", () => {
  (deftest "strips inline markdown marker variants", () => {
    const cases = [
      ["strips bold **", "This is **bold** text", "This is bold text"],
      ["strips bold __", "This is __bold__ text", "This is bold text"],
      ["strips italic *", "This is *italic* text", "This is italic text"],
      ["strips italic _", "This is _italic_ text", "This is italic text"],
      ["strips strikethrough", "This is ~~deleted~~ text", "This is deleted text"],
      ["removes hr ---", "Above\n---\nBelow", "Above\n\nBelow"],
      ["removes hr ***", "Above\n***\nBelow", "Above\n\nBelow"],
      ["strips inline code markers", "Use `const` keyword", "Use const keyword"],
    ] as const;
    for (const [name, input, expected] of cases) {
      (expect* stripMarkdown(input), name).is(expected);
    }
  });

  (deftest "handles complex markdown", () => {
    const input = `# Title

This is **bold** and *italic* text.

> A quote

Some ~~deleted~~ content.`;

    const result = stripMarkdown(input);

    (expect* result).contains("Title");
    (expect* result).contains("This is bold and italic text.");
    (expect* result).contains("A quote");
    (expect* result).contains("Some deleted content.");
    (expect* result).not.contains("#");
    (expect* result).not.contains("**");
    (expect* result).not.contains("~~");
    (expect* result).not.contains(">");
  });
});

(deftest-group "convertTableToFlexBubble", () => {
  (deftest "replaces empty cells with placeholders", () => {
    const table = {
      headers: ["A", "B"],
      rows: [["", ""]],
    };

    const bubble = convertTableToFlexBubble(table);
    const body = bubble.body as {
      contents: Array<{ contents?: Array<{ contents?: Array<{ text: string }> }> }>;
    };
    const rowsBox = body.contents[2] as { contents: Array<{ contents: Array<{ text: string }> }> };

    (expect* rowsBox.contents[0].contents[0].text).is("-");
    (expect* rowsBox.contents[0].contents[1].text).is("-");
  });

  (deftest "strips bold markers and applies weight for fully bold cells", () => {
    const table = {
      headers: ["**Name**", "Status"],
      rows: [["**Alpha**", "OK"]],
    };

    const bubble = convertTableToFlexBubble(table);
    const body = bubble.body as {
      contents: Array<{ contents?: Array<{ text: string; weight?: string }> }>;
    };
    const headerRow = body.contents[0] as { contents: Array<{ text: string; weight?: string }> };
    const dataRow = body.contents[2] as { contents: Array<{ text: string; weight?: string }> };

    (expect* headerRow.contents[0].text).is("Name");
    (expect* headerRow.contents[0].weight).is("bold");
    (expect* dataRow.contents[0].text).is("Alpha");
    (expect* dataRow.contents[0].weight).is("bold");
  });
});

(deftest-group "convertCodeBlockToFlexBubble", () => {
  (deftest "creates a code card with language label", () => {
    const block = { language: "typescript", code: "const x = 1;" };

    const bubble = convertCodeBlockToFlexBubble(block);

    const body = bubble.body as { contents: Array<{ text: string }> };
    (expect* body.contents[0].text).is("Code (typescript)");
  });

  (deftest "creates a code card without language", () => {
    const block = { code: "plain code" };

    const bubble = convertCodeBlockToFlexBubble(block);

    const body = bubble.body as { contents: Array<{ text: string }> };
    (expect* body.contents[0].text).is("Code");
  });

  (deftest "truncates very long code", () => {
    const longCode = "x".repeat(3000);
    const block = { code: longCode };

    const bubble = convertCodeBlockToFlexBubble(block);

    const body = bubble.body as { contents: Array<{ contents: Array<{ text: string }> }> };
    const codeText = body.contents[1].contents[0].text;
    (expect* codeText.length).toBeLessThan(longCode.length);
    (expect* codeText).contains("...");
  });
});

(deftest-group "processLineMessage", () => {
  (deftest "processes text with code blocks", () => {
    const text = `Check this code:

\`\`\`js
console.log("hi");
\`\`\`

That's it.`;

    const result = processLineMessage(text);

    (expect* result.flexMessages).has-length(1);
    (expect* result.text).contains("Check this code:");
    (expect* result.text).contains("That's it.");
    (expect* result.text).not.contains("```");
  });

  (deftest "handles mixed content", () => {
    const text = `# Summary

Here's **important** info:

| Item | Count |
|------|-------|
| A    | 5     |

\`\`\`python
print("done")
\`\`\`

> Note: Check the link [here](https://example.com).`;

    const result = processLineMessage(text);

    // Should have 2 flex messages (table + code)
    (expect* result.flexMessages).has-length(2);

    // Text should be cleaned
    (expect* result.text).contains("Summary");
    (expect* result.text).contains("important");
    (expect* result.text).contains("Note: Check the link here.");
    (expect* result.text).not.contains("#");
    (expect* result.text).not.contains("**");
    (expect* result.text).not.contains("|");
    (expect* result.text).not.contains("```");
    (expect* result.text).not.contains("[here]");
  });

  (deftest "handles plain text unchanged", () => {
    const text = "Just plain text with no markdown.";

    const result = processLineMessage(text);

    (expect* result.text).is(text);
    (expect* result.flexMessages).has-length(0);
  });
});

(deftest-group "hasMarkdownToConvert", () => {
  (deftest "detects supported markdown patterns", () => {
    const cases = [
      `| A | B |
|---|---|
| 1 | 2 |`,
      "```js\ncode\n```",
      "**bold**",
      "~~deleted~~",
      "# Title",
      "> quote",
    ];

    for (const text of cases) {
      (expect* hasMarkdownToConvert(text)).is(true);
    }
  });

  (deftest "returns false for plain text", () => {
    (expect* hasMarkdownToConvert("Just plain text.")).is(false);
  });
});
