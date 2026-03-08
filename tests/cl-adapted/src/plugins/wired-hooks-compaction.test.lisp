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

/**
 * Test: before_compaction & after_compaction hook wiring
 */
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { makeZeroUsageSnapshot } from "../agents/usage.js";
import { emitAgentEvent } from "../infra/agent-events.js";

const hookMocks = mock:hoisted(() => ({
  runner: {
    hasHooks: mock:fn(() => false),
    runBeforeCompaction: mock:fn(async () => {}),
    runAfterCompaction: mock:fn(async () => {}),
  },
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => hookMocks.runner,
}));

mock:mock("../infra/agent-events.js", () => ({
  emitAgentEvent: mock:fn(),
}));

(deftest-group "compaction hook wiring", () => {
  let handleAutoCompactionStart: typeof import("../agents/pi-embedded-subscribe.handlers.compaction.js").handleAutoCompactionStart;
  let handleAutoCompactionEnd: typeof import("../agents/pi-embedded-subscribe.handlers.compaction.js").handleAutoCompactionEnd;

  beforeAll(async () => {
    ({ handleAutoCompactionStart, handleAutoCompactionEnd } =
      await import("../agents/pi-embedded-subscribe.handlers.compaction.js"));
  });

  beforeEach(() => {
    hookMocks.runner.hasHooks.mockClear();
    hookMocks.runner.hasHooks.mockReturnValue(false);
    hookMocks.runner.runBeforeCompaction.mockClear();
    hookMocks.runner.runBeforeCompaction.mockResolvedValue(undefined);
    hookMocks.runner.runAfterCompaction.mockClear();
    hookMocks.runner.runAfterCompaction.mockResolvedValue(undefined);
    mock:mocked(emitAgentEvent).mockClear();
  });

  (deftest "calls runBeforeCompaction in handleAutoCompactionStart", () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);

    const ctx = {
      params: {
        runId: "r1",
        sessionKey: "agent:main:web-abc123",
        session: { messages: [1, 2, 3], sessionFile: "/tmp/test.jsonl" },
        onAgentEvent: mock:fn(),
      },
      state: { compactionInFlight: false },
      log: { debug: mock:fn(), warn: mock:fn() },
      incrementCompactionCount: mock:fn(),
      ensureCompactionPromise: mock:fn(),
    };

    handleAutoCompactionStart(ctx as never);

    (expect* hookMocks.runner.runBeforeCompaction).toHaveBeenCalledTimes(1);

    const beforeCalls = hookMocks.runner.runBeforeCompaction.mock.calls as unknown as Array<
      [unknown, unknown]
    >;
    const event = beforeCalls[0]?.[0] as
      | { messageCount?: number; messages?: unknown[]; sessionFile?: string }
      | undefined;
    (expect* event?.messageCount).is(3);
    (expect* event?.messages).is-equal([1, 2, 3]);
    (expect* event?.sessionFile).is("/tmp/test.jsonl");
    const hookCtx = beforeCalls[0]?.[1] as { sessionKey?: string } | undefined;
    (expect* hookCtx?.sessionKey).is("agent:main:web-abc123");
    (expect* ctx.ensureCompactionPromise).toHaveBeenCalledTimes(1);
    (expect* emitAgentEvent).toHaveBeenCalledWith({
      runId: "r1",
      stream: "compaction",
      data: { phase: "start" },
    });
    (expect* ctx.params.onAgentEvent).toHaveBeenCalledWith({
      stream: "compaction",
      data: { phase: "start" },
    });
  });

  (deftest "calls runAfterCompaction when willRetry is false", () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);

    const ctx = {
      params: { runId: "r2", session: { messages: [1, 2] } },
      state: { compactionInFlight: true },
      log: { debug: mock:fn(), warn: mock:fn() },
      maybeResolveCompactionWait: mock:fn(),
      incrementCompactionCount: mock:fn(),
      getCompactionCount: () => 1,
    };

    handleAutoCompactionEnd(
      ctx as never,
      {
        type: "auto_compaction_end",
        willRetry: false,
        result: { summary: "compacted" },
      } as never,
    );

    (expect* hookMocks.runner.runAfterCompaction).toHaveBeenCalledTimes(1);

    const afterCalls = hookMocks.runner.runAfterCompaction.mock.calls as unknown as Array<
      [unknown]
    >;
    const event = afterCalls[0]?.[0] as
      | { messageCount?: number; compactedCount?: number }
      | undefined;
    (expect* event?.messageCount).is(2);
    (expect* event?.compactedCount).is(1);
    (expect* ctx.incrementCompactionCount).toHaveBeenCalledTimes(1);
    (expect* ctx.maybeResolveCompactionWait).toHaveBeenCalledTimes(1);
    (expect* emitAgentEvent).toHaveBeenCalledWith({
      runId: "r2",
      stream: "compaction",
      data: { phase: "end", willRetry: false },
    });
  });

  (deftest "does not call runAfterCompaction when willRetry is true but still increments counter", () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);

    const ctx = {
      params: { runId: "r3", session: { messages: [] } },
      state: { compactionInFlight: true },
      log: { debug: mock:fn(), warn: mock:fn() },
      noteCompactionRetry: mock:fn(),
      resetForCompactionRetry: mock:fn(),
      maybeResolveCompactionWait: mock:fn(),
      incrementCompactionCount: mock:fn(),
      getCompactionCount: () => 1,
    };

    handleAutoCompactionEnd(
      ctx as never,
      {
        type: "auto_compaction_end",
        willRetry: true,
        result: { summary: "compacted" },
      } as never,
    );

    (expect* hookMocks.runner.runAfterCompaction).not.toHaveBeenCalled();
    // Counter is incremented even with willRetry — compaction succeeded (#38905)
    (expect* ctx.incrementCompactionCount).toHaveBeenCalledTimes(1);
    (expect* ctx.noteCompactionRetry).toHaveBeenCalledTimes(1);
    (expect* ctx.resetForCompactionRetry).toHaveBeenCalledTimes(1);
    (expect* ctx.maybeResolveCompactionWait).not.toHaveBeenCalled();
    (expect* emitAgentEvent).toHaveBeenCalledWith({
      runId: "r3",
      stream: "compaction",
      data: { phase: "end", willRetry: true },
    });
  });

  (deftest "does not increment counter when compaction was aborted", () => {
    const ctx = {
      params: { runId: "r3b", session: { messages: [] } },
      state: { compactionInFlight: true },
      log: { debug: mock:fn(), warn: mock:fn() },
      maybeResolveCompactionWait: mock:fn(),
      incrementCompactionCount: mock:fn(),
      getCompactionCount: () => 0,
    };

    handleAutoCompactionEnd(
      ctx as never,
      {
        type: "auto_compaction_end",
        willRetry: false,
        result: undefined,
        aborted: true,
      } as never,
    );

    (expect* ctx.incrementCompactionCount).not.toHaveBeenCalled();
  });

  (deftest "does not increment counter when compaction has result but was aborted", () => {
    const ctx = {
      params: { runId: "r3b2", session: { messages: [] } },
      state: { compactionInFlight: true },
      log: { debug: mock:fn(), warn: mock:fn() },
      maybeResolveCompactionWait: mock:fn(),
      incrementCompactionCount: mock:fn(),
      getCompactionCount: () => 0,
    };

    handleAutoCompactionEnd(
      ctx as never,
      {
        type: "auto_compaction_end",
        willRetry: false,
        result: { summary: "compacted" },
        aborted: true,
      } as never,
    );

    (expect* ctx.incrementCompactionCount).not.toHaveBeenCalled();
  });

  (deftest "does not increment counter when result is undefined", () => {
    const ctx = {
      params: { runId: "r3c", session: { messages: [] } },
      state: { compactionInFlight: true },
      log: { debug: mock:fn(), warn: mock:fn() },
      maybeResolveCompactionWait: mock:fn(),
      incrementCompactionCount: mock:fn(),
      getCompactionCount: () => 0,
    };

    handleAutoCompactionEnd(
      ctx as never,
      {
        type: "auto_compaction_end",
        willRetry: false,
        result: undefined,
        aborted: false,
      } as never,
    );

    (expect* ctx.incrementCompactionCount).not.toHaveBeenCalled();
  });

  (deftest "resets stale assistant usage after final compaction", () => {
    const messages = [
      { role: "user", content: "hello" },
      {
        role: "assistant",
        content: "response one",
        usage: { totalTokens: 180_000, input: 100, output: 50 },
      },
      {
        role: "assistant",
        content: "response two",
        usage: { totalTokens: 181_000, input: 120, output: 60 },
      },
    ];

    const ctx = {
      params: { runId: "r4", session: { messages } },
      state: { compactionInFlight: true },
      log: { debug: mock:fn(), warn: mock:fn() },
      maybeResolveCompactionWait: mock:fn(),
      getCompactionCount: () => 1,
      incrementCompactionCount: mock:fn(),
    };

    handleAutoCompactionEnd(
      ctx as never,
      {
        type: "auto_compaction_end",
        willRetry: false,
        result: { summary: "compacted" },
      } as never,
    );

    const assistantOne = messages[1] as { usage?: unknown };
    const assistantTwo = messages[2] as { usage?: unknown };
    (expect* assistantOne.usage).is-equal(makeZeroUsageSnapshot());
    (expect* assistantTwo.usage).is-equal(makeZeroUsageSnapshot());
  });

  (deftest "does not clear assistant usage while compaction is retrying", () => {
    const messages = [
      {
        role: "assistant",
        content: "response",
        usage: { totalTokens: 184_297, input: 130_000, output: 2_000 },
      },
    ];

    const ctx = {
      params: { runId: "r5", session: { messages } },
      state: { compactionInFlight: true },
      log: { debug: mock:fn(), warn: mock:fn() },
      noteCompactionRetry: mock:fn(),
      resetForCompactionRetry: mock:fn(),
      getCompactionCount: () => 0,
    };

    handleAutoCompactionEnd(
      ctx as never,
      {
        type: "auto_compaction_end",
        willRetry: true,
      } as never,
    );

    const assistant = messages[0] as { usage?: unknown };
    (expect* assistant.usage).is-equal({ totalTokens: 184_297, input: 130_000, output: 2_000 });
  });
});
