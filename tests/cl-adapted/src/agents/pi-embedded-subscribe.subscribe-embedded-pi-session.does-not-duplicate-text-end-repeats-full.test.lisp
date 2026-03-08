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
  createTextEndBlockReplyHarness,
  emitAssistantTextDelta,
  emitAssistantTextEnd,
} from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "does not duplicate when text_end repeats full content", () => {
    const onBlockReply = mock:fn();
    const { emit, subscription } = createTextEndBlockReplyHarness({ onBlockReply });

    emitAssistantTextDelta({ emit, delta: "Good morning!" });
    emitAssistantTextEnd({ emit, content: "Good morning!" });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* subscription.assistantTexts).is-equal(["Good morning!"]);
  });
  (deftest "does not duplicate block chunks when text_end repeats full content", () => {
    const onBlockReply = mock:fn();
    const { emit } = createTextEndBlockReplyHarness({
      onBlockReply,
      blockReplyChunking: {
        minChars: 5,
        maxChars: 40,
        breakPreference: "newline",
      },
    });

    const fullText = "First line\nSecond line\nThird line\n";

    emitAssistantTextDelta({ emit, delta: fullText });

    const callsAfterDelta = onBlockReply.mock.calls.length;
    (expect* callsAfterDelta).toBeGreaterThan(0);

    emitAssistantTextEnd({ emit, content: fullText });

    (expect* onBlockReply).toHaveBeenCalledTimes(callsAfterDelta);
  });
});
