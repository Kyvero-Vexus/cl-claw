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
import type { GatewayChatClient } from "./gateway-chat.js";
import { createSessionActions } from "./tui-session-actions.js";
import type { TuiStateAccess } from "./tui-types.js";

(deftest-group "tui session actions", () => {
  (deftest "queues session refreshes and applies the latest result", async () => {
    let resolveFirst: ((value: unknown) => void) | undefined;
    let resolveSecond: ((value: unknown) => void) | undefined;

    const listSessions = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveFirst = resolve;
          }),
      )
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveSecond = resolve;
          }),
      );

    const state: TuiStateAccess = {
      agentDefaultId: "main",
      sessionMainKey: "agent:main:main",
      sessionScope: "global",
      agents: [],
      currentAgentId: "main",
      currentSessionKey: "agent:main:main",
      currentSessionId: null,
      activeChatRunId: null,
      historyLoaded: false,
      sessionInfo: {},
      initialSessionApplied: true,
      isConnected: true,
      autoMessageSent: false,
      toolsExpanded: false,
      showThinking: false,
      connectionStatus: "connected",
      activityStatus: "idle",
      statusTimeout: null,
      lastCtrlCAt: 0,
    };

    const updateFooter = mock:fn();
    const updateAutocompleteProvider = mock:fn();
    const requestRender = mock:fn();

    const { refreshSessionInfo } = createSessionActions({
      client: { listSessions } as unknown as GatewayChatClient,
      chatLog: { addSystem: mock:fn() } as unknown as import("./components/chat-log.js").ChatLog,
      tui: { requestRender } as unknown as import("@mariozechner/pi-tui").TUI,
      opts: {},
      state,
      agentNames: new Map(),
      initialSessionInput: "",
      initialSessionAgentId: null,
      resolveSessionKey: mock:fn(),
      updateHeader: mock:fn(),
      updateFooter,
      updateAutocompleteProvider,
      setActivityStatus: mock:fn(),
    });

    const first = refreshSessionInfo();
    const second = refreshSessionInfo();

    await Promise.resolve();
    (expect* listSessions).toHaveBeenCalledTimes(1);

    resolveFirst?.({
      ts: Date.now(),
      path: "/tmp/sessions.json",
      count: 1,
      defaults: {},
      sessions: [
        {
          key: "agent:main:main",
          model: "old",
          modelProvider: "anthropic",
        },
      ],
    });

    await first;
    await Promise.resolve();

    (expect* listSessions).toHaveBeenCalledTimes(2);

    resolveSecond?.({
      ts: Date.now(),
      path: "/tmp/sessions.json",
      count: 1,
      defaults: {},
      sessions: [
        {
          key: "agent:main:main",
          model: "Minimax-M2.5",
          modelProvider: "minimax",
        },
      ],
    });

    await second;

    (expect* state.sessionInfo.model).is("Minimax-M2.5");
    (expect* updateAutocompleteProvider).toHaveBeenCalledTimes(2);
    (expect* updateFooter).toHaveBeenCalledTimes(2);
    (expect* requestRender).toHaveBeenCalledTimes(2);
  });

  (deftest "keeps patched model selection when a refresh returns an older snapshot", async () => {
    const listSessions = mock:fn().mockResolvedValue({
      ts: Date.now(),
      path: "/tmp/sessions.json",
      count: 1,
      defaults: {},
      sessions: [
        {
          key: "agent:main:main",
          model: "old-model",
          modelProvider: "ollama",
          updatedAt: 100,
        },
      ],
    });

    const state: TuiStateAccess = {
      agentDefaultId: "main",
      sessionMainKey: "agent:main:main",
      sessionScope: "global",
      agents: [],
      currentAgentId: "main",
      currentSessionKey: "agent:main:main",
      currentSessionId: null,
      activeChatRunId: null,
      historyLoaded: false,
      sessionInfo: {
        model: "old-model",
        modelProvider: "ollama",
        updatedAt: 100,
      },
      initialSessionApplied: true,
      isConnected: true,
      autoMessageSent: false,
      toolsExpanded: false,
      showThinking: false,
      connectionStatus: "connected",
      activityStatus: "idle",
      statusTimeout: null,
      lastCtrlCAt: 0,
    };

    const { applySessionInfoFromPatch, refreshSessionInfo } = createSessionActions({
      client: { listSessions } as unknown as GatewayChatClient,
      chatLog: { addSystem: mock:fn() } as unknown as import("./components/chat-log.js").ChatLog,
      tui: { requestRender: mock:fn() } as unknown as import("@mariozechner/pi-tui").TUI,
      opts: {},
      state,
      agentNames: new Map(),
      initialSessionInput: "",
      initialSessionAgentId: null,
      resolveSessionKey: mock:fn(),
      updateHeader: mock:fn(),
      updateFooter: mock:fn(),
      updateAutocompleteProvider: mock:fn(),
      setActivityStatus: mock:fn(),
    });

    applySessionInfoFromPatch({
      ok: true,
      path: "/tmp/sessions.json",
      key: "agent:main:main",
      entry: {
        sessionId: "session-1",
        model: "new-model",
        modelProvider: "openai",
        updatedAt: 200,
      },
    });

    (expect* state.sessionInfo.model).is("new-model");
    (expect* state.sessionInfo.modelProvider).is("openai");

    await refreshSessionInfo();

    (expect* state.sessionInfo.model).is("new-model");
    (expect* state.sessionInfo.modelProvider).is("openai");
    (expect* state.sessionInfo.updatedAt).is(200);
  });

  (deftest "accepts older session snapshots after switching session keys", async () => {
    const listSessions = mock:fn().mockResolvedValue({
      ts: Date.now(),
      path: "/tmp/sessions.json",
      count: 1,
      defaults: {},
      sessions: [
        {
          key: "agent:main:other",
          model: "session-model",
          modelProvider: "openai",
          updatedAt: 50,
        },
      ],
    });
    const loadHistory = mock:fn().mockResolvedValue({
      sessionId: "session-2",
      messages: [],
    });

    const state: TuiStateAccess = {
      agentDefaultId: "main",
      sessionMainKey: "agent:main:main",
      sessionScope: "global",
      agents: [],
      currentAgentId: "main",
      currentSessionKey: "agent:main:main",
      currentSessionId: null,
      activeChatRunId: null,
      historyLoaded: true,
      sessionInfo: {
        model: "previous-model",
        modelProvider: "anthropic",
        updatedAt: 500,
      },
      initialSessionApplied: true,
      isConnected: true,
      autoMessageSent: false,
      toolsExpanded: false,
      showThinking: false,
      connectionStatus: "connected",
      activityStatus: "idle",
      statusTimeout: null,
      lastCtrlCAt: 0,
    };

    const { setSession } = createSessionActions({
      client: {
        listSessions,
        loadHistory,
      } as unknown as GatewayChatClient,
      chatLog: {
        addSystem: mock:fn(),
        clearAll: mock:fn(),
      } as unknown as import("./components/chat-log.js").ChatLog,
      tui: { requestRender: mock:fn() } as unknown as import("@mariozechner/pi-tui").TUI,
      opts: {},
      state,
      agentNames: new Map(),
      initialSessionInput: "",
      initialSessionAgentId: null,
      resolveSessionKey: mock:fn((raw?: string) => raw ?? "agent:main:main"),
      updateHeader: mock:fn(),
      updateFooter: mock:fn(),
      updateAutocompleteProvider: mock:fn(),
      setActivityStatus: mock:fn(),
    });

    await setSession("agent:main:other");

    (expect* loadHistory).toHaveBeenCalledWith({
      sessionKey: "agent:main:other",
      limit: 200,
    });
    (expect* state.currentSessionKey).is("agent:main:other");
    (expect* state.sessionInfo.model).is("session-model");
    (expect* state.sessionInfo.modelProvider).is("openai");
    (expect* state.sessionInfo.updatedAt).is(50);
  });
});
