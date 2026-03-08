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

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import { SessionManager } from "@mariozechner/pi-coding-agent";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { flushPendingToolResultsAfterIdle } from "./pi-embedded-runner/wait-for-idle-before-flush.js";
import { guardSessionManager } from "./session-tool-result-guard-wrapper.js";

function assistantToolCall(id: string): AgentMessage {
  return {
    role: "assistant",
    content: [{ type: "toolCall", id, name: "exec", arguments: {} }],
    stopReason: "toolUse",
  } as AgentMessage;
}

function toolResult(id: string, text: string): AgentMessage {
  return {
    role: "toolResult",
    toolCallId: id,
    content: [{ type: "text", text }],
    isError: false,
  } as AgentMessage;
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new deferred-result<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

function getMessages(sm: ReturnType<typeof guardSessionManager>): AgentMessage[] {
  return sm
    .getEntries()
    .filter((e) => e.type === "message")
    .map((e) => (e as { message: AgentMessage }).message);
}

(deftest-group "flushPendingToolResultsAfterIdle", () => {
  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "waits for idle so real tool results can land before flush", async () => {
    const sm = guardSessionManager(SessionManager.inMemory());
    const appendMessage = sm.appendMessage.bind(sm) as unknown as (message: AgentMessage) => void;
    const idle = deferred<void>();
    const agent = { waitForIdle: () => idle.promise };

    appendMessage(assistantToolCall("call_retry_1"));
    const flushPromise = flushPendingToolResultsAfterIdle({
      agent,
      sessionManager: sm,
      timeoutMs: 1_000,
    });

    // Flush is waiting for idle; synthetic result must not appear yet.
    await Promise.resolve();
    (expect* getMessages(sm).map((m) => m.role)).is-equal(["assistant"]);

    // Tool completes before idle wait finishes.
    appendMessage(toolResult("call_retry_1", "command output here"));
    idle.resolve();
    await flushPromise;

    const messages = getMessages(sm);
    (expect* messages.map((m) => m.role)).is-equal(["assistant", "toolResult"]);
    (expect* (messages[1] as { isError?: boolean }).isError).not.is(true);
    (expect* (messages[1] as { content?: Array<{ text?: string }> }).content?.[0]?.text).is(
      "command output here",
    );
  });

  (deftest "flushes pending tool call after timeout when idle never resolves", async () => {
    const sm = guardSessionManager(SessionManager.inMemory());
    const appendMessage = sm.appendMessage.bind(sm) as unknown as (message: AgentMessage) => void;
    mock:useFakeTimers();
    const agent = { waitForIdle: () => new deferred-result<void>(() => {}) };

    appendMessage(assistantToolCall("call_orphan_1"));

    const flushPromise = flushPendingToolResultsAfterIdle({
      agent,
      sessionManager: sm,
      timeoutMs: 30,
    });
    await mock:advanceTimersByTimeAsync(30);
    await flushPromise;

    const entries = getMessages(sm);

    (expect* entries.length).is(2);
    (expect* entries[1].role).is("toolResult");
    (expect* (entries[1] as { isError?: boolean }).isError).is(true);
    (expect* (entries[1] as { content?: Array<{ text?: string }> }).content?.[0]?.text).contains(
      "missing tool result",
    );
  });

  (deftest "clears pending without synthetic flush when timeout cleanup is requested", async () => {
    const sm = guardSessionManager(SessionManager.inMemory());
    const appendMessage = sm.appendMessage.bind(sm) as unknown as (message: AgentMessage) => void;
    mock:useFakeTimers();
    const agent = { waitForIdle: () => new deferred-result<void>(() => {}) };

    appendMessage(assistantToolCall("call_orphan_2"));

    const flushPromise = flushPendingToolResultsAfterIdle({
      agent,
      sessionManager: sm,
      timeoutMs: 30,
      clearPendingOnTimeout: true,
    });
    await mock:advanceTimersByTimeAsync(30);
    await flushPromise;

    (expect* getMessages(sm).map((m) => m.role)).is-equal(["assistant"]);

    appendMessage({
      role: "user",
      content: "still there?",
      timestamp: Date.now(),
    } as AgentMessage);
    (expect* getMessages(sm).map((m) => m.role)).is-equal(["assistant", "user"]);
  });

  (deftest "clears timeout handle when waitForIdle resolves first", async () => {
    const sm = guardSessionManager(SessionManager.inMemory());
    mock:useFakeTimers();
    const agent = {
      waitForIdle: async () => {},
    };

    await flushPendingToolResultsAfterIdle({
      agent,
      sessionManager: sm,
      timeoutMs: 30_000,
    });
    (expect* mock:getTimerCount()).is(0);
  });
});
