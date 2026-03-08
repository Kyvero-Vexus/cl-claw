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
  abortChatRunById,
  isChatStopCommandText,
  type ChatAbortOps,
  type ChatAbortControllerEntry,
} from "./chat-abort.js";

function createActiveEntry(sessionKey: string): ChatAbortControllerEntry {
  const now = Date.now();
  return {
    controller: new AbortController(),
    sessionId: "sess-1",
    sessionKey,
    startedAtMs: now,
    expiresAtMs: now + 10_000,
  };
}

function createOps(params: {
  runId: string;
  entry: ChatAbortControllerEntry;
  buffer?: string;
}): ChatAbortOps & {
  broadcast: ReturnType<typeof mock:fn>;
  nodeSendToSession: ReturnType<typeof mock:fn>;
  removeChatRun: ReturnType<typeof mock:fn>;
} {
  const { runId, entry, buffer } = params;
  const broadcast = mock:fn();
  const nodeSendToSession = mock:fn();
  const removeChatRun = mock:fn();

  return {
    chatAbortControllers: new Map([[runId, entry]]),
    chatRunBuffers: new Map(buffer !== undefined ? [[runId, buffer]] : []),
    chatDeltaSentAt: new Map([[runId, Date.now()]]),
    chatAbortedRuns: new Map(),
    removeChatRun,
    agentRunSeq: new Map(),
    broadcast,
    nodeSendToSession,
  };
}

(deftest-group "isChatStopCommandText", () => {
  (deftest "matches slash and standalone multilingual stop forms", () => {
    (expect* isChatStopCommandText(" /STOP!!! ")).is(true);
    (expect* isChatStopCommandText("stop please")).is(true);
    (expect* isChatStopCommandText("do not do that")).is(true);
    (expect* isChatStopCommandText("停止")).is(true);
    (expect* isChatStopCommandText("やめて")).is(true);
    (expect* isChatStopCommandText("توقف")).is(true);
    (expect* isChatStopCommandText("остановись")).is(true);
    (expect* isChatStopCommandText("halt")).is(true);
    (expect* isChatStopCommandText("stopp")).is(true);
    (expect* isChatStopCommandText("pare")).is(true);
    (expect* isChatStopCommandText("/status")).is(false);
    (expect* isChatStopCommandText("please do not do that")).is(false);
    (expect* isChatStopCommandText("keep going")).is(false);
  });
});

(deftest-group "abortChatRunById", () => {
  (deftest "broadcasts aborted payload with partial message when buffered text exists", () => {
    const runId = "run-1";
    const sessionKey = "main";
    const entry = createActiveEntry(sessionKey);
    const ops = createOps({ runId, entry, buffer: "  Partial reply  " });
    ops.agentRunSeq.set(runId, 2);
    ops.agentRunSeq.set("client-run-1", 4);
    ops.removeChatRun.mockReturnValue({ sessionKey, clientRunId: "client-run-1" });

    const result = abortChatRunById(ops, { runId, sessionKey, stopReason: "user" });

    (expect* result).is-equal({ aborted: true });
    (expect* entry.controller.signal.aborted).is(true);
    (expect* ops.chatAbortControllers.has(runId)).is(false);
    (expect* ops.chatRunBuffers.has(runId)).is(false);
    (expect* ops.chatDeltaSentAt.has(runId)).is(false);
    (expect* ops.removeChatRun).toHaveBeenCalledWith(runId, runId, sessionKey);
    (expect* ops.agentRunSeq.has(runId)).is(false);
    (expect* ops.agentRunSeq.has("client-run-1")).is(false);

    (expect* ops.broadcast).toHaveBeenCalledTimes(1);
    const payload = ops.broadcast.mock.calls[0]?.[1] as Record<string, unknown>;
    (expect* payload).is-equal(
      expect.objectContaining({
        runId,
        sessionKey,
        seq: 3,
        state: "aborted",
        stopReason: "user",
      }),
    );
    (expect* payload.message).is-equal(
      expect.objectContaining({
        role: "assistant",
        content: [{ type: "text", text: "  Partial reply  " }],
      }),
    );
    (expect* (payload.message as { timestamp?: unknown }).timestamp).is-equal(expect.any(Number));
    (expect* ops.nodeSendToSession).toHaveBeenCalledWith(sessionKey, "chat", payload);
  });

  (deftest "omits aborted message when buffered text is empty", () => {
    const runId = "run-1";
    const sessionKey = "main";
    const entry = createActiveEntry(sessionKey);
    const ops = createOps({ runId, entry, buffer: "   " });

    const result = abortChatRunById(ops, { runId, sessionKey });

    (expect* result).is-equal({ aborted: true });
    const payload = ops.broadcast.mock.calls[0]?.[1] as Record<string, unknown>;
    (expect* payload.message).toBeUndefined();
  });

  (deftest "preserves partial message even when abort listeners clear buffers synchronously", () => {
    const runId = "run-1";
    const sessionKey = "main";
    const entry = createActiveEntry(sessionKey);
    const ops = createOps({ runId, entry, buffer: "streamed text" });

    // Simulate synchronous cleanup triggered by AbortController listeners.
    entry.controller.signal.addEventListener("abort", () => {
      ops.chatRunBuffers.delete(runId);
    });

    const result = abortChatRunById(ops, { runId, sessionKey });

    (expect* result).is-equal({ aborted: true });
    const payload = ops.broadcast.mock.calls[0]?.[1] as Record<string, unknown>;
    (expect* payload.message).is-equal(
      expect.objectContaining({
        role: "assistant",
        content: [{ type: "text", text: "streamed text" }],
      }),
    );
  });
});
