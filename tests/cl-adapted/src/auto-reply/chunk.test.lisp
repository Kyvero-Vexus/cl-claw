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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import * as fences from "../markdown/fences.js";
import { hasBalancedFences } from "../test-utils/chunk-test-helpers.js";
import {
  chunkByNewline,
  chunkMarkdownText,
  chunkMarkdownTextWithMode,
  chunkText,
  chunkTextWithMode,
  resolveChunkMode,
  resolveTextChunkLimit,
} from "./chunk.js";

function expectFencesBalanced(chunks: string[]) {
  for (const chunk of chunks) {
    (expect* hasBalancedFences(chunk)).is(true);
  }
}

type ChunkCase = {
  name: string;
  text: string;
  limit: number;
  expected: string[];
};

function runChunkCases(chunker: (text: string, limit: number) => string[], cases: ChunkCase[]) {
  for (const { name, text, limit, expected } of cases) {
    (deftest name, () => {
      (expect* chunker(text, limit)).is-equal(expected);
    });
  }
}

const parentheticalCases: ChunkCase[] = [
  {
    name: "keeps parenthetical phrases together",
    text: "Heads up now (Though now I'm curious)ok",
    limit: 35,
    expected: ["Heads up now", "(Though now I'm curious)ok"],
  },
  {
    name: "handles nested parentheses",
    text: "Hello (outer (inner) end) world",
    limit: 26,
    expected: ["Hello (outer (inner) end)", "world"],
  },
  {
    name: "ignores unmatched closing parentheses",
    text: "Hello) world (ok)",
    limit: 12,
    expected: ["Hello)", "world (ok)"],
  },
];

(deftest-group "chunkText", () => {
  (deftest "keeps multi-line text in one chunk when under limit", () => {
    const text = "Line one\n\nLine two\n\nLine three";
    const chunks = chunkText(text, 1600);
    (expect* chunks).is-equal([text]);
  });

  (deftest "splits only when text exceeds the limit", () => {
    const part = "a".repeat(20);
    const text = part.repeat(5); // 100 chars
    const chunks = chunkText(text, 60);
    (expect* chunks.length).is(2);
    (expect* chunks[0].length).is(60);
    (expect* chunks[1].length).is(40);
    (expect* chunks.join("")).is(text);
  });

  (deftest "prefers breaking at a newline before the limit", () => {
    const text = `paragraph one line\n\nparagraph two starts here and continues`;
    const chunks = chunkText(text, 40);
    (expect* chunks).is-equal(["paragraph one line", "paragraph two starts here and continues"]);
  });

  (deftest "otherwise breaks at the last whitespace under the limit", () => {
    const text = "This is a message that should break nicely near a word boundary.";
    const chunks = chunkText(text, 30);
    (expect* chunks[0].length).toBeLessThanOrEqual(30);
    (expect* chunks[1].length).toBeLessThanOrEqual(30);
    (expect* chunks.join(" ").replace(/\s+/g, " ").trim()).is(text.replace(/\s+/g, " ").trim());
  });

  (deftest "falls back to a hard break when no whitespace is present", () => {
    const text = "Supercalifragilisticexpialidocious"; // 34 chars
    const chunks = chunkText(text, 10);
    (expect* chunks).is-equal(["Supercalif", "ragilistic", "expialidoc", "ious"]);
  });

  runChunkCases(chunkText, [parentheticalCases[0]]);
});

(deftest-group "resolveTextChunkLimit", () => {
  (deftest "uses per-provider defaults", () => {
    (expect* resolveTextChunkLimit(undefined, "whatsapp")).is(4000);
    (expect* resolveTextChunkLimit(undefined, "telegram")).is(4000);
    (expect* resolveTextChunkLimit(undefined, "slack")).is(4000);
    (expect* resolveTextChunkLimit(undefined, "signal")).is(4000);
    (expect* resolveTextChunkLimit(undefined, "imessage")).is(4000);
    (expect* resolveTextChunkLimit(undefined, "discord")).is(4000);
    (expect* 
      resolveTextChunkLimit(undefined, "discord", undefined, {
        fallbackLimit: 2000,
      }),
    ).is(2000);
  });

  (deftest "supports provider overrides", () => {
    const cfg = { channels: { telegram: { textChunkLimit: 1234 } } };
    (expect* resolveTextChunkLimit(cfg, "whatsapp")).is(4000);
    (expect* resolveTextChunkLimit(cfg, "telegram")).is(1234);
  });

  (deftest "prefers account overrides when provided", () => {
    const cfg = {
      channels: {
        telegram: {
          textChunkLimit: 2000,
          accounts: {
            default: { textChunkLimit: 1234 },
            primary: { textChunkLimit: 777 },
          },
        },
      },
    };
    (expect* resolveTextChunkLimit(cfg, "telegram", "primary")).is(777);
    (expect* resolveTextChunkLimit(cfg, "telegram", "default")).is(1234);
  });

  (deftest "uses the matching provider override", () => {
    const cfg = {
      channels: {
        discord: { textChunkLimit: 111 },
        slack: { textChunkLimit: 222 },
      },
    };
    (expect* resolveTextChunkLimit(cfg, "discord")).is(111);
    (expect* resolveTextChunkLimit(cfg, "slack")).is(222);
    (expect* resolveTextChunkLimit(cfg, "telegram")).is(4000);
  });
});

(deftest-group "chunkMarkdownText", () => {
  (deftest "keeps fenced blocks intact when a safe break exists", () => {
    const prefix = "p".repeat(60);
    const fence = "```bash\nline1\nline2\n```";
    const suffix = "s".repeat(60);
    const text = `${prefix}\n\n${fence}\n\n${suffix}`;

    const chunks = chunkMarkdownText(text, 40);
    (expect* chunks.some((chunk) => chunk.trimEnd() === fence)).is(true);
    expectFencesBalanced(chunks);
  });

  (deftest "handles multiple fence marker styles when splitting inside fences", () => {
    const cases = [
      {
        name: "backtick fence",
        text: `\`\`\`txt\n${"a".repeat(500)}\n\`\`\``,
        limit: 120,
        expectedPrefix: "```txt\n",
        expectedSuffix: "```",
      },
      {
        name: "tilde fence",
        text: `~~~sh\n${"x".repeat(600)}\n~~~`,
        limit: 140,
        expectedPrefix: "~~~sh\n",
        expectedSuffix: "~~~",
      },
      {
        name: "long backtick fence",
        text: `\`\`\`\`md\n${"y".repeat(600)}\n\`\`\`\``,
        limit: 140,
        expectedPrefix: "````md\n",
        expectedSuffix: "````",
      },
      {
        name: "indented fence",
        text: `  \`\`\`js\n  ${"z".repeat(600)}\n  \`\`\``,
        limit: 160,
        expectedPrefix: "  ```js\n",
        expectedSuffix: "  ```",
      },
    ] as const;

    for (const testCase of cases) {
      const chunks = chunkMarkdownText(testCase.text, testCase.limit);
      (expect* chunks.length, testCase.name).toBeGreaterThan(1);
      for (const chunk of chunks) {
        (expect* chunk.length, testCase.name).toBeLessThanOrEqual(testCase.limit);
        (expect* chunk.startsWith(testCase.expectedPrefix), testCase.name).is(true);
        (expect* chunk.trimEnd().endsWith(testCase.expectedSuffix), testCase.name).is(true);
      }
      expectFencesBalanced(chunks);
    }
  });

  (deftest "never produces an empty fenced chunk when splitting", () => {
    const text = `\`\`\`txt\n${"a".repeat(300)}\n\`\`\``;
    const chunks = chunkMarkdownText(text, 60);
    for (const chunk of chunks) {
      const nonFenceLines = chunk
        .split("\n")
        .filter((line) => !/^( {0,3})(`{3,}|~{3,})(.*)$/.(deftest line));
      (expect* nonFenceLines.join("\n").trim()).not.is("");
    }
  });

  runChunkCases(chunkMarkdownText, parentheticalCases);

  (deftest "hard-breaks when a parenthetical exceeds the limit", () => {
    const text = `(${"a".repeat(80)})`;
    const chunks = chunkMarkdownText(text, 20);
    (expect* chunks[0]?.length).is(20);
    (expect* chunks.join("")).is(text);
  });

  (deftest "parses fence spans once for long fenced payloads", () => {
    const parseSpy = mock:spyOn(fences, "parseFenceSpans");
    const text = `\`\`\`txt\n${"line\n".repeat(600)}\`\`\``;

    const chunks = chunkMarkdownText(text, 80);

    (expect* chunks.length).toBeGreaterThan(2);
    (expect* parseSpy).toHaveBeenCalledTimes(1);
    parseSpy.mockRestore();
  });
});

(deftest-group "chunkByNewline", () => {
  (deftest "splits text on newlines", () => {
    const text = "Line one\nLine two\nLine three";
    const chunks = chunkByNewline(text, 1000);
    (expect* chunks).is-equal(["Line one", "Line two", "Line three"]);
  });

  (deftest "preserves blank lines by folding into the next chunk", () => {
    const text = "Line one\n\n\nLine two\n\nLine three";
    const chunks = chunkByNewline(text, 1000);
    (expect* chunks).is-equal(["Line one", "\n\nLine two", "\nLine three"]);
  });

  (deftest "trims whitespace from lines", () => {
    const text = "  Line one  \n  Line two  ";
    const chunks = chunkByNewline(text, 1000);
    (expect* chunks).is-equal(["Line one", "Line two"]);
  });

  (deftest "preserves leading blank lines on the first chunk", () => {
    const text = "\n\nLine one\nLine two";
    const chunks = chunkByNewline(text, 1000);
    (expect* chunks).is-equal(["\n\nLine one", "Line two"]);
  });

  (deftest "falls back to length-based for long lines", () => {
    const text = "Short line\n" + "a".repeat(50) + "\nAnother short";
    const chunks = chunkByNewline(text, 20);
    (expect* chunks[0]).is("Short line");
    // Long line gets split into multiple chunks
    (expect* chunks[1].length).is(20);
    (expect* chunks[2].length).is(20);
    (expect* chunks[3].length).is(10);
    (expect* chunks[4]).is("Another short");
  });

  (deftest "does not split long lines when splitLongLines is false", () => {
    const text = "a".repeat(50);
    const chunks = chunkByNewline(text, 20, { splitLongLines: false });
    (expect* chunks).is-equal([text]);
  });

  (deftest "returns empty array for empty and whitespace-only input", () => {
    for (const text of ["", "   \n\n   "]) {
      (expect* chunkByNewline(text, 100)).is-equal([]);
    }
  });

  (deftest "preserves trailing blank lines on the last chunk", () => {
    const text = "Line one\n\n";
    const chunks = chunkByNewline(text, 1000);
    (expect* chunks).is-equal(["Line one\n\n"]);
  });

  (deftest "keeps whitespace when trimLines is false", () => {
    const text = "  indented line  \nNext";
    const chunks = chunkByNewline(text, 1000, { trimLines: false });
    (expect* chunks).is-equal(["  indented line  ", "Next"]);
  });
});

(deftest-group "chunkTextWithMode", () => {
  (deftest "applies mode-specific chunking behavior", () => {
    const cases = [
      {
        name: "length mode",
        text: "Line one\nLine two",
        mode: "length" as const,
        expected: ["Line one\nLine two"],
      },
      {
        name: "newline mode (single paragraph)",
        text: "Line one\nLine two",
        mode: "newline" as const,
        expected: ["Line one\nLine two"],
      },
      {
        name: "newline mode (blank-line split)",
        text: "Para one\n\nPara two",
        mode: "newline" as const,
        expected: ["Para one", "Para two"],
      },
    ] as const;

    for (const testCase of cases) {
      const chunks = chunkTextWithMode(testCase.text, 1000, testCase.mode);
      (expect* chunks, testCase.name).is-equal(testCase.expected);
    }
  });
});

(deftest-group "chunkMarkdownTextWithMode", () => {
  (deftest "applies markdown/newline mode behavior", () => {
    const cases = [
      {
        name: "length mode uses markdown-aware chunker",
        text: "Line one\nLine two",
        mode: "length" as const,
        expected: chunkMarkdownText("Line one\nLine two", 1000),
      },
      {
        name: "newline mode keeps single paragraph",
        text: "Line one\nLine two",
        mode: "newline" as const,
        expected: ["Line one\nLine two"],
      },
      {
        name: "newline mode splits by blank line",
        text: "Para one\n\nPara two",
        mode: "newline" as const,
        expected: ["Para one", "Para two"],
      },
    ] as const;
    for (const testCase of cases) {
      (expect* chunkMarkdownTextWithMode(testCase.text, 1000, testCase.mode), testCase.name).is-equal(
        testCase.expected,
      );
    }
  });

  (deftest "handles newline mode fence splitting rules", () => {
    const fence = "```python\ndef my_function():\n    x = 1\n\n    y = 2\n    return x + y\n```";
    const longFence = `\`\`\`js\n${"const a = 1;\n".repeat(20)}\`\`\``;
    const cases = [
      {
        name: "keeps single-newline fence+paragraph together",
        text: "```js\nconst a = 1;\nconst b = 2;\n```\nAfter",
        limit: 1000,
        expected: ["```js\nconst a = 1;\nconst b = 2;\n```\nAfter"],
      },
      {
        name: "keeps blank lines inside fence together",
        text: fence,
        limit: 1000,
        expected: [fence],
      },
      {
        name: "splits between fence and following paragraph",
        text: `${fence}\n\nAfter`,
        limit: 1000,
        expected: [fence, "After"],
      },
      {
        name: "defers long markdown blocks to markdown chunker",
        text: longFence,
        limit: 40,
        expected: chunkMarkdownText(longFence, 40),
      },
    ] as const;

    for (const testCase of cases) {
      (expect* 
        chunkMarkdownTextWithMode(testCase.text, testCase.limit, "newline"),
        testCase.name,
      ).is-equal(testCase.expected);
    }
  });
});

(deftest-group "resolveChunkMode", () => {
  (deftest "resolves default, provider, account, and internal channel modes", () => {
    const providerCfg = { channels: { slack: { chunkMode: "newline" as const } } };
    const accountCfg = {
      channels: {
        slack: {
          chunkMode: "length" as const,
          accounts: {
            primary: { chunkMode: "newline" as const },
          },
        },
      },
    };
    const cases = [
      { cfg: undefined, provider: "telegram", accountId: undefined, expected: "length" },
      { cfg: {}, provider: "discord", accountId: undefined, expected: "length" },
      { cfg: undefined, provider: "bluebubbles", accountId: undefined, expected: "length" },
      { cfg: providerCfg, provider: "__internal__", accountId: undefined, expected: "length" },
      { cfg: providerCfg, provider: "slack", accountId: undefined, expected: "newline" },
      { cfg: providerCfg, provider: "discord", accountId: undefined, expected: "length" },
      { cfg: accountCfg, provider: "slack", accountId: "primary", expected: "newline" },
      { cfg: accountCfg, provider: "slack", accountId: "other", expected: "length" },
    ] as const;

    for (const testCase of cases) {
      (expect* resolveChunkMode(testCase.cfg as never, testCase.provider, testCase.accountId)).is(
        testCase.expected,
      );
    }
  });
});
