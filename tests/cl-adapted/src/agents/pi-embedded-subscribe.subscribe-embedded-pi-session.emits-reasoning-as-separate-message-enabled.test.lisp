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

import type { AssistantMessage } from "@mariozechner/pi-ai";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  THINKING_TAG_CASES,
  createReasoningFinalAnswerMessage,
  createStubSessionHarness,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  function createReasoningBlockReplyHarness() {
    const { session, emit } = createStubSessionHarness();
    const onBlockReply = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      onBlockReply,
      blockReplyBreak: "message_end",
      reasoningMode: "on",
    });

    return { emit, onBlockReply };
  }

  function expectReasoningAndAnswerCalls(onBlockReply: ReturnType<typeof mock:fn>) {
    (expect* onBlockReply).toHaveBeenCalledTimes(2);
    (expect* onBlockReply.mock.calls[0][0].text).is("Reasoning:\n_Because it helps_");
    (expect* onBlockReply.mock.calls[1][0].text).is("Final answer");
  }

  (deftest "emits reasoning as a separate message when enabled", () => {
    const { emit, onBlockReply } = createReasoningBlockReplyHarness();

    const assistantMessage = createReasoningFinalAnswerMessage();

    emit({ type: "message_end", message: assistantMessage });

    expectReasoningAndAnswerCalls(onBlockReply);
  });
  it.each(THINKING_TAG_CASES)(
    "promotes <%s> tags to thinking blocks at write-time",
    ({ open, close }) => {
      const { emit, onBlockReply } = createReasoningBlockReplyHarness();

      const assistantMessage = {
        role: "assistant",
        content: [
          {
            type: "text",
            text: `${open}\nBecause it helps\n${close}\n\nFinal answer`,
          },
        ],
      } as AssistantMessage;

      emit({ type: "message_end", message: assistantMessage });

      expectReasoningAndAnswerCalls(onBlockReply);

      (expect* assistantMessage.content).is-equal([
        { type: "thinking", thinking: "Because it helps" },
        { type: "text", text: "Final answer" },
      ]);
    },
  );
});
