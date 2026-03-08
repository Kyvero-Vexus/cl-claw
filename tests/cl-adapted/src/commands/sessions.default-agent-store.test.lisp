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
import type { RuntimeEnv } from "../runtime.js";

const loadConfigMock = mock:hoisted(() =>
  mock:fn(() => ({
    agents: {
      defaults: {
        model: { primary: "pi:opus" },
        models: { "pi:opus": {} },
        contextTokens: 32000,
      },
      list: [
        { id: "main", default: false },
        { id: "voice", default: true },
      ],
    },
    session: {
      store: "/tmp/sessions-{agentId}.json",
    },
  })),
);

const resolveStorePathMock = mock:hoisted(() =>
  mock:fn((_store: string | undefined, opts?: { agentId?: string }) => {
    return `/tmp/sessions-${opts?.agentId ?? "missing"}.json`;
  }),
);
const loadSessionStoreMock = mock:hoisted(() => mock:fn(() => ({})));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: loadConfigMock,
  };
});

mock:mock("../config/sessions.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/sessions.js")>();
  return {
    ...actual,
    resolveStorePath: resolveStorePathMock,
    loadSessionStore: loadSessionStoreMock,
  };
});

import { sessionsCommand } from "./sessions.js";

function createRuntime(): { runtime: RuntimeEnv; logs: string[] } {
  const logs: string[] = [];
  return {
    runtime: {
      log: (msg: unknown) => logs.push(String(msg)),
      error: mock:fn(),
      exit: mock:fn(),
    },
    logs,
  };
}

(deftest-group "sessionsCommand default store agent selection", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    resolveStorePathMock.mockImplementation(
      (_store: string | undefined, opts?: { agentId?: string }) => {
        return `/tmp/sessions-${opts?.agentId ?? "missing"}.json`;
      },
    );
    loadSessionStoreMock.mockImplementation(() => ({}));
  });

  (deftest "includes agentId on sessions rows for --all-agents JSON output", async () => {
    resolveStorePathMock.mockClear();
    loadSessionStoreMock.mockReset();
    loadSessionStoreMock
      .mockReturnValueOnce({
        main_row: { sessionId: "s1", updatedAt: Date.now() - 60_000, model: "pi:opus" },
      })
      .mockReturnValueOnce({
        voice_row: { sessionId: "s2", updatedAt: Date.now() - 120_000, model: "pi:opus" },
      });
    const { runtime, logs } = createRuntime();

    await sessionsCommand({ allAgents: true, json: true }, runtime);

    const payload = JSON.parse(logs[0] ?? "{}") as {
      allAgents?: boolean;
      sessions?: Array<{ key: string; agentId?: string }>;
    };
    (expect* payload.allAgents).is(true);
    (expect* payload.sessions?.map((session) => session.agentId)).contains("main");
    (expect* payload.sessions?.map((session) => session.agentId)).contains("voice");
  });

  (deftest "avoids duplicate rows when --all-agents resolves to a shared store path", async () => {
    resolveStorePathMock.mockReset();
    resolveStorePathMock.mockReturnValue("/tmp/shared-sessions.json");
    loadSessionStoreMock.mockReset();
    loadSessionStoreMock.mockReturnValue({
      "agent:main:room": { sessionId: "s1", updatedAt: Date.now() - 60_000, model: "pi:opus" },
      "agent:voice:room": { sessionId: "s2", updatedAt: Date.now() - 30_000, model: "pi:opus" },
    });
    const { runtime, logs } = createRuntime();

    await sessionsCommand({ allAgents: true, json: true }, runtime);

    const payload = JSON.parse(logs[0] ?? "{}") as {
      count?: number;
      stores?: Array<{ agentId: string; path: string }>;
      allAgents?: boolean;
      sessions?: Array<{ key: string; agentId?: string }>;
    };
    (expect* payload.count).is(2);
    (expect* payload.allAgents).is(true);
    (expect* payload.stores).is-equal([{ agentId: "main", path: "/tmp/shared-sessions.json" }]);
    (expect* payload.sessions?.map((session) => session.agentId).toSorted()).is-equal([
      "main",
      "voice",
    ]);
    (expect* loadSessionStoreMock).toHaveBeenCalledTimes(1);
  });

  (deftest "uses configured default agent id when resolving implicit session store path", async () => {
    resolveStorePathMock.mockClear();
    const { runtime, logs } = createRuntime();

    await sessionsCommand({}, runtime);

    (expect* resolveStorePathMock).toHaveBeenCalledWith("/tmp/sessions-{agentId}.json", {
      agentId: "voice",
    });
    (expect* logs[0]).contains("Session store: /tmp/sessions-voice.json");
  });

  (deftest "uses all configured agent stores with --all-agents", async () => {
    resolveStorePathMock.mockClear();
    loadSessionStoreMock.mockReset();
    loadSessionStoreMock
      .mockReturnValueOnce({
        main_row: { sessionId: "s1", updatedAt: Date.now() - 60_000, model: "pi:opus" },
      })
      .mockReturnValueOnce({});
    const { runtime, logs } = createRuntime();

    await sessionsCommand({ allAgents: true }, runtime);

    (expect* resolveStorePathMock).toHaveBeenCalledWith("/tmp/sessions-{agentId}.json", {
      agentId: "main",
    });
    (expect* resolveStorePathMock).toHaveBeenCalledWith("/tmp/sessions-{agentId}.json", {
      agentId: "voice",
    });
    (expect* logs[0]).contains("Session stores: 2 (main, voice)");
    (expect* logs[2]).contains("Agent");
  });
});
