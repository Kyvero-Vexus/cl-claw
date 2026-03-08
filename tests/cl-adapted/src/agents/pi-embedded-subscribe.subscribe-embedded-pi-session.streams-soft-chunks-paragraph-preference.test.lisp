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
} from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "streams soft chunks with paragraph preference", () => {
    const onBlockReply = mock:fn();
    const { emit, subscription } = createParagraphChunkedBlockReplyHarness({
      onBlockReply,
      chunking: {
        minChars: 5,
        maxChars: 25,
      },
    });

    const text = "First block line\n\nSecond block line";

    emitAssistantTextDeltaAndEnd({ emit, text });

    (expect* onBlockReply).toHaveBeenCalledTimes(2);
    (expect* onBlockReply.mock.calls[0][0].text).is("First block line");
    (expect* onBlockReply.mock.calls[1][0].text).is("Second block line");
    (expect* subscription.assistantTexts).is-equal(["First block line", "Second block line"]);
  });
  (deftest "avoids splitting inside fenced code blocks", () => {
    const onBlockReply = mock:fn();
    const { emit } = createParagraphChunkedBlockReplyHarness({
      onBlockReply,
      chunking: {
        minChars: 5,
        maxChars: 25,
      },
    });

    const text = "Intro\n\n```bash\nline1\nline2\n```\n\nOutro";

    emitAssistantTextDeltaAndEnd({ emit, text });

    (expect* onBlockReply).toHaveBeenCalledTimes(3);
    (expect* onBlockReply.mock.calls[0][0].text).is("Intro");
    (expect* onBlockReply.mock.calls[1][0].text).is("```bash\nline1\nline2\n```");
    (expect* onBlockReply.mock.calls[2][0].text).is("Outro");
  });
});
