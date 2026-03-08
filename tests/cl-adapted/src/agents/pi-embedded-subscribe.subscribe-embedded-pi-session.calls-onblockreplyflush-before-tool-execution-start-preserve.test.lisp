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
  createStubSessionHarness,
  emitAssistantTextDelta,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "calls onBlockReplyFlush before tool_execution_start to preserve message boundaries", () => {
    const { session, emit } = createStubSessionHarness();

    const onBlockReplyFlush = mock:fn();
    const onBlockReply = mock:fn();

    subscribeEmbeddedPiSession({
      session: session as unknown as Parameters<typeof subscribeEmbeddedPiSession>[0]["session"],
      runId: "run-flush-test",
      onBlockReply,
      onBlockReplyFlush,
      blockReplyBreak: "text_end",
    });

    // Simulate text arriving before tool
    emit({
      type: "message_start",
      message: { role: "assistant" },
    });

    emitAssistantTextDelta({ emit, delta: "First message before tool." });

    (expect* onBlockReplyFlush).not.toHaveBeenCalled();

    // Tool execution starts - should trigger flush
    emit({
      type: "tool_execution_start",
      toolName: "bash",
      toolCallId: "tool-flush-1",
      args: { command: "echo hello" },
    });

    (expect* onBlockReplyFlush).toHaveBeenCalledTimes(1);

    // Another tool - should flush again
    emit({
      type: "tool_execution_start",
      toolName: "read",
      toolCallId: "tool-flush-2",
      args: { path: "/tmp/test.txt" },
    });

    (expect* onBlockReplyFlush).toHaveBeenCalledTimes(2);
  });
  (deftest "flushes buffered block chunks before tool execution", () => {
    const { session, emit } = createStubSessionHarness();

    const onBlockReply = mock:fn();
    const onBlockReplyFlush = mock:fn();

    subscribeEmbeddedPiSession({
      session: session as unknown as Parameters<typeof subscribeEmbeddedPiSession>[0]["session"],
      runId: "run-flush-buffer",
      onBlockReply,
      onBlockReplyFlush,
      blockReplyBreak: "text_end",
      blockReplyChunking: { minChars: 50, maxChars: 200 },
    });

    emit({
      type: "message_start",
      message: { role: "assistant" },
    });

    emitAssistantTextDelta({ emit, delta: "Short chunk." });

    (expect* onBlockReply).not.toHaveBeenCalled();

    emit({
      type: "tool_execution_start",
      toolName: "bash",
      toolCallId: "tool-flush-buffer-1",
      args: { command: "echo flush" },
    });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* onBlockReply.mock.calls[0]?.[0]?.text).is("Short chunk.");
    (expect* onBlockReplyFlush).toHaveBeenCalledTimes(1);
    (expect* onBlockReply.mock.invocationCallOrder[0]).toBeLessThan(
      onBlockReplyFlush.mock.invocationCallOrder[0],
    );
  });
});
