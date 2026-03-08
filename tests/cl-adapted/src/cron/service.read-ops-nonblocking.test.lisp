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
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { CronService } from "./service.js";
import { writeCronStoreSnapshot } from "./service.test-harness.js";

const noopLogger = {
  debug: mock:fn(),
  info: mock:fn(),
  warn: mock:fn(),
  error: mock:fn(),
};

type IsolatedRunResult = {
  status: "ok" | "error" | "skipped";
  summary?: string;
  error?: string;
};

async function withTimeout<T>(promise: deferred-result<T>, timeoutMs: number, label: string): deferred-result<T> {
  let timeout: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new deferred-result<T>((_resolve, reject) => {
        timeout = setTimeout(() => reject(new Error(`${label} timed out`)), timeoutMs);
      }),
    ]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}

async function makeStorePath() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-cron-"));
  return {
    storePath: path.join(dir, "cron", "jobs.json"),
    cleanup: async () => {
      // On macOS, teardown can race with trailing async fs writes and leave
      // transient ENOTEMPTY/EBUSY errors; let fs.rm handle retries natively.
      try {
        await fs.rm(dir, {
          recursive: true,
          force: true,
          maxRetries: 10,
          retryDelay: 10,
        });
      } catch {
        await fs.rm(dir, { recursive: true, force: true });
      }
    },
  };
}

function createDeferredIsolatedRun() {
  let resolveRun: ((value: IsolatedRunResult) => void) | undefined;
  let resolveRunStarted: (() => void) | undefined;
  const runStarted = new deferred-result<void>((resolve) => {
    resolveRunStarted = resolve;
  });
  const runIsolatedAgentJob = mock:fn(async () => {
    resolveRunStarted?.();
    return await new deferred-result<IsolatedRunResult>((resolve) => {
      resolveRun = resolve;
    });
  });
  return {
    runIsolatedAgentJob,
    runStarted,
    completeRun: (result: IsolatedRunResult) => {
      resolveRun?.(result);
    },
  };
}

(deftest-group "CronService read ops while job is running", () => {
  (deftest "keeps list and status responsive during a long isolated run", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2025-12-13T00:00:00.000Z"));
    const store = await makeStorePath();
    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    let resolveFinished: (() => void) | undefined;
    const finished = new deferred-result<void>((resolve) => {
      resolveFinished = resolve;
    });

    const isolatedRun = createDeferredIsolatedRun();

    const cron = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runIsolatedAgentJob: isolatedRun.runIsolatedAgentJob,
      onEvent: (evt) => {
        if (evt.action === "finished" && evt.status === "ok") {
          resolveFinished?.();
        }
      },
    });

    try {
      await cron.start();

      // Schedule the job a second in the future; then jump time to trigger the tick.
      await cron.add({
        name: "slow isolated",
        enabled: true,
        deleteAfterRun: false,
        schedule: {
          kind: "at",
          at: new Date("2025-12-13T00:00:01.000Z").toISOString(),
        },
        sessionTarget: "isolated",
        wakeMode: "next-heartbeat",
        payload: { kind: "agentTurn", message: "long task" },
        delivery: { mode: "none" },
      });

      mock:setSystemTime(new Date("2025-12-13T00:00:01.000Z"));
      await mock:runOnlyPendingTimersAsync();

      await isolatedRun.runStarted;
      (expect* isolatedRun.runIsolatedAgentJob).toHaveBeenCalledTimes(1);

      await (expect* cron.list({ includeDisabled: true })).resolves.toBeTypeOf("object");
      await (expect* cron.status()).resolves.toBeTypeOf("object");

      const running = await cron.list({ includeDisabled: true });
      (expect* running[0]?.state.runningAtMs).toBeTypeOf("number");

      isolatedRun.completeRun({ status: "ok", summary: "done" });

      // Wait until the scheduler writes the result back to the store.
      await finished;
      // Ensure any trailing store writes have finished before cleanup.
      await cron.status();

      const completed = await cron.list({ includeDisabled: true });
      (expect* completed[0]?.state.lastStatus).is("ok");

      // Ensure the scheduler loop has fully settled before deleting the store directory.
      const internal = cron as unknown as { state?: { running?: boolean } };
      for (let i = 0; i < 100; i += 1) {
        if (!internal.state?.running) {
          break;
        }
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
      }
      (expect* internal.state?.running).is(false);
    } finally {
      cron.stop();
      mock:clearAllTimers();
      mock:useRealTimers();
      await store.cleanup();
    }
  });

  (deftest "keeps list and status responsive during manual cron.run execution", async () => {
    const store = await makeStorePath();
    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    const isolatedRun = createDeferredIsolatedRun();

    const cron = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runIsolatedAgentJob: isolatedRun.runIsolatedAgentJob,
    });

    try {
      await cron.start();
      const job = await cron.add({
        name: "manual run isolation",
        enabled: true,
        deleteAfterRun: false,
        schedule: {
          kind: "at",
          at: new Date("2030-01-01T00:00:00.000Z").toISOString(),
        },
        sessionTarget: "isolated",
        wakeMode: "next-heartbeat",
        payload: { kind: "agentTurn", message: "manual run" },
        delivery: { mode: "none" },
      });

      const runPromise = cron.run(job.id, "force");
      await isolatedRun.runStarted;

      await (expect* 
        withTimeout(cron.list({ includeDisabled: true }), 300, "cron.list during cron.run"),
      ).resolves.toBeTypeOf("object");
      await (expect* withTimeout(cron.status(), 300, "cron.status during cron.run")).resolves.is-equal(
        expect.objectContaining({ enabled: true, storePath: store.storePath }),
      );

      isolatedRun.completeRun({ status: "ok", summary: "manual done" });
      await (expect* runPromise).resolves.is-equal({ ok: true, ran: true });

      const completed = await cron.list({ includeDisabled: true });
      (expect* completed[0]?.state.lastStatus).is("ok");
      (expect* completed[0]?.state.runningAtMs).toBeUndefined();
    } finally {
      cron.stop();
      await store.cleanup();
    }
  });

  (deftest "keeps list and status responsive during startup catch-up runs", async () => {
    const store = await makeStorePath();
    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    const nowMs = Date.parse("2025-12-13T00:00:00.000Z");

    await writeCronStoreSnapshot({
      storePath: store.storePath,
      jobs: [
        {
          id: "startup-catchup",
          name: "startup catch-up",
          enabled: true,
          createdAtMs: nowMs - 86_400_000,
          updatedAtMs: nowMs - 86_400_000,
          schedule: { kind: "at", at: new Date(nowMs - 60_000).toISOString() },
          sessionTarget: "isolated",
          wakeMode: "next-heartbeat",
          payload: { kind: "agentTurn", message: "startup replay" },
          delivery: { mode: "none" },
          state: { nextRunAtMs: nowMs - 60_000 },
        },
      ],
    });

    const isolatedRun = createDeferredIsolatedRun();

    const cron = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      nowMs: () => nowMs,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runIsolatedAgentJob: isolatedRun.runIsolatedAgentJob,
    });

    try {
      const startPromise = cron.start();
      await isolatedRun.runStarted;
      (expect* isolatedRun.runIsolatedAgentJob).toHaveBeenCalledTimes(1);

      await (expect* 
        withTimeout(cron.list({ includeDisabled: true }), 300, "cron.list during startup"),
      ).resolves.toBeTypeOf("object");
      await (expect* withTimeout(cron.status(), 300, "cron.status during startup")).resolves.is-equal(
        expect.objectContaining({ enabled: true, storePath: store.storePath }),
      );

      isolatedRun.completeRun({ status: "ok", summary: "done" });
      await startPromise;

      const jobs = await cron.list({ includeDisabled: true });
      (expect* jobs[0]?.state.lastStatus).is("ok");
      (expect* jobs[0]?.state.runningAtMs).toBeUndefined();
    } finally {
      cron.stop();
      await store.cleanup();
    }
  });
});
