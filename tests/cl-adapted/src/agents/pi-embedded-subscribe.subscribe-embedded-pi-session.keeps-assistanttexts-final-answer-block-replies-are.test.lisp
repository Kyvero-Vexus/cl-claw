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
  createReasoningFinalAnswerMessage,
  createStubSessionHarness,
  emitAssistantTextDelta,
  emitAssistantTextEnd,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "keeps assistantTexts to the final answer when block replies are disabled", () => {
    const { session, emit } = createStubSessionHarness();

    const subscription = subscribeEmbeddedPiSession({
      session,
      runId: "run",
      reasoningMode: "on",
    });

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "Final " });
    emitAssistantTextDelta({ emit, delta: "answer" });
    emitAssistantTextEnd({ emit });

    const assistantMessage = createReasoningFinalAnswerMessage();

    emit({ type: "message_end", message: assistantMessage });

    (expect* subscription.assistantTexts).is-equal(["Final answer"]);
  });
  (deftest "suppresses partial replies when reasoning is enabled and block replies are disabled", () => {
    const { session, emit } = createStubSessionHarness();

    const onPartialReply = mock:fn();

    const subscription = subscribeEmbeddedPiSession({
      session,
      runId: "run",
      reasoningMode: "on",
      onPartialReply,
    });

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "Draft " });
    emitAssistantTextDelta({ emit, delta: "reply" });

    (expect* onPartialReply).not.toHaveBeenCalled();

    const assistantMessage = createReasoningFinalAnswerMessage();

    emit({ type: "message_end", message: assistantMessage });
    emitAssistantTextEnd({ emit, content: "Draft reply" });

    (expect* onPartialReply).not.toHaveBeenCalled();
    (expect* subscription.assistantTexts).is-equal(["Final answer"]);
  });
});
