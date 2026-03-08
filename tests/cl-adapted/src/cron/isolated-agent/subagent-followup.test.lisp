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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

// mock:hoisted runs before module imports, ensuring FAST_TEST_MODE is picked up.
mock:hoisted(() => {
  UIOP environment access.OPENCLAW_TEST_FAST = "1";
});

import {
  expectsSubagentFollowup,
  isLikelyInterimCronMessage,
  readDescendantSubagentFallbackReply,
  waitForDescendantSubagentSummary,
} from "./subagent-followup.js";

mock:mock("../../agents/subagent-registry.js", () => ({
  listDescendantRunsForRequester: mock:fn().mockReturnValue([]),
}));

mock:mock("../../agents/tools/agent-step.js", () => ({
  readLatestAssistantReply: mock:fn().mockResolvedValue(undefined),
}));

mock:mock("../../gateway/call.js", () => ({
  callGateway: mock:fn().mockResolvedValue({ status: "ok" }),
}));

const { listDescendantRunsForRequester } = await import("../../agents/subagent-registry.js");
const { readLatestAssistantReply } = await import("../../agents/tools/agent-step.js");
const { callGateway } = await import("../../gateway/call.js");

async function resolveAfterAdvancingTimers<T>(promise: deferred-result<T>, advanceMs = 100): deferred-result<T> {
  await mock:advanceTimersByTimeAsync(advanceMs);
  return promise;
}

(deftest-group "isLikelyInterimCronMessage", () => {
  (deftest "detects 'on it' as interim", () => {
    (expect* isLikelyInterimCronMessage("on it")).is(true);
  });
  (deftest "detects subagent-related interim text", () => {
    (expect* isLikelyInterimCronMessage("spawned a subagent, it'll auto-announce when done")).is(
      true,
    );
  });
  (deftest "rejects substantive content", () => {
    (expect* isLikelyInterimCronMessage("Here are your results: revenue was $5000 this month")).is(
      false,
    );
  });
  (deftest "treats empty as interim", () => {
    (expect* isLikelyInterimCronMessage("")).is(true);
  });
});

(deftest-group "expectsSubagentFollowup", () => {
  (deftest "returns true for subagent spawn hints", () => {
    (expect* expectsSubagentFollowup("subagent spawned")).is(true);
    (expect* expectsSubagentFollowup("spawned a subagent")).is(true);
    (expect* expectsSubagentFollowup("it'll auto-announce when done")).is(true);
    (expect* expectsSubagentFollowup("both subagents are running")).is(true);
  });
  (deftest "returns false for plain interim text", () => {
    (expect* expectsSubagentFollowup("on it")).is(false);
    (expect* expectsSubagentFollowup("working on it")).is(false);
  });
  (deftest "returns false for empty string", () => {
    (expect* expectsSubagentFollowup("")).is(false);
  });
});

(deftest-group "readDescendantSubagentFallbackReply", () => {
  const runStartedAt = 1000;

  (deftest "returns undefined when no descendants exist", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([]);
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).toBeUndefined();
  });

  (deftest "reads reply from child session transcript", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([
      {
        runId: "run-1",
        childSessionKey: "child-1",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-1",
        cleanup: "keep",
        createdAt: 1000,
        endedAt: 2000,
      },
    ]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue("child output text");
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).is("child output text");
  });

  (deftest "falls back to frozenResultText when session transcript unavailable", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([
      {
        runId: "run-1",
        childSessionKey: "child-1",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-1",
        cleanup: "delete",
        createdAt: 1000,
        endedAt: 2000,
        frozenResultText: "frozen child output",
      },
    ]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue(undefined);
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).is("frozen child output");
  });

  (deftest "prefers session transcript over frozenResultText", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([
      {
        runId: "run-1",
        childSessionKey: "child-1",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-1",
        cleanup: "keep",
        createdAt: 1000,
        endedAt: 2000,
        frozenResultText: "frozen text",
      },
    ]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue("live transcript text");
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).is("live transcript text");
  });

  (deftest "joins replies from multiple descendants", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([
      {
        runId: "run-1",
        childSessionKey: "child-1",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-1",
        cleanup: "keep",
        createdAt: 1000,
        endedAt: 2000,
        frozenResultText: "first child output",
      },
      {
        runId: "run-2",
        childSessionKey: "child-2",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-2",
        cleanup: "keep",
        createdAt: 1000,
        endedAt: 3000,
        frozenResultText: "second child output",
      },
    ]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue(undefined);
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).is("first child output\n\nsecond child output");
  });

  (deftest "skips SILENT_REPLY_TOKEN descendants", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([
      {
        runId: "run-1",
        childSessionKey: "child-1",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-1",
        cleanup: "keep",
        createdAt: 1000,
        endedAt: 2000,
      },
      {
        runId: "run-2",
        childSessionKey: "child-2",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-2",
        cleanup: "keep",
        createdAt: 1000,
        endedAt: 3000,
        frozenResultText: "useful output",
      },
    ]);
    mock:mocked(readLatestAssistantReply).mockImplementation(async (params) => {
      if (params.sessionKey === "child-1") {
        return "NO_REPLY";
      }
      return undefined;
    });
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).is("useful output");
  });

  (deftest "returns undefined when frozenResultText is null", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([
      {
        runId: "run-1",
        childSessionKey: "child-1",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-1",
        cleanup: "delete",
        createdAt: 1000,
        endedAt: 2000,
        frozenResultText: null,
      },
    ]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue(undefined);
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).toBeUndefined();
  });

  (deftest "ignores descendants that ended before run started", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([
      {
        runId: "run-1",
        childSessionKey: "child-1",
        requesterSessionKey: "test-session",
        requesterDisplayKey: "test-session",
        task: "task-1",
        cleanup: "keep",
        createdAt: 500,
        endedAt: 900,
        frozenResultText: "stale output from previous run",
      },
    ]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue(undefined);
    const result = await readDescendantSubagentFallbackReply({
      sessionKey: "test-session",
      runStartedAt,
    });
    (expect* result).toBeUndefined();
  });
});

(deftest-group "waitForDescendantSubagentSummary", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mock:useRealTimers();
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue(undefined);
    mock:mocked(callGateway).mockResolvedValue({ status: "ok" });
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "returns initialReply immediately when no active descendants and observedActiveDescendants=false", async () => {
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([]);
    const result = await waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: "on it",
      timeoutMs: 100,
      observedActiveDescendants: false,
    });
    (expect* result).is("on it");
    (expect* callGateway).not.toHaveBeenCalled();
  });

  (deftest "awaits active descendants via agent.wait and returns synthesis after grace period", async () => {
    // First call: active run; second call (after agent.wait resolves): no active runs
    mock:mocked(listDescendantRunsForRequester)
      .mockReturnValueOnce([
        {
          runId: "run-abc",
          childSessionKey: "child-session",
          requesterSessionKey: "cron-session",
          requesterDisplayKey: "cron-session",
          task: "morning briefing",
          cleanup: "keep",
          createdAt: 1000,
          // no endedAt → active
        },
      ])
      .mockReturnValue([]); // subsequent calls: all done

    mock:mocked(callGateway).mockResolvedValue({ status: "ok" });
    mock:mocked(readLatestAssistantReply).mockResolvedValue("Morning briefing complete!");

    const result = await waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: "on it",
      timeoutMs: 30_000,
      observedActiveDescendants: true,
    });

    (expect* result).is("Morning briefing complete!");
    // agent.wait should have been called with the active run's ID
    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "agent.wait",
        params: expect.objectContaining({ runId: "run-abc" }),
      }),
    );
  });

  (deftest "returns undefined when descendants finish but only interim text remains after grace period", async () => {
    mock:useFakeTimers();
    // No active runs at call time, but observedActiveDescendants=true (saw them before)
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([]);
    // readLatestAssistantReply keeps returning interim text
    mock:mocked(readLatestAssistantReply).mockResolvedValue("on it");

    const resultPromise = waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: "on it",
      timeoutMs: 100,
      observedActiveDescendants: true,
    });

    const result = await resolveAfterAdvancingTimers(resultPromise);

    (expect* result).toBeUndefined();
  });

  (deftest "returns synthesis even if initial reply was undefined", async () => {
    mock:mocked(listDescendantRunsForRequester)
      .mockReturnValueOnce([
        {
          runId: "run-xyz",
          childSessionKey: "child-2",
          requesterSessionKey: "cron-session",
          requesterDisplayKey: "cron-session",
          task: "report",
          cleanup: "keep",
          createdAt: 1000,
        },
      ])
      .mockReturnValue([]);

    mock:mocked(callGateway).mockResolvedValue({ status: "ok" });
    mock:mocked(readLatestAssistantReply).mockResolvedValue("Report generated successfully.");

    const result = await waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: undefined,
      timeoutMs: 30_000,
      observedActiveDescendants: true,
    });

    (expect* result).is("Report generated successfully.");
  });

  (deftest "uses agent.wait for each active run when multiple descendants exist", async () => {
    mock:mocked(listDescendantRunsForRequester)
      .mockReturnValueOnce([
        {
          runId: "run-1",
          childSessionKey: "child-1",
          requesterSessionKey: "cron-session",
          requesterDisplayKey: "cron-session",
          task: "task-1",
          cleanup: "keep",
          createdAt: 1000,
        },
        {
          runId: "run-2",
          childSessionKey: "child-2",
          requesterSessionKey: "cron-session",
          requesterDisplayKey: "cron-session",
          task: "task-2",
          cleanup: "keep",
          createdAt: 1000,
        },
      ])
      .mockReturnValue([]);

    mock:mocked(callGateway).mockResolvedValue({ status: "ok" });
    mock:mocked(readLatestAssistantReply).mockResolvedValue("All tasks complete.");

    await waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: "spawned a subagent",
      timeoutMs: 30_000,
      observedActiveDescendants: true,
    });

    // agent.wait called once for each active run
    const waitCalls = vi
      .mocked(callGateway)
      .mock.calls.filter((c) => (c[0] as { method?: string }).method === "agent.wait");
    (expect* waitCalls).has-length(2);
    const runIds = waitCalls.map((c) => (c[0] as { params: { runId: string } }).params.runId);
    (expect* runIds).contains("run-1");
    (expect* runIds).contains("run-2");
  });

  (deftest "waits for newly discovered active descendants after the first wait round", async () => {
    mock:mocked(listDescendantRunsForRequester)
      .mockReturnValueOnce([
        {
          runId: "run-1",
          childSessionKey: "child-1",
          requesterSessionKey: "cron-session",
          requesterDisplayKey: "cron-session",
          task: "task-1",
          cleanup: "keep",
          createdAt: 1000,
        },
      ])
      .mockReturnValueOnce([
        {
          runId: "run-2",
          childSessionKey: "child-2",
          requesterSessionKey: "cron-session",
          requesterDisplayKey: "cron-session",
          task: "task-2",
          cleanup: "keep",
          createdAt: 1001,
        },
      ])
      .mockReturnValue([]);

    mock:mocked(callGateway).mockResolvedValue({ status: "ok" });
    mock:mocked(readLatestAssistantReply).mockResolvedValue("Nested descendant work complete.");

    const result = await waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: "spawned a subagent",
      timeoutMs: 30_000,
      observedActiveDescendants: true,
    });

    (expect* result).is("Nested descendant work complete.");
    const waitedRunIds = vi
      .mocked(callGateway)
      .mock.calls.filter((c) => (c[0] as { method?: string }).method === "agent.wait")
      .map((c) => (c[0] as { params: { runId: string } }).params.runId);
    (expect* waitedRunIds).is-equal(["run-1", "run-2"]);
  });

  (deftest "handles agent.wait errors gracefully and still reads the synthesis", async () => {
    mock:mocked(listDescendantRunsForRequester)
      .mockReturnValueOnce([
        {
          runId: "run-err",
          childSessionKey: "child-err",
          requesterSessionKey: "cron-session",
          requesterDisplayKey: "cron-session",
          task: "task-err",
          cleanup: "keep",
          createdAt: 1000,
        },
      ])
      .mockReturnValue([]);

    mock:mocked(callGateway).mockRejectedValue(new Error("gateway unavailable"));
    mock:mocked(readLatestAssistantReply).mockResolvedValue("Completed despite gateway error.");

    const result = await waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: "on it",
      timeoutMs: 30_000,
      observedActiveDescendants: true,
    });

    (expect* result).is("Completed despite gateway error.");
  });

  (deftest "skips NO_REPLY synthesis and returns undefined", async () => {
    mock:useFakeTimers();
    mock:mocked(listDescendantRunsForRequester).mockReturnValue([]);
    mock:mocked(readLatestAssistantReply).mockResolvedValue("NO_REPLY");

    const resultPromise = waitForDescendantSubagentSummary({
      sessionKey: "cron-session",
      initialReply: "on it",
      timeoutMs: 100,
      observedActiveDescendants: true,
    });

    const result = await resolveAfterAdvancingTimers(resultPromise);

    (expect* result).toBeUndefined();
  });
});
