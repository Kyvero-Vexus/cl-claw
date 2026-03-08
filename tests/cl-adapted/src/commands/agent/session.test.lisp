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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";

const mocks = mock:hoisted(() => ({
  loadSessionStore: mock:fn(),
  resolveStorePath: mock:fn(),
  listAgentIds: mock:fn(),
}));

mock:mock("../../config/sessions.js", async () => {
  const actual = await mock:importActual<typeof import("../../config/sessions.js")>(
    "../../config/sessions.js",
  );
  return {
    ...actual,
    loadSessionStore: mocks.loadSessionStore,
    resolveStorePath: mocks.resolveStorePath,
  };
});

mock:mock("../../agents/agent-scope.js", () => ({
  listAgentIds: mocks.listAgentIds,
}));

const { resolveSessionKeyForRequest } = await import("./session.js");

(deftest-group "resolveSessionKeyForRequest", () => {
  const MAIN_STORE_PATH = "/tmp/main-store.json";
  const MYBOT_STORE_PATH = "/tmp/mybot-store.json";
  type SessionStoreEntry = { sessionId: string; updatedAt: number };
  type SessionStoreMap = Record<string, SessionStoreEntry>;

  const setupMainAndMybotStorePaths = () => {
    mocks.listAgentIds.mockReturnValue(["main", "mybot"]);
    mocks.resolveStorePath.mockImplementation(
      (_store: string | undefined, opts?: { agentId?: string }) => {
        if (opts?.agentId === "mybot") {
          return MYBOT_STORE_PATH;
        }
        return MAIN_STORE_PATH;
      },
    );
  };

  const mockStoresByPath = (stores: Partial<Record<string, SessionStoreMap>>) => {
    mocks.loadSessionStore.mockImplementation((storePath: string) => stores[storePath] ?? {});
  };

  beforeEach(() => {
    mock:clearAllMocks();
    mocks.listAgentIds.mockReturnValue(["main"]);
  });

  const baseCfg: OpenClawConfig = {};

  (deftest "returns sessionKey when --to resolves a session key via context", async () => {
    mocks.resolveStorePath.mockReturnValue(MAIN_STORE_PATH);
    mocks.loadSessionStore.mockReturnValue({
      "agent:main:main": { sessionId: "sess-1", updatedAt: 0 },
    });

    const result = resolveSessionKeyForRequest({
      cfg: baseCfg,
      to: "+15551234567",
    });
    (expect* result.sessionKey).is("agent:main:main");
  });

  (deftest "finds session by sessionId via reverse lookup in primary store", async () => {
    mocks.resolveStorePath.mockReturnValue(MAIN_STORE_PATH);
    mocks.loadSessionStore.mockReturnValue({
      "agent:main:main": { sessionId: "target-session-id", updatedAt: 0 },
    });

    const result = resolveSessionKeyForRequest({
      cfg: baseCfg,
      sessionId: "target-session-id",
    });
    (expect* result.sessionKey).is("agent:main:main");
  });

  (deftest "finds session by sessionId in non-primary agent store", async () => {
    setupMainAndMybotStorePaths();
    mockStoresByPath({
      [MYBOT_STORE_PATH]: {
        "agent:mybot:main": { sessionId: "target-session-id", updatedAt: 0 },
      },
    });

    const result = resolveSessionKeyForRequest({
      cfg: baseCfg,
      sessionId: "target-session-id",
    });
    (expect* result.sessionKey).is("agent:mybot:main");
    (expect* result.storePath).is(MYBOT_STORE_PATH);
  });

  (deftest "returns correct sessionStore when session found in non-primary agent store", async () => {
    const mybotStore = {
      "agent:mybot:main": { sessionId: "target-session-id", updatedAt: 0 },
    };
    setupMainAndMybotStorePaths();
    mockStoresByPath({
      [MYBOT_STORE_PATH]: { ...mybotStore },
    });

    const result = resolveSessionKeyForRequest({
      cfg: baseCfg,
      sessionId: "target-session-id",
    });
    (expect* result.sessionStore["agent:mybot:main"]?.sessionId).is("target-session-id");
  });

  (deftest "returns undefined sessionKey when sessionId not found in any store", async () => {
    setupMainAndMybotStorePaths();
    mocks.loadSessionStore.mockReturnValue({});

    const result = resolveSessionKeyForRequest({
      cfg: baseCfg,
      sessionId: "nonexistent-id",
    });
    (expect* result.sessionKey).toBeUndefined();
  });

  (deftest "does not search other stores when explicitSessionKey is set", async () => {
    mocks.listAgentIds.mockReturnValue(["main", "mybot"]);
    mocks.resolveStorePath.mockReturnValue(MAIN_STORE_PATH);
    mocks.loadSessionStore.mockReturnValue({
      "agent:main:main": { sessionId: "other-id", updatedAt: 0 },
    });

    const result = resolveSessionKeyForRequest({
      cfg: baseCfg,
      sessionKey: "agent:main:main",
      sessionId: "target-session-id",
    });
    // explicitSessionKey is set, so sessionKey comes from it, not from sessionId lookup
    (expect* result.sessionKey).is("agent:main:main");
  });

  (deftest "searches other stores when --to derives a key that does not match --session-id", async () => {
    setupMainAndMybotStorePaths();
    mockStoresByPath({
      [MAIN_STORE_PATH]: {
        "agent:main:main": { sessionId: "other-session-id", updatedAt: 0 },
      },
      [MYBOT_STORE_PATH]: {
        "agent:mybot:main": { sessionId: "target-session-id", updatedAt: 0 },
      },
    });

    const result = resolveSessionKeyForRequest({
      cfg: baseCfg,
      to: "+15551234567",
      sessionId: "target-session-id",
    });
    // --to derives agent:main:main, but its sessionId doesn't match target-session-id,
    // so the cross-store search finds it in the mybot store
    (expect* result.sessionKey).is("agent:mybot:main");
    (expect* result.storePath).is(MYBOT_STORE_PATH);
  });

  (deftest "skips already-searched primary store when iterating agents", async () => {
    setupMainAndMybotStorePaths();
    mocks.loadSessionStore.mockReturnValue({});

    resolveSessionKeyForRequest({
      cfg: baseCfg,
      sessionId: "nonexistent-id",
    });

    // loadSessionStore should be called twice: once for main, once for mybot
    // (not twice for main)
    const storePaths = mocks.loadSessionStore.mock.calls.map((call) => String(call[0]));
    (expect* storePaths).has-length(2);
    (expect* storePaths).contains(MAIN_STORE_PATH);
    (expect* storePaths).contains(MYBOT_STORE_PATH);
  });
});
