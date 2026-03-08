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

(deftest-group "subscribeEmbeddedPiSession reply tags", () => {
  function createBlockReplyHarness() {
    const { session, emit } = createStubSessionHarness();
    const onBlockReply = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      onBlockReply,
      blockReplyBreak: "text_end",
      blockReplyChunking: {
        minChars: 1,
        maxChars: 50,
        breakPreference: "newline",
      },
    });

    return { emit, onBlockReply };
  }

  (deftest "carries reply_to_current across tag-only block chunks", () => {
    const { emit, onBlockReply } = createBlockReplyHarness();

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "[[reply_to_current]]\nHello" });
    emitAssistantTextEnd({ emit });

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "[[reply_to_current]]\nHello" }],
    } as AssistantMessage;
    emit({ type: "message_end", message: assistantMessage });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    const payload = onBlockReply.mock.calls[0]?.[0];
    (expect* payload?.text).is("Hello");
    (expect* payload?.replyToCurrent).is(true);
    (expect* payload?.replyToTag).is(true);
  });

  (deftest "flushes trailing directive tails on stream end", () => {
    const { emit, onBlockReply } = createBlockReplyHarness();

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "Hello [[" });
    emitAssistantTextEnd({ emit });

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "Hello [[" }],
    } as AssistantMessage;
    emit({ type: "message_end", message: assistantMessage });

    (expect* onBlockReply).toHaveBeenCalledTimes(2);
    (expect* onBlockReply.mock.calls[0]?.[0]?.text).is("Hello");
    (expect* onBlockReply.mock.calls[1]?.[0]?.text).is("[[");
  });

  (deftest "streams partial replies past reply_to tags split across chunks", () => {
    const { session, emit } = createStubSessionHarness();

    const onPartialReply = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      onPartialReply,
    });

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "[[reply_to:1897" });
    emitAssistantTextDelta({ emit, delta: "]] Hello" });
    emitAssistantTextDelta({ emit, delta: " world" });
    emitAssistantTextEnd({ emit });

    const lastPayload = onPartialReply.mock.calls.at(-1)?.[0];
    (expect* lastPayload?.text).is("Hello world");
    for (const call of onPartialReply.mock.calls) {
      (expect* call[0]?.text?.includes("[[reply_to")).is(false);
    }
  });
});
