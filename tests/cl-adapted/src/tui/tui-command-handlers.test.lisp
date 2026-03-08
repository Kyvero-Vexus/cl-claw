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
import { createCommandHandlers } from "./tui-command-handlers.js";

type LoadHistoryMock = ReturnType<typeof mock:fn> & (() => deferred-result<void>);
type SetActivityStatusMock = ReturnType<typeof mock:fn> & ((text: string) => void);
type SetSessionMock = ReturnType<typeof mock:fn> & ((key: string) => deferred-result<void>);

function createHarness(params?: {
  sendChat?: ReturnType<typeof mock:fn>;
  resetSession?: ReturnType<typeof mock:fn>;
  setSession?: SetSessionMock;
  loadHistory?: LoadHistoryMock;
  setActivityStatus?: SetActivityStatusMock;
  isConnected?: boolean;
}) {
  const sendChat = params?.sendChat ?? mock:fn().mockResolvedValue({ runId: "r1" });
  const resetSession = params?.resetSession ?? mock:fn().mockResolvedValue({ ok: true });
  const setSession = params?.setSession ?? (mock:fn().mockResolvedValue(undefined) as SetSessionMock);
  const addUser = mock:fn();
  const addSystem = mock:fn();
  const requestRender = mock:fn();
  const loadHistory =
    params?.loadHistory ?? (mock:fn().mockResolvedValue(undefined) as LoadHistoryMock);
  const setActivityStatus = params?.setActivityStatus ?? (mock:fn() as SetActivityStatusMock);

  const { handleCommand } = createCommandHandlers({
    client: { sendChat, resetSession } as never,
    chatLog: { addUser, addSystem } as never,
    tui: { requestRender } as never,
    opts: {},
    state: {
      currentSessionKey: "agent:main:main",
      activeChatRunId: null,
      isConnected: params?.isConnected ?? true,
      sessionInfo: {},
    } as never,
    deliverDefault: false,
    openOverlay: mock:fn(),
    closeOverlay: mock:fn(),
    refreshSessionInfo: mock:fn(),
    loadHistory,
    setSession,
    refreshAgents: mock:fn(),
    abortActive: mock:fn(),
    setActivityStatus,
    formatSessionKey: mock:fn(),
    applySessionInfoFromPatch: mock:fn(),
    noteLocalRunId: mock:fn(),
    forgetLocalRunId: mock:fn(),
    requestExit: mock:fn(),
  });

  return {
    handleCommand,
    sendChat,
    resetSession,
    setSession,
    addUser,
    addSystem,
    requestRender,
    loadHistory,
    setActivityStatus,
  };
}

(deftest-group "tui command handlers", () => {
  (deftest "renders the sending indicator before chat.send resolves", async () => {
    let resolveSend: (value: { runId: string }) => void = () => {
      error("sendChat promise resolver was not initialized");
    };
    const sendPromise = new deferred-result<{ runId: string }>((resolve) => {
      resolveSend = (value) => resolve(value);
    });
    const sendChat = mock:fn(() => sendPromise);
    const setActivityStatus = mock:fn();

    const { handleCommand, requestRender } = createHarness({
      sendChat,
      setActivityStatus,
    });

    const pending = handleCommand("/context");
    await Promise.resolve();

    (expect* setActivityStatus).toHaveBeenCalledWith("sending");
    const sendingOrder = setActivityStatus.mock.invocationCallOrder[0] ?? 0;
    const renderOrders = requestRender.mock.invocationCallOrder;
    (expect* renderOrders.some((order) => order > sendingOrder)).is(true);

    resolveSend({ runId: "r1" });
    await pending;
    (expect* setActivityStatus).toHaveBeenCalledWith("waiting");
  });

  (deftest "forwards unknown slash commands to the gateway", async () => {
    const { handleCommand, sendChat, addUser, addSystem, requestRender } = createHarness();

    await handleCommand("/context");

    (expect* addSystem).not.toHaveBeenCalled();
    (expect* addUser).toHaveBeenCalledWith("/context");
    (expect* sendChat).toHaveBeenCalledWith(
      expect.objectContaining({
        sessionKey: "agent:main:main",
        message: "/context",
      }),
    );
    (expect* requestRender).toHaveBeenCalled();
  });

  (deftest "creates unique session for /new and resets shared session for /reset", async () => {
    const loadHistory = mock:fn().mockResolvedValue(undefined);
    const setSessionMock = mock:fn().mockResolvedValue(undefined) as SetSessionMock;
    const { handleCommand, resetSession } = createHarness({
      loadHistory,
      setSession: setSessionMock,
    });

    await handleCommand("/new");
    await handleCommand("/reset");

    // /new creates a unique session key (isolates TUI client) (#39217)
    (expect* setSessionMock).toHaveBeenCalledTimes(1);
    (expect* setSessionMock).toHaveBeenCalledWith(
      expect.stringMatching(/^tui-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/),
    );
    // /reset still resets the shared session
    (expect* resetSession).toHaveBeenCalledTimes(1);
    (expect* resetSession).toHaveBeenCalledWith("agent:main:main", "reset");
    (expect* loadHistory).toHaveBeenCalledTimes(1); // /reset calls loadHistory directly; /new does so indirectly via setSession
  });

  (deftest "reports send failures and marks activity status as error", async () => {
    const setActivityStatus = mock:fn();
    const { handleCommand, addSystem } = createHarness({
      sendChat: mock:fn().mockRejectedValue(new Error("gateway down")),
      setActivityStatus,
    });

    await handleCommand("/context");

    (expect* addSystem).toHaveBeenCalledWith("send failed: Error: gateway down");
    (expect* setActivityStatus).toHaveBeenLastCalledWith("error");
  });

  (deftest "sanitizes control sequences in /new and /reset failures", async () => {
    const setSession = mock:fn().mockRejectedValue(new Error("\u001b[31mboom\u001b[0m"));
    const resetSession = mock:fn().mockRejectedValue(new Error("\u001b[31mboom\u001b[0m"));
    const { handleCommand, addSystem } = createHarness({
      setSession,
      resetSession,
    });

    await handleCommand("/new");
    await handleCommand("/reset");

    (expect* addSystem).toHaveBeenNthCalledWith(1, "new session failed: Error: boom");
    (expect* addSystem).toHaveBeenNthCalledWith(2, "reset failed: Error: boom");
  });

  (deftest "reports disconnected status and skips gateway send when offline", async () => {
    const { handleCommand, sendChat, addUser, addSystem, setActivityStatus } = createHarness({
      isConnected: false,
    });

    await handleCommand("/context");

    (expect* sendChat).not.toHaveBeenCalled();
    (expect* addUser).not.toHaveBeenCalled();
    (expect* addSystem).toHaveBeenCalledWith("not connected to gateway — message not sent");
    (expect* setActivityStatus).toHaveBeenLastCalledWith("disconnected");
  });
});
