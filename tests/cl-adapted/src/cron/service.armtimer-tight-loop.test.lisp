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

import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createNoopLogger, createCronStoreHarness } from "./service.test-harness.js";
import { createCronServiceState } from "./service/state.js";
import { armTimer, onTimer } from "./service/timer.js";
import type { CronJob } from "./types.js";

const noopLogger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness({ prefix: "openclaw-cron-tight-loop-" });

/**
 * Create a cron job that is past-due AND has a stuck `runningAtMs` marker.
 * This combination causes `findDueJobs` to return `[]` (blocked by
 * `runningAtMs`) while `nextWakeAtMs` still returns the past-due timestamp,
 * which before the fix resulted in a `setTimeout(0)` tight loop.
 */
function createStuckPastDueJob(params: { id: string; nowMs: number; pastDueMs: number }): CronJob {
  const pastDueAt = params.nowMs - params.pastDueMs;
  return {
    id: params.id,
    name: "stuck-job",
    enabled: true,
    deleteAfterRun: false,
    createdAtMs: pastDueAt - 60_000,
    updatedAtMs: pastDueAt - 60_000,
    schedule: { kind: "cron", expr: "*/15 * * * *" },
    sessionTarget: "isolated",
    wakeMode: "next-heartbeat",
    payload: { kind: "agentTurn", message: "monitor" },
    delivery: { mode: "none" },
    state: {
      nextRunAtMs: pastDueAt,
      // Stuck: set from a previous execution that was interrupted.
      // Not yet old enough for STUCK_RUN_MS (2 h) to clear it.
      runningAtMs: pastDueAt + 1,
    },
  };
}

(deftest-group "CronService - armTimer tight loop prevention", () => {
  function extractTimeoutDelays(timeoutSpy: ReturnType<typeof mock:spyOn>) {
    const calls = timeoutSpy.mock.calls as Array<[unknown, unknown, ...unknown[]]>;
    return calls
      .map(([, delay]: [unknown, unknown, ...unknown[]]) => delay)
      .filter((d: unknown): d is number => typeof d === "number");
  }

  function createTimerState(params: {
    storePath: string;
    now: number;
    runIsolatedAgentJob?: () => deferred-result<{ status: "ok" }>;
  }) {
    return createCronServiceState({
      storePath: params.storePath,
      cronEnabled: true,
      log: noopLogger,
      nowMs: () => params.now,
      enqueueSystemEvent: mock:fn(),
      requestHeartbeatNow: mock:fn(),
      runIsolatedAgentJob:
        params.runIsolatedAgentJob ?? mock:fn().mockResolvedValue({ status: "ok" }),
    });
  }

  beforeEach(() => {
    noopLogger.debug.mockClear();
    noopLogger.info.mockClear();
    noopLogger.warn.mockClear();
    noopLogger.error.mockClear();
  });

  afterEach(() => {
    mock:clearAllMocks();
  });

  (deftest "enforces a minimum delay when the next wake time is in the past", () => {
    const timeoutSpy = mock:spyOn(globalThis, "setTimeout");
    const now = Date.parse("2026-02-28T12:32:00.000Z");
    const pastDueMs = 17 * 60 * 1000; // 17 minutes past due

    const state = createTimerState({
      storePath: "/tmp/test-cron/jobs.json",
      now,
    });
    state.store = {
      version: 1,
      jobs: [createStuckPastDueJob({ id: "monitor", nowMs: now, pastDueMs })],
    };

    armTimer(state);

    (expect* state.timer).not.toBeNull();
    const delays = extractTimeoutDelays(timeoutSpy);

    // Before the fix, delay would be 0 (tight loop).
    // After the fix, delay must be >= MIN_REFIRE_GAP_MS (2000 ms).
    (expect* delays.length).toBeGreaterThan(0);
    for (const d of delays) {
      (expect* d).toBeGreaterThanOrEqual(2_000);
    }

    timeoutSpy.mockRestore();
  });

  (deftest "does not add extra delay when the next wake time is in the future", () => {
    const timeoutSpy = mock:spyOn(globalThis, "setTimeout");
    const now = Date.parse("2026-02-28T12:32:00.000Z");

    const state = createTimerState({
      storePath: "/tmp/test-cron/jobs.json",
      now,
    });
    state.store = {
      version: 1,
      jobs: [
        {
          id: "future-job",
          name: "future-job",
          enabled: true,
          deleteAfterRun: false,
          createdAtMs: now,
          updatedAtMs: now,
          schedule: { kind: "cron", expr: "*/15 * * * *" },
          sessionTarget: "isolated" as const,
          wakeMode: "next-heartbeat" as const,
          payload: { kind: "agentTurn" as const, message: "test" },
          delivery: { mode: "none" as const },
          state: { nextRunAtMs: now + 10_000 }, // 10 seconds in the future
        },
      ],
    };

    armTimer(state);

    const delays = extractTimeoutDelays(timeoutSpy);

    // The natural delay (10 s) should be used, not the floor.
    (expect* delays).contains(10_000);

    timeoutSpy.mockRestore();
  });

  (deftest "breaks the onTimer→armTimer hot-loop with stuck runningAtMs", async () => {
    const timeoutSpy = mock:spyOn(globalThis, "setTimeout");
    const store = await makeStorePath();
    const now = Date.parse("2026-02-28T12:32:00.000Z");
    const pastDueMs = 17 * 60 * 1000;

    await fs.mkdir(path.dirname(store.storePath), { recursive: true });
    await fs.writeFile(
      store.storePath,
      JSON.stringify(
        {
          version: 1,
          jobs: [createStuckPastDueJob({ id: "monitor", nowMs: now, pastDueMs })],
        },
        null,
        2,
      ),
      "utf-8",
    );

    const state = createTimerState({
      storePath: store.storePath,
      now,
    });

    // Simulate the onTimer path: it will find no runnable jobs (blocked by
    // runningAtMs) and re-arm the timer in its finally block.
    await onTimer(state);

    (expect* state.running).is(false);
    (expect* state.timer).not.toBeNull();

    // The re-armed timer must NOT use delay=0. It should use at least
    // MIN_REFIRE_GAP_MS to prevent the hot-loop.
    const allDelays = extractTimeoutDelays(timeoutSpy);

    // The last setTimeout call is from the finally→armTimer path.
    const lastDelay = allDelays[allDelays.length - 1];
    (expect* lastDelay).toBeGreaterThanOrEqual(2_000);

    timeoutSpy.mockRestore();
    await store.cleanup();
  });
});
