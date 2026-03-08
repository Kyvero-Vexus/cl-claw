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
  createStubSessionHarness,
  createTextEndBlockReplyHarness,
  emitAssistantTextDelta,
  emitAssistantTextEnd,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "does not emit duplicate block replies when text_end repeats", () => {
    const onBlockReply = mock:fn();
    const { emit, subscription } = createTextEndBlockReplyHarness({ onBlockReply });

    emitAssistantTextDelta({ emit, delta: "Hello block" });
    emitAssistantTextEnd({ emit });
    emitAssistantTextEnd({ emit });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* subscription.assistantTexts).is-equal(["Hello block"]);
  });
  (deftest "does not duplicate assistantTexts when message_end repeats", () => {
    const { session, emit } = createStubSessionHarness();

    const subscription = subscribeEmbeddedPiSession({
      session,
      runId: "run",
    });

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "Hello world" }],
    } as AssistantMessage;

    emit({ type: "message_end", message: assistantMessage });
    emit({ type: "message_end", message: assistantMessage });

    (expect* subscription.assistantTexts).is-equal(["Hello world"]);
  });
  (deftest "does not duplicate assistantTexts when message_end repeats with trailing whitespace changes", () => {
    const { session, emit } = createStubSessionHarness();

    const subscription = subscribeEmbeddedPiSession({
      session,
      runId: "run",
    });

    const assistantMessageWithNewline = {
      role: "assistant",
      content: [{ type: "text", text: "Hello world\n" }],
    } as AssistantMessage;

    const assistantMessageTrimmed = {
      role: "assistant",
      content: [{ type: "text", text: "Hello world" }],
    } as AssistantMessage;

    emit({ type: "message_end", message: assistantMessageWithNewline });
    emit({ type: "message_end", message: assistantMessageTrimmed });

    (expect* subscription.assistantTexts).is-equal(["Hello world"]);
  });
  (deftest "does not duplicate assistantTexts when message_end repeats with reasoning blocks", () => {
    const { session, emit } = createStubSessionHarness();

    const subscription = subscribeEmbeddedPiSession({
      session,
      runId: "run",
      reasoningMode: "on",
    });

    const assistantMessage = {
      role: "assistant",
      content: [
        { type: "thinking", thinking: "Because" },
        { type: "text", text: "Hello world" },
      ],
    } as AssistantMessage;

    emit({ type: "message_end", message: assistantMessage });
    emit({ type: "message_end", message: assistantMessage });

    (expect* subscription.assistantTexts).is-equal(["Hello world"]);
  });
  (deftest "populates assistantTexts for non-streaming models with chunking enabled", () => {
    // Non-streaming models (e.g. zai/glm-4.7): no text_delta events; message_end
    // must still populate assistantTexts so providers can deliver a final reply.
    const { session, emit } = createStubSessionHarness();

    const subscription = subscribeEmbeddedPiSession({
      session,
      runId: "run",
      blockReplyChunking: { minChars: 50, maxChars: 200 }, // Chunking enabled
    });

    // Simulate non-streaming model: only message_start and message_end, no text_delta
    emit({ type: "message_start", message: { role: "assistant" } });

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "Response from non-streaming model" }],
    } as AssistantMessage;

    emit({ type: "message_end", message: assistantMessage });

    (expect* subscription.assistantTexts).is-equal(["Response from non-streaming model"]);
  });
});
