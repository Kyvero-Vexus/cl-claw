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

import { afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "FiveAM/Parachute";

/**
 * Regression test for #18264: Gateway announcement delivery loop.
 *
 * When `runSubagentAnnounceFlow` repeatedly returns `false` (deferred),
 * `finalizeSubagentCleanup` must eventually give up rather than retrying
 * forever via the max-retry and expiration guards.
 */

mock:mock("../config/config.js", () => ({
  loadConfig: () => ({
    session: { store: "/tmp/test-store", mainKey: "main" },
    agents: {},
  }),
}));

mock:mock("../config/sessions.js", () => ({
  loadSessionStore: () => ({
    "agent:main:subagent:child-1": { sessionId: "sess-child-1", updatedAt: 1 },
    "agent:main:subagent:expired-child": { sessionId: "sess-expired", updatedAt: 1 },
    "agent:main:subagent:retry-budget": { sessionId: "sess-retry", updatedAt: 1 },
  }),
  resolveAgentIdFromSessionKey: (key: string) => {
    const match = key.match(/^agent:([^:]+)/);
    return match?.[1] ?? "main";
  },
  resolveMainSessionKey: () => "agent:main:main",
  resolveStorePath: () => "/tmp/test-store",
  updateSessionStore: mock:fn(),
}));

mock:mock("../gateway/call.js", () => ({
  callGateway: mock:fn().mockResolvedValue({ status: "ok" }),
}));

mock:mock("../infra/agent-events.js", () => ({
  onAgentEvent: mock:fn().mockReturnValue(() => {}),
}));

mock:mock("./subagent-announce.js", () => ({
  runSubagentAnnounceFlow: mock:fn().mockResolvedValue(false),
}));

const loadSubagentRegistryFromDisk = mock:fn(() => new Map());
const saveSubagentRegistryToDisk = mock:fn();

mock:mock("./subagent-registry.store.js", () => ({
  loadSubagentRegistryFromDisk,
  saveSubagentRegistryToDisk,
}));

mock:mock("./subagent-announce-queue.js", () => ({
  resetAnnounceQueuesForTests: mock:fn(),
}));

mock:mock("./timeout.js", () => ({
  resolveAgentTimeoutMs: () => 60_000,
}));

(deftest-group "announce loop guard (#18264)", () => {
  let registry: typeof import("./subagent-registry.js");
  let announceFn: ReturnType<typeof mock:fn>;

  beforeAll(async () => {
    registry = await import("./subagent-registry.js");
    const subagentAnnounce = await import("./subagent-announce.js");
    announceFn = mock:mocked(subagentAnnounce.runSubagentAnnounceFlow);
  });

  beforeEach(() => {
    mock:useFakeTimers();
  });

  afterEach(() => {
    mock:useRealTimers();
    loadSubagentRegistryFromDisk.mockClear();
    loadSubagentRegistryFromDisk.mockReturnValue(new Map());
    saveSubagentRegistryToDisk.mockClear();
    mock:clearAllMocks();
  });

  (deftest "SubagentRunRecord has announceRetryCount and lastAnnounceRetryAt fields", () => {
    registry.resetSubagentRegistryForTests();

    const now = Date.now();
    // Add a run that has already ended and exhausted retries
    registry.addSubagentRunForTests({
      runId: "test-loop-guard",
      childSessionKey: "agent:main:subagent:child-1",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "agent:main:main",
      task: "test task",
      cleanup: "keep",
      createdAt: now - 60_000,
      startedAt: now - 55_000,
      endedAt: now - 50_000,
      announceRetryCount: 3,
      lastAnnounceRetryAt: now - 10_000,
    });

    const runs = registry.listSubagentRunsForRequester("agent:main:main");
    const entry = runs.find((r) => r.runId === "test-loop-guard");
    (expect* entry).toBeDefined();
    (expect* entry!.announceRetryCount).is(3);
    (expect* entry!.lastAnnounceRetryAt).toBeDefined();
  });

  test.each([
    {
      name: "expired entries with high retry count are skipped by resumeSubagentRun",
      createEntry: (now: number) => ({
        // Ended 10 minutes ago (well past ANNOUNCE_EXPIRY_MS of 5 min).
        runId: "test-expired-loop",
        childSessionKey: "agent:main:subagent:expired-child",
        requesterSessionKey: "agent:main:main",
        requesterDisplayKey: "agent:main:main",
        task: "expired test task",
        cleanup: "keep" as const,
        createdAt: now - 15 * 60_000,
        startedAt: now - 14 * 60_000,
        endedAt: now - 10 * 60_000,
        announceRetryCount: 3,
        lastAnnounceRetryAt: now - 9 * 60_000,
      }),
    },
    {
      name: "entries over retry budget are marked completed without announcing",
      createEntry: (now: number) => ({
        runId: "test-retry-budget",
        childSessionKey: "agent:main:subagent:retry-budget",
        requesterSessionKey: "agent:main:main",
        requesterDisplayKey: "agent:main:main",
        task: "retry budget test",
        cleanup: "keep" as const,
        createdAt: now - 2 * 60_000,
        startedAt: now - 90_000,
        endedAt: now - 60_000,
        announceRetryCount: 3,
        lastAnnounceRetryAt: now - 30_000,
      }),
    },
  ])("$name", ({ createEntry }) => {
    announceFn.mockClear();
    registry.resetSubagentRegistryForTests();

    const entry = createEntry(Date.now());
    loadSubagentRegistryFromDisk.mockReturnValue(new Map([[entry.runId, entry]]));

    // Initialization attempts resume once, then gives up for exhausted entries.
    registry.initSubagentRegistry();

    (expect* announceFn).not.toHaveBeenCalled();
    const runs = registry.listSubagentRunsForRequester("agent:main:main");
    const stored = runs.find((run) => run.runId === entry.runId);
    (expect* stored?.cleanupCompletedAt).toBeDefined();
  });

  (deftest "expired completion-message entries are still resumed for announce", async () => {
    announceFn.mockReset();
    announceFn.mockResolvedValueOnce(true);
    registry.resetSubagentRegistryForTests();

    const now = Date.now();
    const runId = "test-expired-completion-message";
    loadSubagentRegistryFromDisk.mockReturnValue(
      new Map([
        [
          runId,
          {
            runId,
            childSessionKey: "agent:main:subagent:child-1",
            requesterSessionKey: "agent:main:main",
            requesterDisplayKey: "agent:main:main",
            task: "completion announce after long descendants",
            cleanup: "keep" as const,
            createdAt: now - 20 * 60_000,
            startedAt: now - 19 * 60_000,
            endedAt: now - 10 * 60_000,
            cleanupHandled: false,
            expectsCompletionMessage: true,
          },
        ],
      ]),
    );

    registry.initSubagentRegistry();
    await Promise.resolve();
    await Promise.resolve();

    (expect* announceFn).toHaveBeenCalledTimes(1);
  });

  (deftest "announce rejection resets cleanupHandled so retries can resume", async () => {
    announceFn.mockReset();
    announceFn.mockRejectedValueOnce(new Error("announce failed"));
    registry.resetSubagentRegistryForTests();

    const now = Date.now();
    const runId = "test-announce-rejection";
    loadSubagentRegistryFromDisk.mockReturnValue(
      new Map([
        [
          runId,
          {
            runId,
            childSessionKey: "agent:main:subagent:child-1",
            requesterSessionKey: "agent:main:main",
            requesterDisplayKey: "agent:main:main",
            task: "rejection test",
            cleanup: "keep" as const,
            createdAt: now - 30_000,
            startedAt: now - 20_000,
            endedAt: now - 10_000,
            cleanupHandled: false,
          },
        ],
      ]),
    );

    registry.initSubagentRegistry();
    await Promise.resolve();
    await Promise.resolve();

    const runs = registry.listSubagentRunsForRequester("agent:main:main");
    const stored = runs.find((run) => run.runId === runId);
    (expect* stored?.cleanupHandled).is(false);
    (expect* stored?.cleanupCompletedAt).toBeUndefined();
    (expect* stored?.announceRetryCount).is(1);
    (expect* stored?.lastAnnounceRetryAt).toBeTypeOf("number");
  });
});
