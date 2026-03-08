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

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const noop = () => {};
const MAIN_REQUESTER_SESSION_KEY = "agent:main:main";
const MAIN_REQUESTER_DISPLAY_KEY = "main";

type LifecycleData = {
  phase?: string;
  startedAt?: number;
  endedAt?: number;
  aborted?: boolean;
  error?: string;
};
type LifecycleEvent = {
  stream?: string;
  runId: string;
  sessionKey?: string;
  data?: LifecycleData;
};

let lifecycleHandler: ((evt: LifecycleEvent) => void) | undefined;
const callGatewayMock = mock:fn(async (request: unknown) => {
  const method = (request as { method?: string }).method;
  if (method === "agent.wait") {
    // Keep wait unresolved from the RPC path so lifecycle fallback logic is exercised.
    return { status: "pending" };
  }
  return {};
});
const onAgentEventMock = mock:fn((handler: typeof lifecycleHandler) => {
  lifecycleHandler = handler;
  return noop;
});
const loadConfigMock = mock:fn(() => ({
  agents: { defaults: { subagents: { archiveAfterMinutes: 0 } } },
}));
const loadRegistryMock = mock:fn(() => new Map());
const saveRegistryMock = mock:fn(() => {});
const announceSpy = mock:fn(async (_params?: Record<string, unknown>) => true);
const captureCompletionReplySpy = mock:fn(
  async (_sessionKey?: string) => undefined as string | undefined,
);

mock:mock("../gateway/call.js", () => ({
  callGateway: callGatewayMock,
}));

mock:mock("../infra/agent-events.js", () => ({
  onAgentEvent: onAgentEventMock,
}));

mock:mock("../config/config.js", () => ({
  loadConfig: loadConfigMock,
}));

mock:mock("./subagent-announce.js", () => ({
  runSubagentAnnounceFlow: announceSpy,
  captureSubagentCompletionReply: captureCompletionReplySpy,
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: mock:fn(() => null),
}));

mock:mock("./subagent-registry.store.js", () => ({
  loadSubagentRegistryFromDisk: loadRegistryMock,
  saveSubagentRegistryToDisk: saveRegistryMock,
}));

(deftest-group "subagent registry lifecycle error grace", () => {
  let mod: typeof import("./subagent-registry.js");

  beforeAll(async () => {
    mod = await import("./subagent-registry.js");
  });

  beforeEach(() => {
    mock:useFakeTimers();
    announceSpy.mockReset().mockResolvedValue(true);
    captureCompletionReplySpy.mockReset().mockResolvedValue(undefined);
  });

  afterEach(() => {
    lifecycleHandler = undefined;
    mod.resetSubagentRegistryForTests({ persist: false });
    mock:useRealTimers();
  });

  const flushAsync = async () => {
    await Promise.resolve();
    await Promise.resolve();
  };

  const waitForCleanupHandledFalse = async (runId: string) => {
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const run = mod
        .listSubagentRunsForRequester(MAIN_REQUESTER_SESSION_KEY)
        .find((candidate) => candidate.runId === runId);
      if (run?.cleanupHandled === false) {
        return;
      }
      await mock:advanceTimersByTimeAsync(1);
      await flushAsync();
    }
    error(`run ${runId} did not reach cleanupHandled=false in time`);
  };

  const waitForCleanupCompleted = async (runId: string) => {
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const run = mod
        .listSubagentRunsForRequester(MAIN_REQUESTER_SESSION_KEY)
        .find((candidate) => candidate.runId === runId);
      if (typeof run?.cleanupCompletedAt === "number") {
        return run;
      }
      await mock:advanceTimersByTimeAsync(1);
      await flushAsync();
    }
    error(`run ${runId} did not complete cleanup in time`);
  };

  function registerCompletionRun(runId: string, childSuffix: string, task: string) {
    mod.registerSubagentRun({
      runId,
      childSessionKey: `agent:main:subagent:${childSuffix}`,
      requesterSessionKey: MAIN_REQUESTER_SESSION_KEY,
      requesterDisplayKey: MAIN_REQUESTER_DISPLAY_KEY,
      task,
      cleanup: "keep",
      expectsCompletionMessage: true,
    });
  }

  function emitLifecycleEvent(
    runId: string,
    data: LifecycleData,
    options?: { sessionKey?: string },
  ) {
    lifecycleHandler?.({
      stream: "lifecycle",
      runId,
      sessionKey: options?.sessionKey,
      data,
    });
  }

  function readFirstAnnounceOutcome() {
    const announceCalls = announceSpy.mock.calls as unknown as Array<Array<unknown>>;
    const first = (announceCalls[0]?.[0] ?? {}) as {
      outcome?: { status?: string; error?: string };
    };
    return first.outcome;
  }

  (deftest "ignores transient lifecycle errors when run retries and then ends successfully", async () => {
    registerCompletionRun("run-transient-error", "transient-error", "transient error test");

    emitLifecycleEvent("run-transient-error", {
      phase: "error",
      error: "rate limit",
      endedAt: 1_000,
    });
    await flushAsync();
    (expect* announceSpy).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(14_999);
    (expect* announceSpy).not.toHaveBeenCalled();

    emitLifecycleEvent("run-transient-error", { phase: "start", startedAt: 1_050 });
    await flushAsync();

    await mock:advanceTimersByTimeAsync(20_000);
    (expect* announceSpy).not.toHaveBeenCalled();

    emitLifecycleEvent("run-transient-error", { phase: "end", endedAt: 1_250 });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(1);
    (expect* readFirstAnnounceOutcome()?.status).is("ok");
  });

  (deftest "announces error when lifecycle error remains terminal after grace window", async () => {
    registerCompletionRun("run-terminal-error", "terminal-error", "terminal error test");

    emitLifecycleEvent("run-terminal-error", {
      phase: "error",
      error: "fatal failure",
      endedAt: 2_000,
    });
    await flushAsync();
    (expect* announceSpy).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(15_000);
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(1);
    (expect* readFirstAnnounceOutcome()?.status).is("error");
    (expect* readFirstAnnounceOutcome()?.error).is("fatal failure");
  });

  (deftest "freezes completion result at run termination across deferred announce retries", async () => {
    // Regression guard: late lifecycle noise must never overwrite the frozen completion reply.
    registerCompletionRun("run-freeze", "freeze", "freeze test");
    captureCompletionReplySpy.mockResolvedValueOnce("Final answer X");
    announceSpy.mockResolvedValueOnce(false).mockResolvedValueOnce(true);

    const endedAt = Date.now();
    emitLifecycleEvent("run-freeze", { phase: "end", endedAt });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(1);
    const firstCall = announceSpy.mock.calls[0]?.[0] as { roundOneReply?: string } | undefined;
    (expect* firstCall?.roundOneReply).is("Final answer X");

    await waitForCleanupHandledFalse("run-freeze");

    captureCompletionReplySpy.mockResolvedValueOnce("Late reply Y");
    emitLifecycleEvent("run-freeze", { phase: "end", endedAt: endedAt + 100 });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(2);
    const secondCall = announceSpy.mock.calls[1]?.[0] as { roundOneReply?: string } | undefined;
    (expect* secondCall?.roundOneReply).is("Final answer X");
    (expect* captureCompletionReplySpy).toHaveBeenCalledTimes(1);
  });

  (deftest "refreshes frozen completion output from later turns in the same session", async () => {
    registerCompletionRun("run-refresh", "refresh", "refresh frozen output test");
    captureCompletionReplySpy.mockResolvedValueOnce(
      "Both spawned. Waiting for completion events...",
    );
    announceSpy.mockResolvedValueOnce(false).mockResolvedValueOnce(true);

    const endedAt = Date.now();
    emitLifecycleEvent("run-refresh", { phase: "end", endedAt });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(1);
    const firstCall = announceSpy.mock.calls[0]?.[0] as { roundOneReply?: string } | undefined;
    (expect* firstCall?.roundOneReply).is("Both spawned. Waiting for completion events...");

    await waitForCleanupHandledFalse("run-refresh");

    const runBeforeRefresh = mod
      .listSubagentRunsForRequester(MAIN_REQUESTER_SESSION_KEY)
      .find((candidate) => candidate.runId === "run-refresh");
    const firstCapturedAt = runBeforeRefresh?.frozenResultCapturedAt ?? 0;

    captureCompletionReplySpy.mockResolvedValueOnce(
      "All 3 subagents complete. Here's the final summary.",
    );
    emitLifecycleEvent(
      "run-refresh-followup-turn",
      { phase: "end", endedAt: endedAt + 200 },
      { sessionKey: "agent:main:subagent:refresh" },
    );
    await flushAsync();

    const runAfterRefresh = mod
      .listSubagentRunsForRequester(MAIN_REQUESTER_SESSION_KEY)
      .find((candidate) => candidate.runId === "run-refresh");
    (expect* runAfterRefresh?.frozenResultText).is(
      "All 3 subagents complete. Here's the final summary.",
    );
    (expect* (runAfterRefresh?.frozenResultCapturedAt ?? 0) >= firstCapturedAt).is(true);

    emitLifecycleEvent("run-refresh", { phase: "end", endedAt: endedAt + 300 });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(2);
    const secondCall = announceSpy.mock.calls[1]?.[0] as { roundOneReply?: string } | undefined;
    (expect* secondCall?.roundOneReply).is("All 3 subagents complete. Here's the final summary.");
    (expect* captureCompletionReplySpy).toHaveBeenCalledTimes(2);
  });

  (deftest "ignores silent follow-up turns when refreshing frozen completion output", async () => {
    registerCompletionRun("run-refresh-silent", "refresh-silent", "refresh silent test");
    captureCompletionReplySpy.mockResolvedValueOnce("All work complete, final summary");
    announceSpy.mockResolvedValueOnce(false).mockResolvedValueOnce(true);

    const endedAt = Date.now();
    emitLifecycleEvent("run-refresh-silent", { phase: "end", endedAt });
    await flushAsync();
    await waitForCleanupHandledFalse("run-refresh-silent");

    captureCompletionReplySpy.mockResolvedValueOnce("NO_REPLY");
    emitLifecycleEvent(
      "run-refresh-silent-followup-turn",
      { phase: "end", endedAt: endedAt + 200 },
      { sessionKey: "agent:main:subagent:refresh-silent" },
    );
    await flushAsync();

    const runAfterSilent = mod
      .listSubagentRunsForRequester(MAIN_REQUESTER_SESSION_KEY)
      .find((candidate) => candidate.runId === "run-refresh-silent");
    (expect* runAfterSilent?.frozenResultText).is("All work complete, final summary");

    emitLifecycleEvent("run-refresh-silent", { phase: "end", endedAt: endedAt + 300 });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(2);
    const secondCall = announceSpy.mock.calls[1]?.[0] as { roundOneReply?: string } | undefined;
    (expect* secondCall?.roundOneReply).is("All work complete, final summary");
    (expect* captureCompletionReplySpy).toHaveBeenCalledTimes(2);
  });

  (deftest "regression, captures frozen completion output with 100KB cap and retains it for keep-mode cleanup", async () => {
    registerCompletionRun("run-capped", "capped", "capped result test");
    captureCompletionReplySpy.mockResolvedValueOnce("x".repeat(120 * 1024));
    announceSpy.mockResolvedValueOnce(true);

    emitLifecycleEvent("run-capped", { phase: "end", endedAt: Date.now() });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(1);
    const call = announceSpy.mock.calls[0]?.[0] as { roundOneReply?: string } | undefined;
    (expect* call?.roundOneReply).contains("[truncated: frozen completion output exceeded 100KB");
    (expect* Buffer.byteLength(call?.roundOneReply ?? "", "utf8")).toBeLessThanOrEqual(100 * 1024);

    const run = await waitForCleanupCompleted("run-capped");
    (expect* typeof run.frozenResultText).is("string");
    (expect* run.frozenResultText).contains("[truncated: frozen completion output exceeded 100KB");
    (expect* run.frozenResultCapturedAt).toBeTypeOf("number");
  });

  (deftest "keeps parallel child completion results frozen even when late traffic arrives", async () => {
    // Regression guard: fan-out retries must preserve each child's first frozen result text.
    registerCompletionRun("run-parallel-a", "parallel-a", "parallel a");
    registerCompletionRun("run-parallel-b", "parallel-b", "parallel b");
    captureCompletionReplySpy
      .mockResolvedValueOnce("Final answer A")
      .mockResolvedValueOnce("Final answer B");
    announceSpy
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(true)
      .mockResolvedValueOnce(true);

    const parallelEndedAt = Date.now();
    emitLifecycleEvent("run-parallel-a", { phase: "end", endedAt: parallelEndedAt });
    emitLifecycleEvent("run-parallel-b", { phase: "end", endedAt: parallelEndedAt + 1 });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(2);
    await waitForCleanupHandledFalse("run-parallel-a");
    await waitForCleanupHandledFalse("run-parallel-b");

    captureCompletionReplySpy.mockResolvedValue("Late overwrite");

    emitLifecycleEvent("run-parallel-a", { phase: "end", endedAt: parallelEndedAt + 100 });
    emitLifecycleEvent("run-parallel-b", { phase: "end", endedAt: parallelEndedAt + 101 });
    await flushAsync();

    (expect* announceSpy).toHaveBeenCalledTimes(4);

    const callsByRun = new Map<string, Array<{ roundOneReply?: string }>>();
    for (const call of announceSpy.mock.calls) {
      const params = (call?.[0] ?? {}) as { childRunId?: string; roundOneReply?: string };
      const runId = params.childRunId;
      if (!runId) {
        continue;
      }
      const existing = callsByRun.get(runId) ?? [];
      existing.push({ roundOneReply: params.roundOneReply });
      callsByRun.set(runId, existing);
    }

    (expect* callsByRun.get("run-parallel-a")?.map((entry) => entry.roundOneReply)).is-equal([
      "Final answer A",
      "Final answer A",
    ]);
    (expect* callsByRun.get("run-parallel-b")?.map((entry) => entry.roundOneReply)).is-equal([
      "Final answer B",
      "Final answer B",
    ]);
    (expect* captureCompletionReplySpy).toHaveBeenCalledTimes(2);
  });
});
