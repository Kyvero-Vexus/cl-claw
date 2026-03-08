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
  createStubSessionHarness,
  emitAssistantLifecycleErrorAndEnd,
  emitMessageStartAndEndForAssistantText,
  expectSingleAgentEventText,
  extractAgentEventPayloads,
  findLifecycleErrorAgentEvent,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  function createAgentEventHarness(options?: { runId?: string; sessionKey?: string }) {
    const { session, emit } = createStubSessionHarness();
    const onAgentEvent = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: options?.runId ?? "run",
      onAgentEvent,
      sessionKey: options?.sessionKey,
    });

    return { emit, onAgentEvent };
  }

  function createToolErrorHarness(runId: string) {
    const { session, emit } = createStubSessionHarness();
    const subscription = subscribeEmbeddedPiSession({
      session,
      runId,
      sessionKey: "test-session",
    });

    return { emit, subscription };
  }

  function createSubscribedHarness(
    options: Omit<Parameters<typeof subscribeEmbeddedPiSession>[0], "session">,
  ) {
    const { session, emit } = createStubSessionHarness();
    subscribeEmbeddedPiSession({
      session,
      ...options,
    });
    return { emit };
  }

  function emitAssistantTextDelta(
    emit: (evt: unknown) => void,
    delta: string,
    message: Record<string, unknown> = { role: "assistant" },
  ) {
    emit({
      type: "message_update",
      message,
      assistantMessageEvent: {
        type: "text_delta",
        delta,
      },
    });
  }

  function createWriteFailureHarness(params: {
    runId: string;
    path: string;
    content: string;
  }): ReturnType<typeof createToolErrorHarness> {
    const harness = createToolErrorHarness(params.runId);
    emitToolRun({
      emit: harness.emit,
      toolName: "write",
      toolCallId: "w1",
      args: { path: params.path, content: params.content },
      isError: true,
      result: { error: "disk full" },
    });
    (expect* harness.subscription.getLastToolError()?.toolName).is("write");
    return harness;
  }

  function emitToolRun(params: {
    emit: (evt: unknown) => void;
    toolName: string;
    toolCallId: string;
    args?: Record<string, unknown>;
    isError: boolean;
    result: unknown;
  }): void {
    params.emit({
      type: "tool_execution_start",
      toolName: params.toolName,
      toolCallId: params.toolCallId,
      args: params.args,
    });
    params.emit({
      type: "tool_execution_end",
      toolName: params.toolName,
      toolCallId: params.toolCallId,
      isError: params.isError,
      result: params.result,
    });
  }

  it.each(THINKING_TAG_CASES)(
    "streams <%s> reasoning via onReasoningStream without leaking into final text",
    ({ open, close }) => {
      const onReasoningStream = mock:fn();
      const onBlockReply = mock:fn();

      const { emit } = createSubscribedHarness({
        runId: "run",
        onReasoningStream,
        onBlockReply,
        blockReplyBreak: "message_end",
        reasoningMode: "stream",
      });

      emitAssistantTextDelta(emit, `${open}\nBecause`);
      emitAssistantTextDelta(emit, ` it helps\n${close}\n\nFinal answer`);

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

      (expect* onBlockReply).toHaveBeenCalledTimes(1);
      (expect* onBlockReply.mock.calls[0][0].text).is("Final answer");

      const streamTexts = onReasoningStream.mock.calls
        .map((call) => call[0]?.text)
        .filter((value): value is string => typeof value === "string");
      (expect* streamTexts.at(-1)).is("Reasoning:\n_Because it helps_");

      (expect* assistantMessage.content).is-equal([
        { type: "thinking", thinking: "Because it helps" },
        { type: "text", text: "Final answer" },
      ]);
    },
  );
  it.each(THINKING_TAG_CASES)(
    "suppresses <%s> blocks across chunk boundaries",
    ({ open, close }) => {
      const onBlockReply = mock:fn();

      const { emit } = createSubscribedHarness({
        runId: "run",
        onBlockReply,
        blockReplyBreak: "text_end",
        blockReplyChunking: {
          minChars: 5,
          maxChars: 50,
          breakPreference: "newline",
        },
      });

      emit({ type: "message_start", message: { role: "assistant" } });
      emitAssistantTextDelta(emit, `${open}Reasoning chunk that should not leak`);

      (expect* onBlockReply).not.toHaveBeenCalled();

      emitAssistantTextDelta(emit, `${close}\n\nFinal answer`);
      emit({
        type: "message_update",
        message: { role: "assistant" },
        assistantMessageEvent: { type: "text_end" },
      });

      const payloadTexts = onBlockReply.mock.calls
        .map((call) => call[0]?.text)
        .filter((value): value is string => typeof value === "string");
      (expect* payloadTexts.length).toBeGreaterThan(0);
      for (const text of payloadTexts) {
        (expect* text).not.contains("Reasoning");
        (expect* text).not.contains(open);
      }
      const combined = payloadTexts.join(" ").replace(/\s+/g, " ").trim();
      (expect* combined).is("Final answer");
    },
  );

  (deftest "streams native thinking_delta events and signals reasoning end", () => {
    const onReasoningStream = mock:fn();
    const onReasoningEnd = mock:fn();

    const { emit } = createSubscribedHarness({
      runId: "run",
      reasoningMode: "stream",
      onReasoningStream,
      onReasoningEnd,
    });

    emit({
      type: "message_update",
      message: {
        role: "assistant",
        content: [{ type: "thinking", thinking: "Checking files" }],
      },
      assistantMessageEvent: {
        type: "thinking_delta",
        delta: "Checking files",
      },
    });

    emit({
      type: "message_update",
      message: {
        role: "assistant",
        content: [{ type: "thinking", thinking: "Checking files done" }],
      },
      assistantMessageEvent: {
        type: "thinking_end",
      },
    });

    const streamTexts = onReasoningStream.mock.calls
      .map((call) => call[0]?.text)
      .filter((value): value is string => typeof value === "string");
    (expect* streamTexts.at(-1)).is("Reasoning:\n_Checking files done_");
    (expect* onReasoningEnd).toHaveBeenCalledTimes(1);
  });

  (deftest "emits reasoning end once when native and tagged reasoning end overlap", () => {
    const onReasoningEnd = mock:fn();

    const { emit } = createSubscribedHarness({
      runId: "run",
      reasoningMode: "stream",
      onReasoningStream: mock:fn(),
      onReasoningEnd,
    });

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta(emit, "<think>Checking");
    emit({
      type: "message_update",
      message: {
        role: "assistant",
        content: [{ type: "thinking", thinking: "Checking" }],
      },
      assistantMessageEvent: {
        type: "thinking_end",
      },
    });

    emitAssistantTextDelta(emit, " files</think>\nFinal answer");

    (expect* onReasoningEnd).toHaveBeenCalledTimes(1);
  });

  (deftest "emits delta chunks in agent events for streaming assistant text", () => {
    const { emit, onAgentEvent } = createAgentEventHarness();

    emit({ type: "message_start", message: { role: "assistant" } });
    emit({
      type: "message_update",
      message: { role: "assistant" },
      assistantMessageEvent: { type: "text_delta", delta: "Hello" },
    });
    emit({
      type: "message_update",
      message: { role: "assistant" },
      assistantMessageEvent: { type: "text_delta", delta: " world" },
    });

    const payloads = extractAgentEventPayloads(onAgentEvent.mock.calls);
    (expect* payloads[0]?.text).is("Hello");
    (expect* payloads[0]?.delta).is("Hello");
    (expect* payloads[1]?.text).is("Hello world");
    (expect* payloads[1]?.delta).is(" world");
  });

  (deftest "emits agent events on message_end for non-streaming assistant text", () => {
    const { session, emit } = createStubSessionHarness();

    const onAgentEvent = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      onAgentEvent,
    });
    emitMessageStartAndEndForAssistantText({ emit, text: "Hello world" });
    expectSingleAgentEventText(onAgentEvent.mock.calls, "Hello world");
  });

  (deftest "does not emit duplicate agent events when message_end repeats", () => {
    const { emit, onAgentEvent } = createAgentEventHarness();

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "Hello world" }],
    } as AssistantMessage;

    emit({ type: "message_start", message: assistantMessage });
    emit({ type: "message_end", message: assistantMessage });
    emit({ type: "message_end", message: assistantMessage });

    const payloads = extractAgentEventPayloads(onAgentEvent.mock.calls);
    (expect* payloads).has-length(1);
  });

  (deftest "skips agent events when cleaned text rewinds mid-stream", () => {
    const { emit, onAgentEvent } = createAgentEventHarness();

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta(emit, "MEDIA:");
    emitAssistantTextDelta(emit, " https://example.com/a.png\nCaption");

    const payloads = extractAgentEventPayloads(onAgentEvent.mock.calls);
    (expect* payloads).has-length(1);
    (expect* payloads[0]?.text).is("MEDIA:");
  });

  (deftest "emits agent events when media arrives without text", () => {
    const { emit, onAgentEvent } = createAgentEventHarness();

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta(emit, "MEDIA: https://example.com/a.png");

    const payloads = extractAgentEventPayloads(onAgentEvent.mock.calls);
    (expect* payloads).has-length(1);
    (expect* payloads[0]?.text).is("");
    (expect* payloads[0]?.mediaUrls).is-equal(["https://example.com/a.png"]);
  });

  (deftest "keeps unresolved mutating failure when an unrelated tool succeeds", () => {
    const { emit, subscription } = createWriteFailureHarness({
      runId: "run-tools-1",
      path: "/tmp/demo.txt",
      content: "next",
    });

    emitToolRun({
      emit,
      toolName: "read",
      toolCallId: "r1",
      args: { path: "/tmp/demo.txt" },
      isError: false,
      result: { text: "ok" },
    });

    (expect* subscription.getLastToolError()?.toolName).is("write");
  });

  (deftest "clears unresolved mutating failure when the same action succeeds", () => {
    const { emit, subscription } = createWriteFailureHarness({
      runId: "run-tools-2",
      path: "/tmp/demo.txt",
      content: "next",
    });

    emitToolRun({
      emit,
      toolName: "write",
      toolCallId: "w2",
      args: { path: "/tmp/demo.txt", content: "retry" },
      isError: false,
      result: { ok: true },
    });

    (expect* subscription.getLastToolError()).toBeUndefined();
  });

  (deftest "keeps unresolved mutating failure when same tool succeeds on a different target", () => {
    const { emit, subscription } = createToolErrorHarness("run-tools-3");

    emitToolRun({
      emit,
      toolName: "write",
      toolCallId: "w1",
      args: { path: "/tmp/a.txt", content: "first" },
      isError: true,
      result: { error: "disk full" },
    });

    emitToolRun({
      emit,
      toolName: "write",
      toolCallId: "w2",
      args: { path: "/tmp/b.txt", content: "second" },
      isError: false,
      result: { ok: true },
    });

    (expect* subscription.getLastToolError()?.toolName).is("write");
  });

  (deftest "keeps unresolved session_status model-mutation failure on later read-only status success", () => {
    const { emit, subscription } = createToolErrorHarness("run-tools-4");

    emitToolRun({
      emit,
      toolName: "session_status",
      toolCallId: "s1",
      args: { sessionKey: "agent:main:main", model: "openai/gpt-4o" },
      isError: true,
      result: { error: "Model not allowed." },
    });

    emitToolRun({
      emit,
      toolName: "session_status",
      toolCallId: "s2",
      args: { sessionKey: "agent:main:main" },
      isError: false,
      result: { ok: true },
    });

    (expect* subscription.getLastToolError()?.toolName).is("session_status");
  });

  (deftest "emits lifecycle:error event on agent_end when last assistant message was an error", async () => {
    const { emit, onAgentEvent } = createAgentEventHarness({
      runId: "run-error",
      sessionKey: "test-session",
    });

    emitAssistantLifecycleErrorAndEnd({
      emit,
      errorMessage: "429 Rate limit exceeded",
    });

    // Look for lifecycle:error event
    const lifecycleError = findLifecycleErrorAgentEvent(onAgentEvent.mock.calls);

    (expect* lifecycleError).toBeDefined();
    (expect* lifecycleError?.data?.error).contains("API rate limit reached");
  });
});
