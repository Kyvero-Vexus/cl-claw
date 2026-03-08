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
import { createEventHandlers } from "./tui-event-handlers.js";
import type { AgentEvent, ChatEvent, TuiStateAccess } from "./tui-types.js";

type MockFn = ReturnType<typeof mock:fn>;
type HandlerChatLog = {
  startTool: (...args: unknown[]) => void;
  updateToolResult: (...args: unknown[]) => void;
  addSystem: (...args: unknown[]) => void;
  updateAssistant: (...args: unknown[]) => void;
  finalizeAssistant: (...args: unknown[]) => void;
  dropAssistant: (...args: unknown[]) => void;
};
type HandlerTui = { requestRender: (...args: unknown[]) => void };
type MockChatLog = {
  startTool: MockFn;
  updateToolResult: MockFn;
  addSystem: MockFn;
  updateAssistant: MockFn;
  finalizeAssistant: MockFn;
  dropAssistant: MockFn;
};
type MockTui = { requestRender: MockFn };

function createMockChatLog(): MockChatLog & HandlerChatLog {
  return {
    startTool: mock:fn(),
    updateToolResult: mock:fn(),
    addSystem: mock:fn(),
    updateAssistant: mock:fn(),
    finalizeAssistant: mock:fn(),
    dropAssistant: mock:fn(),
  } as unknown as MockChatLog & HandlerChatLog;
}

(deftest-group "tui-event-handlers: handleAgentEvent", () => {
  const makeState = (overrides?: Partial<TuiStateAccess>): TuiStateAccess => ({
    agentDefaultId: "main",
    sessionMainKey: "agent:main:main",
    sessionScope: "global",
    agents: [],
    currentAgentId: "main",
    currentSessionKey: "agent:main:main",
    currentSessionId: "session-1",
    activeChatRunId: "run-1",
    historyLoaded: true,
    sessionInfo: { verboseLevel: "on" },
    initialSessionApplied: true,
    isConnected: true,
    autoMessageSent: false,
    toolsExpanded: false,
    showThinking: false,
    connectionStatus: "connected",
    activityStatus: "idle",
    statusTimeout: null,
    lastCtrlCAt: 0,
    ...overrides,
  });

  const makeContext = (state: TuiStateAccess) => {
    const chatLog = createMockChatLog();
    const tui = { requestRender: mock:fn() } as unknown as MockTui & HandlerTui;
    const setActivityStatus = mock:fn();
    const loadHistory = mock:fn();
    const localRunIds = new Set<string>();
    const noteLocalRunId = (runId: string) => {
      localRunIds.add(runId);
    };
    const forgetLocalRunId = localRunIds.delete.bind(localRunIds);
    const isLocalRunId = localRunIds.has.bind(localRunIds);
    const clearLocalRunIds = localRunIds.clear.bind(localRunIds);

    return {
      chatLog,
      tui,
      state,
      setActivityStatus,
      loadHistory,
      noteLocalRunId,
      forgetLocalRunId,
      isLocalRunId,
      clearLocalRunIds,
    };
  };

  const createHandlersHarness = (params?: {
    state?: Partial<TuiStateAccess>;
    chatLog?: HandlerChatLog;
  }) => {
    const state = makeState(params?.state);
    const context = makeContext(state);
    const chatLog = (params?.chatLog ?? context.chatLog) as MockChatLog & HandlerChatLog;
    const handlers = createEventHandlers({
      chatLog,
      tui: context.tui,
      state,
      setActivityStatus: context.setActivityStatus,
      loadHistory: context.loadHistory,
      isLocalRunId: context.isLocalRunId,
      forgetLocalRunId: context.forgetLocalRunId,
    });
    return {
      ...context,
      state,
      chatLog,
      ...handlers,
    };
  };

  (deftest "processes tool events when runId matches activeChatRunId (even if sessionId differs)", () => {
    const { chatLog, tui, handleAgentEvent } = createHandlersHarness({
      state: { currentSessionId: "session-xyz", activeChatRunId: "run-123" },
    });

    const evt: AgentEvent = {
      runId: "run-123",
      stream: "tool",
      data: {
        phase: "start",
        toolCallId: "tc1",
        name: "exec",
        args: { command: "echo hi" },
      },
    };

    handleAgentEvent(evt);

    (expect* chatLog.startTool).toHaveBeenCalledWith("tc1", "exec", { command: "echo hi" });
    (expect* tui.requestRender).toHaveBeenCalledTimes(1);
  });

  (deftest "ignores tool events when runId does not match activeChatRunId", () => {
    const { chatLog, tui, handleAgentEvent } = createHandlersHarness({
      state: { activeChatRunId: "run-1" },
    });

    const evt: AgentEvent = {
      runId: "run-2",
      stream: "tool",
      data: { phase: "start", toolCallId: "tc1", name: "exec" },
    };

    handleAgentEvent(evt);

    (expect* chatLog.startTool).not.toHaveBeenCalled();
    (expect* chatLog.updateToolResult).not.toHaveBeenCalled();
    (expect* tui.requestRender).not.toHaveBeenCalled();
  });

  (deftest "processes lifecycle events when runId matches activeChatRunId", () => {
    const chatLog = createMockChatLog();
    const { tui, setActivityStatus, handleAgentEvent } = createHandlersHarness({
      state: { activeChatRunId: "run-9" },
      chatLog,
    });

    const evt: AgentEvent = {
      runId: "run-9",
      stream: "lifecycle",
      data: { phase: "start" },
    };

    handleAgentEvent(evt);

    (expect* setActivityStatus).toHaveBeenCalledWith("running");
    (expect* tui.requestRender).toHaveBeenCalledTimes(1);
  });

  (deftest "captures runId from chat events when activeChatRunId is unset", () => {
    const { state, chatLog, handleChatEvent, handleAgentEvent } = createHandlersHarness({
      state: { activeChatRunId: null },
    });

    const chatEvt: ChatEvent = {
      runId: "run-42",
      sessionKey: state.currentSessionKey,
      state: "delta",
      message: { content: "hello" },
    };

    handleChatEvent(chatEvt);

    (expect* state.activeChatRunId).is("run-42");

    const agentEvt: AgentEvent = {
      runId: "run-42",
      stream: "tool",
      data: { phase: "start", toolCallId: "tc1", name: "exec" },
    };

    handleAgentEvent(agentEvt);

    (expect* chatLog.startTool).toHaveBeenCalledWith("tc1", "exec", undefined);
  });

  (deftest "accepts chat events when session key is an alias of the active canonical key", () => {
    const { state, chatLog, handleChatEvent } = createHandlersHarness({
      state: {
        currentSessionKey: "agent:main:main",
        activeChatRunId: null,
      },
    });

    handleChatEvent({
      runId: "run-alias",
      sessionKey: "main",
      state: "delta",
      message: { content: "hello" },
    });

    (expect* state.activeChatRunId).is("run-alias");
    (expect* chatLog.updateAssistant).toHaveBeenCalledWith("hello", "run-alias");
  });

  (deftest "does not cross-match canonical session keys from different agents", () => {
    const { chatLog, handleChatEvent } = createHandlersHarness({
      state: {
        currentAgentId: "alpha",
        currentSessionKey: "agent:alpha:main",
        activeChatRunId: null,
      },
    });

    handleChatEvent({
      runId: "run-other-agent",
      sessionKey: "agent:beta:main",
      state: "delta",
      message: { content: "should be ignored" },
    });

    (expect* chatLog.updateAssistant).not.toHaveBeenCalled();
  });

  (deftest "clears run mapping when the session changes", () => {
    const { state, chatLog, tui, handleChatEvent, handleAgentEvent } = createHandlersHarness({
      state: { activeChatRunId: null },
    });

    handleChatEvent({
      runId: "run-old",
      sessionKey: state.currentSessionKey,
      state: "delta",
      message: { content: "hello" },
    });

    state.currentSessionKey = "agent:main:other";
    state.activeChatRunId = null;
    tui.requestRender.mockClear();

    handleAgentEvent({
      runId: "run-old",
      stream: "tool",
      data: { phase: "start", toolCallId: "tc2", name: "exec" },
    });

    (expect* chatLog.startTool).not.toHaveBeenCalled();
    (expect* tui.requestRender).not.toHaveBeenCalled();
  });

  (deftest "accepts tool events after chat final for the same run", () => {
    const { state, chatLog, tui, handleChatEvent, handleAgentEvent } = createHandlersHarness({
      state: { activeChatRunId: null },
    });

    handleChatEvent({
      runId: "run-final",
      sessionKey: state.currentSessionKey,
      state: "final",
      message: { content: [{ type: "text", text: "done" }] },
    });

    handleAgentEvent({
      runId: "run-final",
      stream: "tool",
      data: { phase: "start", toolCallId: "tc-final", name: "session_status" },
    });

    (expect* chatLog.startTool).toHaveBeenCalledWith("tc-final", "session_status", undefined);
    (expect* tui.requestRender).toHaveBeenCalled();
  });

  (deftest "ignores lifecycle updates for non-active runs in the same session", () => {
    const { state, tui, setActivityStatus, handleChatEvent, handleAgentEvent } =
      createHandlersHarness({
        state: { activeChatRunId: "run-active" },
      });

    handleChatEvent({
      runId: "run-other",
      sessionKey: state.currentSessionKey,
      state: "delta",
      message: { content: "hello" },
    });
    setActivityStatus.mockClear();
    tui.requestRender.mockClear();

    handleAgentEvent({
      runId: "run-other",
      stream: "lifecycle",
      data: { phase: "end" },
    });

    (expect* setActivityStatus).not.toHaveBeenCalled();
    (expect* tui.requestRender).not.toHaveBeenCalled();
  });

  (deftest "suppresses tool events when verbose is off", () => {
    const { chatLog, tui, handleAgentEvent } = createHandlersHarness({
      state: {
        activeChatRunId: "run-123",
        sessionInfo: { verboseLevel: "off" },
      },
    });

    handleAgentEvent({
      runId: "run-123",
      stream: "tool",
      data: { phase: "start", toolCallId: "tc-off", name: "session_status" },
    });

    (expect* chatLog.startTool).not.toHaveBeenCalled();
    (expect* tui.requestRender).not.toHaveBeenCalled();
  });

  (deftest "omits tool output when verbose is on (non-full)", () => {
    const { chatLog, handleAgentEvent } = createHandlersHarness({
      state: {
        activeChatRunId: "run-123",
        sessionInfo: { verboseLevel: "on" },
      },
    });

    handleAgentEvent({
      runId: "run-123",
      stream: "tool",
      data: {
        phase: "update",
        toolCallId: "tc-on",
        name: "session_status",
        partialResult: { content: [{ type: "text", text: "secret" }] },
      },
    });

    handleAgentEvent({
      runId: "run-123",
      stream: "tool",
      data: {
        phase: "result",
        toolCallId: "tc-on",
        name: "session_status",
        result: { content: [{ type: "text", text: "secret" }] },
        isError: false,
      },
    });

    (expect* chatLog.updateToolResult).toHaveBeenCalledTimes(1);
    (expect* chatLog.updateToolResult).toHaveBeenCalledWith(
      "tc-on",
      { content: [] },
      { isError: false },
    );
  });

  (deftest "refreshes history after a non-local chat final", () => {
    const { state, loadHistory, handleChatEvent } = createHandlersHarness({
      state: { activeChatRunId: null },
    });

    handleChatEvent({
      runId: "external-run",
      sessionKey: state.currentSessionKey,
      state: "final",
      message: { content: [{ type: "text", text: "done" }] },
    });

    (expect* loadHistory).toHaveBeenCalledTimes(1);
  });

  function createConcurrentRunHarness(localContent = "partial") {
    const { state, chatLog, setActivityStatus, loadHistory, handleChatEvent } =
      createHandlersHarness({
        state: { activeChatRunId: "run-active" },
      });

    handleChatEvent({
      runId: "run-active",
      sessionKey: state.currentSessionKey,
      state: "delta",
      message: { content: localContent },
    });

    return { state, chatLog, setActivityStatus, loadHistory, handleChatEvent };
  }

  (deftest "does not reload history or clear active run when another run final arrives mid-stream", () => {
    const { state, chatLog, setActivityStatus, loadHistory, handleChatEvent } =
      createConcurrentRunHarness("partial");

    loadHistory.mockClear();
    setActivityStatus.mockClear();

    handleChatEvent({
      runId: "run-other",
      sessionKey: state.currentSessionKey,
      state: "final",
      message: { content: [{ type: "text", text: "other final" }] },
    });

    (expect* loadHistory).not.toHaveBeenCalled();
    (expect* state.activeChatRunId).is("run-active");
    (expect* setActivityStatus).not.toHaveBeenCalledWith("idle");

    handleChatEvent({
      runId: "run-active",
      sessionKey: state.currentSessionKey,
      state: "delta",
      message: { content: "continued" },
    });

    (expect* chatLog.updateAssistant).toHaveBeenLastCalledWith("continued", "run-active");
  });

  (deftest "suppresses non-local empty final placeholders during concurrent runs", () => {
    const { state, chatLog, loadHistory, handleChatEvent } =
      createConcurrentRunHarness("local stream");

    loadHistory.mockClear();
    chatLog.finalizeAssistant.mockClear();
    chatLog.dropAssistant.mockClear();

    handleChatEvent({
      runId: "run-other",
      sessionKey: state.currentSessionKey,
      state: "final",
      message: { content: [] },
    });

    (expect* chatLog.finalizeAssistant).not.toHaveBeenCalledWith("(no output)", "run-other");
    (expect* chatLog.dropAssistant).toHaveBeenCalledWith("run-other");
    (expect* loadHistory).not.toHaveBeenCalled();
    (expect* state.activeChatRunId).is("run-active");
  });

  (deftest "renders final error text when chat final has no content but includes event errorMessage", () => {
    const { state, chatLog, handleChatEvent } = createHandlersHarness({
      state: { activeChatRunId: null },
    });

    handleChatEvent({
      runId: "run-error-envelope",
      sessionKey: state.currentSessionKey,
      state: "final",
      message: { content: [] },
      errorMessage: '401 {"error":{"message":"Missing scopes: model.request"}}',
    });

    (expect* chatLog.finalizeAssistant).toHaveBeenCalledTimes(1);
    const [rendered] = chatLog.finalizeAssistant.mock.calls[0] ?? [];
    (expect* String(rendered)).contains("HTTP 401");
    (expect* String(rendered)).contains("Missing scopes: model.request");
    (expect* chatLog.dropAssistant).not.toHaveBeenCalledWith("run-error-envelope");
  });

  (deftest "drops streaming assistant when chat final has no message", () => {
    const { state, chatLog, handleChatEvent } = createHandlersHarness({
      state: { activeChatRunId: null },
    });

    handleChatEvent({
      runId: "run-silent",
      sessionKey: state.currentSessionKey,
      state: "delta",
      message: { content: "hello" },
    });
    chatLog.dropAssistant.mockClear();
    chatLog.finalizeAssistant.mockClear();

    handleChatEvent({
      runId: "run-silent",
      sessionKey: state.currentSessionKey,
      state: "final",
    });

    (expect* chatLog.dropAssistant).toHaveBeenCalledWith("run-silent");
    (expect* chatLog.finalizeAssistant).not.toHaveBeenCalled();
  });

  (deftest "reloads history when a local run ends without a displayable final message", () => {
    const { state, loadHistory, noteLocalRunId, handleChatEvent } = createHandlersHarness({
      state: { activeChatRunId: "run-local-silent" },
    });

    noteLocalRunId("run-local-silent");

    handleChatEvent({
      runId: "run-local-silent",
      sessionKey: state.currentSessionKey,
      state: "final",
    });

    (expect* loadHistory).toHaveBeenCalledTimes(1);
  });
});
