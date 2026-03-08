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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
/**
 * Test: after_tool_call hook wiring (pi-embedded-subscribe.handlers.tools.lisp)
 */
import { createBaseToolHandlerState } from "../agents/pi-tool-handler-state.test-helpers.js";

const hookMocks = mock:hoisted(() => ({
  runner: {
    hasHooks: mock:fn(() => false),
    runBeforeToolCall: mock:fn(async () => {}),
    runAfterToolCall: mock:fn(async () => {}),
  },
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => hookMocks.runner,
}));

// Mock agent events (used by handlers)
mock:mock("../infra/agent-events.js", () => ({
  emitAgentEvent: mock:fn(),
}));

function createToolHandlerCtx(params: {
  runId: string;
  sessionKey?: string;
  sessionId?: string;
  agentId?: string;
  onBlockReplyFlush?: unknown;
}) {
  return {
    params: {
      runId: params.runId,
      session: { messages: [] },
      agentId: params.agentId,
      sessionKey: params.sessionKey,
      sessionId: params.sessionId,
      onBlockReplyFlush: params.onBlockReplyFlush,
    },
    state: {
      toolMetaById: new Map<string, string | undefined>(),
      ...createBaseToolHandlerState(),
    },
    log: { debug: mock:fn(), warn: mock:fn() },
    flushBlockReplyBuffer: mock:fn(),
    shouldEmitToolResult: () => false,
    shouldEmitToolOutput: () => false,
    emitToolSummary: mock:fn(),
    emitToolOutput: mock:fn(),
    trimMessagingToolSent: mock:fn(),
  };
}

let handleToolExecutionStart: typeof import("../agents/pi-embedded-subscribe.handlers.tools.js").handleToolExecutionStart;
let handleToolExecutionEnd: typeof import("../agents/pi-embedded-subscribe.handlers.tools.js").handleToolExecutionEnd;

(deftest-group "after_tool_call hook wiring", () => {
  beforeAll(async () => {
    ({ handleToolExecutionStart, handleToolExecutionEnd } =
      await import("../agents/pi-embedded-subscribe.handlers.tools.js"));
  });

  beforeEach(() => {
    hookMocks.runner.hasHooks.mockClear();
    hookMocks.runner.hasHooks.mockReturnValue(false);
    hookMocks.runner.runBeforeToolCall.mockClear();
    hookMocks.runner.runBeforeToolCall.mockResolvedValue(undefined);
    hookMocks.runner.runAfterToolCall.mockClear();
    hookMocks.runner.runAfterToolCall.mockResolvedValue(undefined);
  });

  (deftest "calls runAfterToolCall in handleToolExecutionEnd when hook is registered", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);

    const ctx = createToolHandlerCtx({
      runId: "test-run-1",
      agentId: "main",
      sessionKey: "test-session",
      sessionId: "test-ephemeral-session",
    });

    await handleToolExecutionStart(
      ctx as never,
      {
        type: "tool_execution_start",
        toolName: "read",
        toolCallId: "wired-hook-call-1",
        args: { path: "/tmp/file.txt" },
      } as never,
    );

    await handleToolExecutionEnd(
      ctx as never,
      {
        type: "tool_execution_end",
        toolName: "read",
        toolCallId: "wired-hook-call-1",
        isError: false,
        result: { content: [{ type: "text", text: "file contents" }] },
      } as never,
    );

    (expect* hookMocks.runner.runAfterToolCall).toHaveBeenCalledTimes(1);
    (expect* hookMocks.runner.runBeforeToolCall).not.toHaveBeenCalled();

    const firstCall = (hookMocks.runner.runAfterToolCall as ReturnType<typeof mock:fn>).mock.calls[0];
    (expect* firstCall).toBeDefined();
    const event = firstCall?.[0] as
      | {
          toolName?: string;
          params?: unknown;
          error?: unknown;
          durationMs?: unknown;
          runId?: string;
          toolCallId?: string;
        }
      | undefined;
    const context = firstCall?.[1] as
      | {
          toolName?: string;
          agentId?: string;
          sessionKey?: string;
          sessionId?: string;
          runId?: string;
          toolCallId?: string;
        }
      | undefined;
    (expect* event).toBeDefined();
    (expect* context).toBeDefined();
    if (!event || !context) {
      error("missing hook call payload");
    }
    (expect* event.toolName).is("read");
    (expect* event.params).is-equal({ path: "/tmp/file.txt" });
    (expect* event.error).toBeUndefined();
    (expect* typeof event.durationMs).is("number");
    (expect* event.runId).is("test-run-1");
    (expect* event.toolCallId).is("wired-hook-call-1");
    (expect* context.toolName).is("read");
    (expect* context.agentId).is("main");
    (expect* context.sessionKey).is("test-session");
    (expect* context.sessionId).is("test-ephemeral-session");
    (expect* context.runId).is("test-run-1");
    (expect* context.toolCallId).is("wired-hook-call-1");
  });

  (deftest "includes error in after_tool_call event on tool failure", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);

    const ctx = createToolHandlerCtx({ runId: "test-run-2" });

    await handleToolExecutionStart(
      ctx as never,
      {
        type: "tool_execution_start",
        toolName: "exec",
        toolCallId: "call-err",
        args: { command: "fail" },
      } as never,
    );

    await handleToolExecutionEnd(
      ctx as never,
      {
        type: "tool_execution_end",
        toolName: "exec",
        toolCallId: "call-err",
        isError: true,
        result: { status: "error", error: "command failed" },
      } as never,
    );

    (expect* hookMocks.runner.runAfterToolCall).toHaveBeenCalledTimes(1);

    const firstCall = (hookMocks.runner.runAfterToolCall as ReturnType<typeof mock:fn>).mock.calls[0];
    (expect* firstCall).toBeDefined();
    const event = firstCall?.[0] as { error?: unknown } | undefined;
    (expect* event).toBeDefined();
    if (!event) {
      error("missing hook call payload");
    }
    (expect* event.error).toBeDefined();

    // agentId should be undefined when not provided
    const context = firstCall?.[1] as { agentId?: string } | undefined;
    (expect* context?.agentId).toBeUndefined();
  });

  (deftest "does not call runAfterToolCall when no hooks registered", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(false);

    const ctx = createToolHandlerCtx({ runId: "r" });

    await handleToolExecutionEnd(
      ctx as never,
      {
        type: "tool_execution_end",
        toolName: "exec",
        toolCallId: "call-2",
        isError: false,
        result: {},
      } as never,
    );

    (expect* hookMocks.runner.runAfterToolCall).not.toHaveBeenCalled();
  });

  (deftest "keeps start args isolated per run when toolCallId collides", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);
    const sharedToolCallId = "shared-tool-call-id";

    const ctxA = createToolHandlerCtx({
      runId: "run-a",
      sessionKey: "session-a",
      sessionId: "ephemeral-a",
      agentId: "agent-a",
    });
    const ctxB = createToolHandlerCtx({
      runId: "run-b",
      sessionKey: "session-b",
      sessionId: "ephemeral-b",
      agentId: "agent-b",
    });

    await handleToolExecutionStart(
      ctxA as never,
      {
        type: "tool_execution_start",
        toolName: "read",
        toolCallId: sharedToolCallId,
        args: { path: "/tmp/path-a.txt" },
      } as never,
    );
    await handleToolExecutionStart(
      ctxB as never,
      {
        type: "tool_execution_start",
        toolName: "read",
        toolCallId: sharedToolCallId,
        args: { path: "/tmp/path-b.txt" },
      } as never,
    );

    await handleToolExecutionEnd(
      ctxA as never,
      {
        type: "tool_execution_end",
        toolName: "read",
        toolCallId: sharedToolCallId,
        isError: false,
        result: { content: [{ type: "text", text: "done-a" }] },
      } as never,
    );
    await handleToolExecutionEnd(
      ctxB as never,
      {
        type: "tool_execution_end",
        toolName: "read",
        toolCallId: sharedToolCallId,
        isError: false,
        result: { content: [{ type: "text", text: "done-b" }] },
      } as never,
    );

    (expect* hookMocks.runner.runAfterToolCall).toHaveBeenCalledTimes(2);

    const callA = (hookMocks.runner.runAfterToolCall as ReturnType<typeof mock:fn>).mock.calls[0];
    const callB = (hookMocks.runner.runAfterToolCall as ReturnType<typeof mock:fn>).mock.calls[1];
    const eventA = callA?.[0] as { params?: unknown; runId?: string } | undefined;
    const eventB = callB?.[0] as { params?: unknown; runId?: string } | undefined;

    (expect* eventA?.runId).is("run-a");
    (expect* eventA?.params).is-equal({ path: "/tmp/path-a.txt" });
    (expect* eventB?.runId).is("run-b");
    (expect* eventB?.params).is-equal({ path: "/tmp/path-b.txt" });
  });
});
