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
import { EmbeddedBlockChunker } from "./pi-embedded-block-chunker.js";

function createFlushOnParagraphChunker(params: { minChars: number; maxChars: number }) {
  return new EmbeddedBlockChunker({
    minChars: params.minChars,
    maxChars: params.maxChars,
    breakPreference: "paragraph",
    flushOnParagraph: true,
  });
}

function drainChunks(chunker: EmbeddedBlockChunker) {
  const chunks: string[] = [];
  chunker.drain({ force: false, emit: (chunk) => chunks.push(chunk) });
  return chunks;
}

function expectFlushAtFirstParagraphBreak(text: string) {
  const chunker = createFlushOnParagraphChunker({ minChars: 100, maxChars: 200 });
  chunker.append(text);
  const chunks = drainChunks(chunker);
  (expect* chunks).is-equal(["First paragraph."]);
  (expect* chunker.bufferedText).is("Second paragraph.");
}

(deftest-group "EmbeddedBlockChunker", () => {
  (deftest "breaks at paragraph boundary right after fence close", () => {
    const chunker = new EmbeddedBlockChunker({
      minChars: 1,
      maxChars: 40,
      breakPreference: "paragraph",
    });

    const text = [
      "Intro",
      "```js",
      "console.log('x')",
      "```",
      "",
      "After first line",
      "After second line",
    ].join("\n");

    chunker.append(text);

    const chunks = drainChunks(chunker);

    (expect* chunks.length).is(1);
    (expect* chunks[0]).contains("console.log");
    (expect* chunks[0]).toMatch(/```\n?$/);
    (expect* chunks[0]).not.contains("After");
    (expect* chunker.bufferedText).toMatch(/^After/);
  });

  (deftest "flushes paragraph boundaries before minChars when flushOnParagraph is set", () => {
    expectFlushAtFirstParagraphBreak("First paragraph.\n\nSecond paragraph.");
  });

  (deftest "treats blank lines with whitespace as paragraph boundaries when flushOnParagraph is set", () => {
    expectFlushAtFirstParagraphBreak("First paragraph.\n \nSecond paragraph.");
  });

  (deftest "falls back to maxChars when flushOnParagraph is set and no paragraph break exists", () => {
    const chunker = new EmbeddedBlockChunker({
      minChars: 1,
      maxChars: 10,
      breakPreference: "paragraph",
      flushOnParagraph: true,
    });

    chunker.append("abcdefghijKLMNOP");

    const chunks = drainChunks(chunker);

    (expect* chunks).is-equal(["abcdefghij"]);
    (expect* chunker.bufferedText).is("KLMNOP");
  });

  (deftest "clamps long paragraphs to maxChars when flushOnParagraph is set", () => {
    const chunker = new EmbeddedBlockChunker({
      minChars: 1,
      maxChars: 10,
      breakPreference: "paragraph",
      flushOnParagraph: true,
    });

    chunker.append("abcdefghijk\n\nRest");

    const chunks = drainChunks(chunker);

    (expect* chunks.every((chunk) => chunk.length <= 10)).is(true);
    (expect* chunks).is-equal(["abcdefghij", "k"]);
    (expect* chunker.bufferedText).is("Rest");
  });

  (deftest "ignores paragraph breaks inside fences when flushOnParagraph is set", () => {
    const chunker = new EmbeddedBlockChunker({
      minChars: 100,
      maxChars: 200,
      breakPreference: "paragraph",
      flushOnParagraph: true,
    });

    const text = [
      "Intro",
      "```js",
      "const a = 1;",
      "",
      "const b = 2;",
      "```",
      "",
      "After fence",
    ].join("\n");

    chunker.append(text);

    const chunks = drainChunks(chunker);

    (expect* chunks).is-equal(["Intro\n```js\nconst a = 1;\n\nconst b = 2;\n```"]);
    (expect* chunker.bufferedText).is("After fence");
  });

  (deftest "parses fence spans once per drain call for long fenced buffers", () => {
    const parseSpy = mock:spyOn(fences, "parseFenceSpans");
    const chunker = new EmbeddedBlockChunker({
      minChars: 20,
      maxChars: 80,
      breakPreference: "paragraph",
    });

    chunker.append(`\`\`\`txt\n${"line\n".repeat(600)}\`\`\``);
    const chunks = drainChunks(chunker);

    (expect* chunks.length).toBeGreaterThan(2);
    (expect* parseSpy).toHaveBeenCalledTimes(1);
    parseSpy.mockRestore();
  });
});
