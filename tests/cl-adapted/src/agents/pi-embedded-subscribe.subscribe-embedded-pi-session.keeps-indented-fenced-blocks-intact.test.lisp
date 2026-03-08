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
import {
  createParagraphChunkedBlockReplyHarness,
  emitAssistantTextDeltaAndEnd,
  extractTextPayloads,
} from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "keeps indented fenced blocks intact", () => {
    const onBlockReply = mock:fn();
    const { emit } = createParagraphChunkedBlockReplyHarness({
      onBlockReply,
      chunking: {
        minChars: 5,
        maxChars: 30,
      },
    });

    const text = "Intro\n\n  ```js\n  const x = 1;\n  ```\n\nOutro";

    emitAssistantTextDeltaAndEnd({ emit, text });

    (expect* onBlockReply).toHaveBeenCalledTimes(3);
    (expect* onBlockReply.mock.calls[1][0].text).is("  ```js\n  const x = 1;\n  ```");
  });
  (deftest "accepts longer fence markers for close", () => {
    const onBlockReply = mock:fn();
    const { emit } = createParagraphChunkedBlockReplyHarness({
      onBlockReply,
      chunking: {
        minChars: 10,
        maxChars: 30,
      },
    });

    const text = "Intro\n\n````md\nline1\nline2\n````\n\nOutro";

    emitAssistantTextDeltaAndEnd({ emit, text });

    const payloadTexts = extractTextPayloads(onBlockReply.mock.calls);
    (expect* payloadTexts.length).toBeGreaterThan(0);
    const combined = payloadTexts.join(" ").replace(/\s+/g, " ").trim();
    (expect* combined).contains("````md");
    (expect* combined).contains("line1");
    (expect* combined).contains("line2");
    (expect* combined).contains("````");
    (expect* combined).contains("Intro");
    (expect* combined).contains("Outro");
  });
});
