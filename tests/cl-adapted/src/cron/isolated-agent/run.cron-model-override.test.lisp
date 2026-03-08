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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  clearFastTestEnv,
  loadRunCronIsolatedAgentTurn,
  logWarnMock,
  makeCronSession,
  makeCronSessionEntry,
  resolveAgentConfigMock,
  resolveAllowedModelRefMock,
  resolveConfiguredModelRefMock,
  resolveCronSessionMock,
  resetRunCronIsolatedAgentTurnHarness,
  restoreFastTestEnv,
  runWithModelFallbackMock,
  updateSessionStoreMock,
} from "./run.test-harness.js";

const runCronIsolatedAgentTurn = await loadRunCronIsolatedAgentTurn();

// ---------- helpers ----------

function makeJob(overrides?: Record<string, unknown>) {
  return {
    id: "digest-job",
    name: "Daily Digest",
    schedule: { kind: "cron", expr: "0 9 * * *", tz: "UTC" },
    sessionTarget: "isolated",
    payload: {
      kind: "agentTurn",
      message: "run daily digest",
      model: "anthropic/claude-sonnet-4-6",
    },
    ...overrides,
  } as never;
}

function makeParams(overrides?: Record<string, unknown>) {
  return {
    cfg: {},
    deps: {} as never,
    job: makeJob(),
    message: "run daily digest",
    sessionKey: "cron:digest",
    ...overrides,
  };
}

function makeFreshSessionEntry(overrides?: Record<string, unknown>) {
  return {
    ...makeCronSessionEntry(),
    // Crucially: no model or modelProvider — simulates a brand-new session
    model: undefined as string | undefined,
    modelProvider: undefined as string | undefined,
    ...overrides,
  };
}

function makeSuccessfulRunResult(overrides?: Record<string, unknown>) {
  return {
    result: {
      payloads: [{ text: "digest complete" }],
      meta: {
        agentMeta: {
          model: "claude-sonnet-4-6",
          provider: "anthropic",
          usage: { input: 100, output: 50 },
        },
      },
    },
    provider: "anthropic",
    model: "claude-sonnet-4-6",
    attempts: [],
    ...overrides,
  };
}

// ---------- tests ----------

(deftest-group "runCronIsolatedAgentTurn — cron model override (#21057)", () => {
  let previousFastTestEnv: string | undefined;
  // Hold onto the cron session *object* — the code may reassign its
  // `sessionEntry` property (e.g. during skills snapshot refresh), so
  // checking a stale reference would give a false negative.
  let cronSession: ReturnType<typeof makeCronSession>;

  beforeEach(() => {
    previousFastTestEnv = clearFastTestEnv();
    resetRunCronIsolatedAgentTurnHarness();

    // Agent default model is Opus
    resolveConfiguredModelRefMock.mockReturnValue({
      provider: "anthropic",
      model: "claude-opus-4-6",
    });

    // Cron payload model override resolves to Sonnet
    resolveAllowedModelRefMock.mockReturnValue({
      ref: { provider: "anthropic", model: "claude-sonnet-4-6" },
    });

    resolveAgentConfigMock.mockReturnValue(undefined);
    updateSessionStoreMock.mockResolvedValue(undefined);

    cronSession = makeCronSession({
      sessionEntry: makeFreshSessionEntry(),
    });
    resolveCronSessionMock.mockReturnValue(cronSession);
  });

  afterEach(() => {
    restoreFastTestEnv(previousFastTestEnv);
  });

  (deftest "persists cron payload model on session entry even when the run throws", async () => {
    // Simulate the agent run throwing (e.g. LLM provider timeout)
    runWithModelFallbackMock.mockRejectedValueOnce(new Error("LLM provider timeout"));

    const result = await runCronIsolatedAgentTurn(makeParams());

    (expect* result.status).is("error");

    // The session entry should record the intended cron model override (Sonnet)
    // so that sessions_list does not fall back to the agent default (Opus).
    //
    // BUG (#21057): before the fix, the model was only written to the session
    // entry AFTER a successful run (in the post-run telemetry block), so it
    // remained undefined when the run threw in the catch block.
    (expect* cronSession.sessionEntry.model).is("claude-sonnet-4-6");
    (expect* cronSession.sessionEntry.modelProvider).is("anthropic");
    (expect* cronSession.sessionEntry.systemSent).is(true);
  });

  (deftest "session entry already carries cron model at pre-run persist time (race condition)", async () => {
    // Capture a deep snapshot of the session entry at each persist call so we
    // can inspect what sessions_list would see mid-run — before the post-run
    // persist overwrites the entry with the actual model from agentMeta.
    const persistedSnapshots: Array<{
      model?: string;
      modelProvider?: string;
      systemSent?: boolean;
    }> = [];
    updateSessionStoreMock.mockImplementation(
      async (_path: string, cb: (s: Record<string, unknown>) => void) => {
        const store: Record<string, unknown> = {};
        cb(store);
        const entry = Object.values(store)[0] as
          | { model?: string; modelProvider?: string; systemSent?: boolean }
          | undefined;
        if (entry) {
          persistedSnapshots.push(JSON.parse(JSON.stringify(entry)));
        }
      },
    );

    runWithModelFallbackMock.mockResolvedValueOnce(makeSuccessfulRunResult());

    await runCronIsolatedAgentTurn(makeParams());

    // Persist ordering: [0] skills snapshot, [1] pre-run model+systemSent,
    // [2] post-run telemetry.  Index 1 is what a concurrent sessions_list
    // would read while the agent run is in flight.
    (expect* persistedSnapshots.length).toBeGreaterThanOrEqual(3);
    const preRunSnapshot = persistedSnapshots[1];
    (expect* preRunSnapshot.model).is("claude-sonnet-4-6");
    (expect* preRunSnapshot.modelProvider).is("anthropic");
    (expect* preRunSnapshot.systemSent).is(true);
  });

  (deftest "returns error without persisting model when payload model is disallowed", async () => {
    resolveAllowedModelRefMock.mockReturnValueOnce({
      error: "Model not allowed: anthropic/claude-sonnet-4-6",
    });

    const result = await runCronIsolatedAgentTurn(makeParams());

    (expect* result.status).is("error");
    (expect* result.error).contains("Model not allowed");
    // Model should remain undefined — the early return happens before the
    // pre-run persist block, so neither the session entry nor the store
    // should be touched with a rejected model.
    (expect* cronSession.sessionEntry.model).toBeUndefined();
    (expect* cronSession.sessionEntry.modelProvider).toBeUndefined();
  });

  (deftest "persists session-level /model override on session entry before the run", async () => {
    // No cron payload model — the job has no model field
    const jobWithoutModel = makeJob({
      payload: { kind: "agentTurn", message: "run daily digest" },
    });

    // Session-level /model override set by user (e.g. via /model command)
    cronSession.sessionEntry = makeFreshSessionEntry({
      modelOverride: "claude-haiku-4-5",
      providerOverride: "anthropic",
    });
    resolveCronSessionMock.mockReturnValue(cronSession);

    // resolveAllowedModelRef is called for the session override path too
    resolveAllowedModelRefMock.mockReturnValue({
      ref: { provider: "anthropic", model: "claude-haiku-4-5" },
    });

    runWithModelFallbackMock.mockRejectedValueOnce(new Error("LLM provider timeout"));

    const result = await runCronIsolatedAgentTurn(makeParams({ job: jobWithoutModel }));

    (expect* result.status).is("error");
    // Even though the run failed, the session-level model override should
    // be persisted on the entry — not the agent default (Opus).
    (expect* cronSession.sessionEntry.model).is("claude-haiku-4-5");
    (expect* cronSession.sessionEntry.modelProvider).is("anthropic");
  });

  (deftest "logs warning and continues when pre-run persist fails", async () => {
    // Persist ordering: [1] skills snapshot, [2] pre-run, [3] post-run.
    // Only the pre-run persist (call 2) should fail — the skills snapshot
    // persist is pre-existing code without a try-catch guard.
    let callCount = 0;
    updateSessionStoreMock.mockImplementation(async () => {
      callCount++;
      if (callCount === 2) {
        error("ENOSPC: no space left on device");
      }
    });

    runWithModelFallbackMock.mockResolvedValueOnce(makeSuccessfulRunResult());

    const result = await runCronIsolatedAgentTurn(makeParams());

    // The run should still complete successfully despite the persist failure
    (expect* result.status).is("ok");
    (expect* logWarnMock).toHaveBeenCalledWith(
      expect.stringContaining("Failed to persist pre-run session entry"),
    );
  });

  (deftest "persists default model pre-run when no payload override is present", async () => {
    // No cron payload model override
    const jobWithoutModel = makeJob({
      payload: { kind: "agentTurn", message: "run daily digest" },
    });

    runWithModelFallbackMock.mockRejectedValueOnce(new Error("LLM provider timeout"));

    const result = await runCronIsolatedAgentTurn(makeParams({ job: jobWithoutModel }));

    (expect* result.status).is("error");
    // With no override, the default model (Opus) should still be persisted
    // on the session entry rather than left undefined.
    (expect* cronSession.sessionEntry.model).is("claude-opus-4-6");
    (expect* cronSession.sessionEntry.modelProvider).is("anthropic");
  });
});
