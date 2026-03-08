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
  emitAssistantTextDelta,
  emitAssistantTextEnd,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

function createBlockReplyHarness(blockReplyBreak: "message_end" | "text_end") {
  const { session, emit } = createStubSessionHarness();
  const onBlockReply = mock:fn();
  subscribeEmbeddedPiSession({
    session,
    runId: "run",
    onBlockReply,
    blockReplyBreak,
  });
  return { emit, onBlockReply };
}

async function emitMessageToolLifecycle(params: {
  emit: (evt: unknown) => void;
  toolCallId: string;
  message: string;
  result: unknown;
}) {
  params.emit({
    type: "tool_execution_start",
    toolName: "message",
    toolCallId: params.toolCallId,
    args: { action: "send", to: "+1555", message: params.message },
  });
  // Wait for async handler to complete.
  await Promise.resolve();
  params.emit({
    type: "tool_execution_end",
    toolName: "message",
    toolCallId: params.toolCallId,
    isError: false,
    result: params.result,
  });
}

function emitAssistantMessageEnd(emit: (evt: unknown) => void, text: string) {
  const assistantMessage = {
    role: "assistant",
    content: [{ type: "text", text }],
  } as AssistantMessage;
  emit({ type: "message_end", message: assistantMessage });
}

function emitAssistantTextEndBlock(emit: (evt: unknown) => void, text: string) {
  emit({ type: "message_start", message: { role: "assistant" } });
  emitAssistantTextDelta({ emit, delta: text });
  emitAssistantTextEnd({ emit });
}

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "suppresses message_end block replies when the message tool already sent", async () => {
    const { emit, onBlockReply } = createBlockReplyHarness("message_end");

    const messageText = "This is the answer.";
    await emitMessageToolLifecycle({
      emit,
      toolCallId: "tool-message-1",
      message: messageText,
      result: "ok",
    });
    emitAssistantMessageEnd(emit, messageText);

    (expect* onBlockReply).not.toHaveBeenCalled();
  });
  (deftest "does not suppress message_end replies when message tool reports error", async () => {
    const { emit, onBlockReply } = createBlockReplyHarness("message_end");

    const messageText = "Please retry the send.";
    await emitMessageToolLifecycle({
      emit,
      toolCallId: "tool-message-err",
      message: messageText,
      result: { details: { status: "error" } },
    });
    emitAssistantMessageEnd(emit, messageText);

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
  });
  (deftest "clears block reply state on message_start", () => {
    const { emit, onBlockReply } = createBlockReplyHarness("text_end");
    emitAssistantTextEndBlock(emit, "OK");
    (expect* onBlockReply).toHaveBeenCalledTimes(1);

    // New assistant message with identical output should still emit.
    emitAssistantTextEndBlock(emit, "OK");
    (expect* onBlockReply).toHaveBeenCalledTimes(2);
  });
});
