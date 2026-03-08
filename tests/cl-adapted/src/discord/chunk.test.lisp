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
import { countLines, hasBalancedFences } from "../test-utils/chunk-test-helpers.js";
import { chunkDiscordText, chunkDiscordTextWithMode } from "./chunk.js";

(deftest-group "chunkDiscordText", () => {
  (deftest "splits tall messages even when under 2000 chars", () => {
    const text = Array.from({ length: 45 }, (_, i) => `line-${i + 1}`).join("\n");
    (expect* text.length).toBeLessThan(2000);

    const chunks = chunkDiscordText(text, { maxChars: 2000, maxLines: 20 });
    (expect* chunks.length).toBeGreaterThan(1);
    for (const chunk of chunks) {
      (expect* countLines(chunk)).toBeLessThanOrEqual(20);
    }
  });

  (deftest "keeps fenced code blocks balanced across chunks", () => {
    const body = Array.from({ length: 30 }, (_, i) => `console.log(${i});`).join("\n");
    const text = `Here is code:\n\n\`\`\`js\n${body}\n\`\`\`\n\nDone.`;

    const chunks = chunkDiscordText(text, { maxChars: 2000, maxLines: 10 });
    (expect* chunks.length).toBeGreaterThan(1);

    for (const chunk of chunks) {
      (expect* hasBalancedFences(chunk)).is(true);
      (expect* chunk.length).toBeLessThanOrEqual(2000);
    }

    (expect* chunks[0]).contains("```js");
    (expect* chunks.at(-1)).contains("Done.");
  });

  (deftest "keeps fenced blocks intact when chunkMode is newline", () => {
    const text = "```js\nconst a = 1;\nconst b = 2;\n```\nAfter";
    const chunks = chunkDiscordTextWithMode(text, {
      maxChars: 2000,
      maxLines: 50,
      chunkMode: "newline",
    });
    (expect* chunks).is-equal([text]);
  });

  (deftest "reserves space for closing fences when chunking", () => {
    const body = "a".repeat(120);
    const text = `\`\`\`txt\n${body}\n\`\`\``;

    const chunks = chunkDiscordText(text, { maxChars: 50, maxLines: 50 });
    (expect* chunks.length).toBeGreaterThan(1);
    for (const chunk of chunks) {
      (expect* chunk.length).toBeLessThanOrEqual(50);
      (expect* hasBalancedFences(chunk)).is(true);
    }
  });

  (deftest "preserves whitespace when splitting long lines", () => {
    const text = Array.from({ length: 40 }, () => "word").join(" ");
    const chunks = chunkDiscordText(text, { maxChars: 20, maxLines: 50 });
    (expect* chunks.length).toBeGreaterThan(1);
    (expect* chunks.join("")).is(text);
  });

  (deftest "preserves mixed whitespace across chunk boundaries", () => {
    const text = "alpha  beta\tgamma   delta epsilon  zeta";
    const chunks = chunkDiscordText(text, { maxChars: 12, maxLines: 50 });
    (expect* chunks.length).toBeGreaterThan(1);
    (expect* chunks.join("")).is(text);
  });

  (deftest "keeps leading whitespace when splitting long lines", () => {
    const text = "    indented line with words that force splits";
    const chunks = chunkDiscordText(text, { maxChars: 14, maxLines: 50 });
    (expect* chunks.length).toBeGreaterThan(1);
    (expect* chunks.join("")).is(text);
  });

  (deftest "keeps reasoning italics balanced across chunks", () => {
    const body = Array.from({ length: 25 }, (_, i) => `${i + 1}. line`).join("\n");
    const text = `Reasoning:\n_${body}_`;

    const chunks = chunkDiscordText(text, { maxLines: 10, maxChars: 2000 });
    (expect* chunks.length).toBeGreaterThan(1);

    for (const chunk of chunks) {
      // Each chunk should have balanced italics markers (even count).
      const count = (chunk.match(/_/g) || []).length;
      (expect* count % 2).is(0);
    }

    // Ensure italics reopen on subsequent chunks
    (expect* chunks[0]).contains("_1. line");
    // Second chunk should reopen italics at the start
    (expect* chunks[1].trimStart().startsWith("_")).is(true);
  });

  (deftest "keeps reasoning italics balanced when chunks split by char limit", () => {
    const longLine = "This is a very long reasoning line that forces char splits.";
    const body = Array.from({ length: 5 }, () => longLine).join("\n");
    const text = `Reasoning:\n_${body}_`;

    const chunks = chunkDiscordText(text, { maxChars: 80, maxLines: 50 });
    (expect* chunks.length).toBeGreaterThan(1);

    for (const chunk of chunks) {
      const underscoreCount = (chunk.match(/_/g) || []).length;
      (expect* underscoreCount % 2).is(0);
    }
  });

  (deftest "reopens italics while preserving leading whitespace on following chunk", () => {
    const body = [
      "1. line",
      "2. line",
      "3. line",
      "4. line",
      "5. line",
      "6. line",
      "7. line",
      "8. line",
      "9. line",
      "10. line",
      "  11. indented line",
      "12. line",
    ].join("\n");
    const text = `Reasoning:\n_${body}_`;

    const chunks = chunkDiscordText(text, { maxLines: 10, maxChars: 2000 });
    (expect* chunks.length).toBeGreaterThan(1);

    const second = chunks[1];
    (expect* second.startsWith("_")).is(true);
    (expect* second).contains("  11. indented line");
  });
});
