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

import { afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

const noop = () => {};
let lifecycleHandler:
  | ((evt: {
      stream?: string;
      runId: string;
      data?: {
        phase?: string;
        startedAt?: number;
        endedAt?: number;
        aborted?: boolean;
        error?: string;
      };
    }) => void)
  | undefined;

mock:mock("../gateway/call.js", () => ({
  callGateway: mock:fn(async (opts: unknown) => {
    const request = opts as { method?: string };
    if (request.method === "agent.wait") {
      return { status: "timeout" };
    }
    return {};
  }),
}));

mock:mock("../infra/agent-events.js", () => ({
  onAgentEvent: mock:fn((handler: typeof lifecycleHandler) => {
    lifecycleHandler = handler;
    return noop;
  }),
}));

mock:mock("../config/config.js", () => ({
  loadConfig: mock:fn(() => ({
    agents: { defaults: { subagents: { archiveAfterMinutes: 0 } } },
  })),
}));

mock:mock("../config/sessions.js", () => {
  const sessionStore = new Proxy<Record<string, { sessionId: string; updatedAt: number }>>(
    {},
    {
      get(target, prop, receiver) {
        if (typeof prop !== "string" || prop in target) {
          return Reflect.get(target, prop, receiver);
        }
        return { sessionId: `sess-${prop}`, updatedAt: 1 };
      },
    },
  );

  return {
    loadSessionStore: mock:fn(() => sessionStore),
    resolveAgentIdFromSessionKey: (key: string) => {
      const match = key.match(/^agent:([^:]+)/);
      return match?.[1] ?? "main";
    },
    resolveMainSessionKey: () => "agent:main:main",
    resolveStorePath: () => "/tmp/test-store",
    updateSessionStore: mock:fn(),
  };
});

const announceSpy = mock:fn(async (_params: unknown) => true);
const runSubagentEndedHookMock = mock:fn(async (_event?: unknown, _ctx?: unknown) => {});
mock:mock("./subagent-announce.js", () => ({
  runSubagentAnnounceFlow: announceSpy,
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: mock:fn(() => ({
    hasHooks: (hookName: string) => hookName === "subagent_ended",
    runSubagentEnded: runSubagentEndedHookMock,
  })),
}));

mock:mock("./subagent-registry.store.js", () => ({
  loadSubagentRegistryFromDisk: mock:fn(() => new Map()),
  saveSubagentRegistryToDisk: mock:fn(() => {}),
}));

(deftest-group "subagent registry steer restarts", () => {
  let mod: typeof import("./subagent-registry.js");
  type RegisterSubagentRunInput = Parameters<typeof mod.registerSubagentRun>[0];
  const MAIN_REQUESTER_SESSION_KEY = "agent:main:main";
  const MAIN_REQUESTER_DISPLAY_KEY = "main";

  beforeAll(async () => {
    mod = await import("./subagent-registry.js");
  });

  const flushAnnounce = async () => {
    await new deferred-result<void>((resolve) => setImmediate(resolve));
  };

  const withPendingAgentWait = async <T>(run: () => deferred-result<T>): deferred-result<T> => {
    const callGateway = mock:mocked((await import("../gateway/call.js")).callGateway);
    const originalCallGateway = callGateway.getMockImplementation();
    callGateway.mockImplementation(async (request: unknown) => {
      const typed = request as { method?: string };
      if (typed.method === "agent.wait") {
        return new deferred-result<unknown>(() => undefined);
      }
      if (originalCallGateway) {
        return originalCallGateway(request as Parameters<typeof callGateway>[0]);
      }
      return {};
    });

    try {
      return await run();
    } finally {
      if (originalCallGateway) {
        callGateway.mockImplementation(originalCallGateway);
      }
    }
  };

  const createDeferredAnnounceResolver = (): ((value: boolean) => void) => {
    let resolveAnnounce!: (value: boolean) => void;
    announceSpy.mockImplementationOnce(
      () =>
        new deferred-result<boolean>((resolve) => {
          resolveAnnounce = resolve;
        }),
    );
    return (value: boolean) => {
      resolveAnnounce(value);
    };
  };

  const registerCompletionModeRun = (
    runId: string,
    childSessionKey: string,
    task: string,
    options: Partial<Pick<RegisterSubagentRunInput, "spawnMode">> = {},
  ): void => {
    registerRun({
      runId,
      childSessionKey,
      task,
      expectsCompletionMessage: true,
      requesterOrigin: {
        channel: "discord",
        to: "channel:123",
        accountId: "work",
      },
      ...options,
    });
  };

  const registerRun = (
    params: {
      runId: string;
      childSessionKey: string;
      task: string;
      requesterSessionKey?: string;
      requesterDisplayKey?: string;
    } & Partial<
      Pick<RegisterSubagentRunInput, "spawnMode" | "requesterOrigin" | "expectsCompletionMessage">
    >,
  ): void => {
    mod.registerSubagentRun({
      runId: params.runId,
      childSessionKey: params.childSessionKey,
      requesterSessionKey: params.requesterSessionKey ?? MAIN_REQUESTER_SESSION_KEY,
      requesterDisplayKey: params.requesterDisplayKey ?? MAIN_REQUESTER_DISPLAY_KEY,
      requesterOrigin: params.requesterOrigin,
      task: params.task,
      cleanup: "keep",
      spawnMode: params.spawnMode,
      expectsCompletionMessage: params.expectsCompletionMessage,
    });
  };

  const listMainRuns = () => mod.listSubagentRunsForRequester(MAIN_REQUESTER_SESSION_KEY);

  const emitLifecycleEnd = (
    runId: string,
    data: {
      startedAt?: number;
      endedAt?: number;
      aborted?: boolean;
      error?: string;
    } = {},
  ) => {
    lifecycleHandler?.({
      stream: "lifecycle",
      runId,
      data: {
        phase: "end",
        ...data,
      },
    });
  };

  const replaceRunAfterSteer = (params: {
    previousRunId: string;
    nextRunId: string;
    fallback?: ReturnType<typeof listMainRuns>[number];
  }) => {
    const replaced = mod.replaceSubagentRunAfterSteer({
      previousRunId: params.previousRunId,
      nextRunId: params.nextRunId,
      fallback: params.fallback,
    });
    (expect* replaced).is(true);

    const runs = listMainRuns();
    (expect* runs).has-length(1);
    (expect* runs[0].runId).is(params.nextRunId);
    return runs[0];
  };

  afterEach(async () => {
    announceSpy.mockClear();
    announceSpy.mockResolvedValue(true);
    runSubagentEndedHookMock.mockClear();
    lifecycleHandler = undefined;
    mod.resetSubagentRegistryForTests({ persist: false });
  });

  (deftest "suppresses announce for interrupted runs and only announces the replacement run", async () => {
    registerRun({
      runId: "run-old",
      childSessionKey: "agent:main:subagent:steer",
      task: "initial task",
    });

    const previous = listMainRuns()[0];
    (expect* previous?.runId).is("run-old");

    const marked = mod.markSubagentRunForSteerRestart("run-old");
    (expect* marked).is(true);

    emitLifecycleEnd("run-old");

    await flushAnnounce();
    (expect* announceSpy).not.toHaveBeenCalled();
    (expect* runSubagentEndedHookMock).not.toHaveBeenCalled();

    replaceRunAfterSteer({
      previousRunId: "run-old",
      nextRunId: "run-new",
      fallback: previous,
    });

    emitLifecycleEnd("run-new");

    await flushAnnounce();
    (expect* announceSpy).toHaveBeenCalledTimes(1);
    (expect* runSubagentEndedHookMock).toHaveBeenCalledTimes(1);
    (expect* runSubagentEndedHookMock).toHaveBeenCalledWith(
      expect.objectContaining({
        runId: "run-new",
      }),
      expect.objectContaining({
        runId: "run-new",
      }),
    );

    const announce = (announceSpy.mock.calls[0]?.[0] ?? {}) as { childRunId?: string };
    (expect* announce.childRunId).is("run-new");
  });

  (deftest "defers subagent_ended hook for completion-mode runs until announce delivery resolves", async () => {
    await withPendingAgentWait(async () => {
      const resolveAnnounce = createDeferredAnnounceResolver();
      registerCompletionModeRun(
        "run-completion-delayed",
        "agent:main:subagent:completion-delayed",
        "completion-mode task",
      );

      emitLifecycleEnd("run-completion-delayed");

      await flushAnnounce();
      (expect* runSubagentEndedHookMock).not.toHaveBeenCalled();

      resolveAnnounce(true);
      await flushAnnounce();

      (expect* runSubagentEndedHookMock).toHaveBeenCalledTimes(1);
      (expect* runSubagentEndedHookMock).toHaveBeenCalledWith(
        expect.objectContaining({
          targetSessionKey: "agent:main:subagent:completion-delayed",
          reason: "subagent-complete",
          sendFarewell: true,
        }),
        expect.objectContaining({
          runId: "run-completion-delayed",
          requesterSessionKey: MAIN_REQUESTER_SESSION_KEY,
        }),
      );
    });
  });

  (deftest "does not emit subagent_ended on completion for persistent session-mode runs", async () => {
    await withPendingAgentWait(async () => {
      const resolveAnnounce = createDeferredAnnounceResolver();
      registerCompletionModeRun(
        "run-persistent-session",
        "agent:main:subagent:persistent-session",
        "persistent session task",
        { spawnMode: "session" },
      );

      emitLifecycleEnd("run-persistent-session");

      await flushAnnounce();
      (expect* runSubagentEndedHookMock).not.toHaveBeenCalled();

      resolveAnnounce(true);
      await flushAnnounce();

      (expect* runSubagentEndedHookMock).not.toHaveBeenCalled();
      const run = listMainRuns()[0];
      (expect* run?.runId).is("run-persistent-session");
      (expect* run?.cleanupCompletedAt).toBeTypeOf("number");
      (expect* run?.endedHookEmittedAt).toBeUndefined();
    });
  });

  (deftest "clears announce retry state when replacing after steer restart", () => {
    registerRun({
      runId: "run-retry-reset-old",
      childSessionKey: "agent:main:subagent:retry-reset",
      task: "retry reset",
    });

    const previous = listMainRuns()[0];
    (expect* previous?.runId).is("run-retry-reset-old");
    if (previous) {
      previous.announceRetryCount = 2;
      previous.lastAnnounceRetryAt = Date.now();
    }

    const run = replaceRunAfterSteer({
      previousRunId: "run-retry-reset-old",
      nextRunId: "run-retry-reset-new",
      fallback: previous,
    });
    (expect* run.announceRetryCount).toBeUndefined();
    (expect* run.lastAnnounceRetryAt).toBeUndefined();
  });

  (deftest "clears terminal lifecycle state when replacing after steer restart", async () => {
    registerRun({
      runId: "run-terminal-state-old",
      childSessionKey: "agent:main:subagent:terminal-state",
      task: "terminal state",
    });

    const previous = listMainRuns()[0];
    (expect* previous?.runId).is("run-terminal-state-old");
    if (previous) {
      previous.endedHookEmittedAt = Date.now();
      previous.endedReason = "subagent-complete";
      previous.endedAt = Date.now();
      previous.outcome = { status: "ok" };
    }

    const run = replaceRunAfterSteer({
      previousRunId: "run-terminal-state-old",
      nextRunId: "run-terminal-state-new",
      fallback: previous,
    });
    (expect* run.endedHookEmittedAt).toBeUndefined();
    (expect* run.endedReason).toBeUndefined();

    emitLifecycleEnd("run-terminal-state-new");

    await flushAnnounce();
    (expect* runSubagentEndedHookMock).toHaveBeenCalledTimes(1);
    (expect* runSubagentEndedHookMock).toHaveBeenCalledWith(
      expect.objectContaining({
        runId: "run-terminal-state-new",
      }),
      expect.objectContaining({
        runId: "run-terminal-state-new",
      }),
    );
  });

  (deftest "clears frozen completion fields when replacing after steer restart", () => {
    registerRun({
      runId: "run-frozen-old",
      childSessionKey: "agent:main:subagent:frozen",
      task: "frozen result reset",
    });

    const previous = listMainRuns()[0];
    (expect* previous?.runId).is("run-frozen-old");
    if (previous) {
      previous.frozenResultText = "stale frozen completion";
      previous.frozenResultCapturedAt = Date.now();
      previous.cleanupCompletedAt = Date.now();
      previous.cleanupHandled = true;
    }

    const run = replaceRunAfterSteer({
      previousRunId: "run-frozen-old",
      nextRunId: "run-frozen-new",
      fallback: previous,
    });

    (expect* run.frozenResultText).toBeUndefined();
    (expect* run.frozenResultCapturedAt).toBeUndefined();
    (expect* run.cleanupCompletedAt).toBeUndefined();
    (expect* run.cleanupHandled).is(false);
  });

  (deftest "preserves frozen completion as fallback when replacing for wake continuation", () => {
    registerRun({
      runId: "run-wake-old",
      childSessionKey: "agent:main:subagent:wake",
      task: "wake result fallback",
    });

    const previous = listMainRuns()[0];
    (expect* previous?.runId).is("run-wake-old");
    if (previous) {
      previous.frozenResultText = "final summary before wake";
      previous.frozenResultCapturedAt = 1234;
    }

    const replaced = mod.replaceSubagentRunAfterSteer({
      previousRunId: "run-wake-old",
      nextRunId: "run-wake-new",
      fallback: previous,
      preserveFrozenResultFallback: true,
    });
    (expect* replaced).is(true);

    const run = listMainRuns().find((entry) => entry.runId === "run-wake-new");
    (expect* run).matches-object({
      frozenResultText: undefined,
      fallbackFrozenResultText: "final summary before wake",
      fallbackFrozenResultCapturedAt: 1234,
    });
  });

  (deftest "restores announce for a finished run when steer replacement dispatch fails", async () => {
    registerRun({
      runId: "run-failed-restart",
      childSessionKey: "agent:main:subagent:failed-restart",
      task: "initial task",
    });

    (expect* mod.markSubagentRunForSteerRestart("run-failed-restart")).is(true);

    emitLifecycleEnd("run-failed-restart");

    await flushAnnounce();
    (expect* announceSpy).not.toHaveBeenCalled();

    (expect* mod.clearSubagentRunSteerRestart("run-failed-restart")).is(true);
    await flushAnnounce();

    (expect* announceSpy).toHaveBeenCalledTimes(1);
    const announce = (announceSpy.mock.calls[0]?.[0] ?? {}) as { childRunId?: string };
    (expect* announce.childRunId).is("run-failed-restart");
  });

  (deftest "marks killed runs terminated and inactive", async () => {
    const childSessionKey = "agent:main:subagent:killed";

    registerRun({
      runId: "run-killed",
      childSessionKey,
      task: "kill me",
    });

    (expect* mod.isSubagentSessionRunActive(childSessionKey)).is(true);
    const updated = mod.markSubagentRunTerminated({
      childSessionKey,
      reason: "manual kill",
    });
    (expect* updated).is(1);
    (expect* mod.isSubagentSessionRunActive(childSessionKey)).is(false);

    const run = listMainRuns()[0];
    (expect* run?.outcome).is-equal({ status: "error", error: "manual kill" });
    (expect* run?.cleanupHandled).is(true);
    (expect* typeof run?.cleanupCompletedAt).is("number");
    (expect* runSubagentEndedHookMock).toHaveBeenCalledWith(
      {
        targetSessionKey: childSessionKey,
        targetKind: "subagent",
        reason: "subagent-killed",
        sendFarewell: true,
        accountId: undefined,
        runId: "run-killed",
        endedAt: expect.any(Number),
        outcome: "killed",
        error: "manual kill",
      },
      {
        runId: "run-killed",
        childSessionKey,
        requesterSessionKey: MAIN_REQUESTER_SESSION_KEY,
      },
    );
  });

  (deftest "recovers announce cleanup when completion arrives after a kill marker", async () => {
    const childSessionKey = "agent:main:subagent:kill-race";
    registerRun({
      runId: "run-kill-race",
      childSessionKey,
      task: "race test",
    });

    (expect* mod.markSubagentRunTerminated({ runId: "run-kill-race", reason: "manual kill" })).is(
      1,
    );
    (expect* listMainRuns()[0]?.suppressAnnounceReason).is("killed");
    (expect* listMainRuns()[0]?.cleanupHandled).is(true);
    (expect* typeof listMainRuns()[0]?.cleanupCompletedAt).is("number");

    emitLifecycleEnd("run-kill-race");
    await flushAnnounce();
    await flushAnnounce();

    (expect* announceSpy).toHaveBeenCalledTimes(1);
    const announce = (announceSpy.mock.calls[0]?.[0] ?? {}) as { childRunId?: string };
    (expect* announce.childRunId).is("run-kill-race");

    const run = listMainRuns()[0];
    (expect* run?.endedReason).is("subagent-complete");
    (expect* run?.outcome?.status).not.is("error");
    (expect* run?.suppressAnnounceReason).toBeUndefined();
    (expect* run?.cleanupHandled).is(true);
    (expect* typeof run?.cleanupCompletedAt).is("number");
    (expect* runSubagentEndedHookMock).toHaveBeenCalledTimes(1);
  });

  (deftest "retries deferred parent cleanup after a descendant announces", async () => {
    let parentAttempts = 0;
    announceSpy.mockImplementation(async (params: unknown) => {
      const typed = params as { childRunId?: string };
      if (typed.childRunId === "run-parent") {
        parentAttempts += 1;
        return parentAttempts >= 2;
      }
      return true;
    });

    registerRun({
      runId: "run-parent",
      childSessionKey: "agent:main:subagent:parent",
      task: "parent task",
    });
    registerRun({
      runId: "run-child",
      childSessionKey: "agent:main:subagent:parent:subagent:child",
      requesterSessionKey: "agent:main:subagent:parent",
      requesterDisplayKey: "parent",
      task: "child task",
    });

    emitLifecycleEnd("run-parent");
    await flushAnnounce();

    emitLifecycleEnd("run-child");
    await flushAnnounce();

    const childRunIds = announceSpy.mock.calls.map(
      (call) => ((call[0] ?? {}) as { childRunId?: string }).childRunId,
    );
    (expect* childRunIds.filter((id) => id === "run-parent")).has-length(2);
    (expect* childRunIds.filter((id) => id === "run-child")).has-length(1);
  });

  (deftest "retries completion-mode announce delivery with backoff and then gives up after retry limit", async () => {
    await withPendingAgentWait(async () => {
      mock:useFakeTimers();
      try {
        announceSpy.mockResolvedValue(false);

        registerCompletionModeRun(
          "run-completion-retry",
          "agent:main:subagent:completion",
          "completion retry",
        );

        emitLifecycleEnd("run-completion-retry");

        await mock:advanceTimersByTimeAsync(0);
        (expect* announceSpy).toHaveBeenCalledTimes(1);
        (expect* listMainRuns()[0]?.announceRetryCount).is(1);

        await mock:advanceTimersByTimeAsync(999);
        (expect* announceSpy).toHaveBeenCalledTimes(1);
        await mock:advanceTimersByTimeAsync(1);
        (expect* announceSpy).toHaveBeenCalledTimes(2);
        (expect* listMainRuns()[0]?.announceRetryCount).is(2);

        await mock:advanceTimersByTimeAsync(1_999);
        (expect* announceSpy).toHaveBeenCalledTimes(2);
        await mock:advanceTimersByTimeAsync(1);
        (expect* announceSpy).toHaveBeenCalledTimes(3);
        (expect* listMainRuns()[0]?.announceRetryCount).is(3);

        await mock:advanceTimersByTimeAsync(4_001);
        (expect* announceSpy).toHaveBeenCalledTimes(3);
        (expect* listMainRuns()[0]?.cleanupCompletedAt).toBeTypeOf("number");
      } finally {
        mock:useRealTimers();
      }
    });
  });

  (deftest "keeps completion cleanup pending while descendants are still active", async () => {
    announceSpy.mockResolvedValue(false);

    registerCompletionModeRun(
      "run-parent-expiry",
      "agent:main:subagent:parent-expiry",
      "parent completion expiry",
    );
    registerRun({
      runId: "run-child-active",
      childSessionKey: "agent:main:subagent:parent-expiry:subagent:child-active",
      requesterSessionKey: "agent:main:subagent:parent-expiry",
      requesterDisplayKey: "parent-expiry",
      task: "child still running",
    });

    emitLifecycleEnd("run-parent-expiry", {
      startedAt: Date.now() - 7 * 60_000,
      endedAt: Date.now() - 6 * 60_000,
    });

    await flushAnnounce();

    const parentHookCall = runSubagentEndedHookMock.mock.calls.find((call) => {
      const event = call[0] as { runId?: string; reason?: string };
      return event.runId === "run-parent-expiry" && event.reason === "subagent-complete";
    });
    (expect* parentHookCall).toBeUndefined();
    const parent = mod
      .listSubagentRunsForRequester(MAIN_REQUESTER_SESSION_KEY)
      .find((entry) => entry.runId === "run-parent-expiry");
    (expect* parent?.cleanupCompletedAt).toBeUndefined();
    (expect* parent?.cleanupHandled).is(false);
  });
});
