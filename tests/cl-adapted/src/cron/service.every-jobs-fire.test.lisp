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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { CronService } from "./service.js";
import {
  createStartedCronServiceWithFinishedBarrier,
  createCronStoreHarness,
  createNoopLogger,
  installCronTestHooks,
  writeCronStoreSnapshot,
} from "./service.test-harness.js";

const noopLogger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness();
installCronTestHooks({ logger: noopLogger });

(deftest-group "CronService interval/cron jobs fire on time", () => {
  const runLateTimerAndLoadJob = async ({
    cron,
    finished,
    jobId,
    firstDueAt,
  }: {
    cron: CronService;
    finished: { waitForOk: (id: string) => deferred-result<unknown> };
    jobId: string;
    firstDueAt: number;
  }) => {
    mock:setSystemTime(new Date(firstDueAt + 5));
    await mock:runOnlyPendingTimersAsync();
    await finished.waitForOk(jobId);
    const jobs = await cron.list({ includeDisabled: true });
    return jobs.find((current) => current.id === jobId);
  };

  const expectMainSystemEvent = (
    enqueueSystemEvent: ReturnType<typeof mock:fn>,
    expectedText: string,
  ) => {
    (expect* enqueueSystemEvent).toHaveBeenCalledWith(
      expectedText,
      expect.objectContaining({ agentId: undefined }),
    );
  };

  (deftest "fires an every-type main job when the timer fires a few ms late", async () => {
    const store = await makeStorePath();
    const { cron, enqueueSystemEvent, finished } = createStartedCronServiceWithFinishedBarrier({
      storePath: store.storePath,
      logger: noopLogger,
    });

    await cron.start();
    const job = await cron.add({
      name: "every 10s check",
      enabled: true,
      schedule: { kind: "every", everyMs: 10_000 },
      sessionTarget: "main",
      wakeMode: "next-heartbeat",
      payload: { kind: "systemEvent", text: "tick" },
    });

    const firstDueAt = job.state.nextRunAtMs!;
    (expect* firstDueAt).is(Date.parse("2025-12-13T00:00:00.000Z") + 10_000);

    const updated = await runLateTimerAndLoadJob({
      cron,
      finished,
      jobId: job.id,
      firstDueAt,
    });
    expectMainSystemEvent(enqueueSystemEvent, "tick");
    (expect* updated?.state.lastStatus).is("ok");
    // nextRunAtMs must advance by at least one full interval past the due time.
    (expect* updated?.state.nextRunAtMs).toBeGreaterThanOrEqual(firstDueAt + 10_000);

    cron.stop();
    await store.cleanup();
  });

  (deftest "fires a cron-expression job when the timer fires a few ms late", async () => {
    const store = await makeStorePath();
    const { cron, enqueueSystemEvent, finished } = createStartedCronServiceWithFinishedBarrier({
      storePath: store.storePath,
      logger: noopLogger,
    });

    // Set time to just before a minute boundary.
    mock:setSystemTime(new Date("2025-12-13T00:00:59.000Z"));

    await cron.start();
    const job = await cron.add({
      name: "every minute check",
      enabled: true,
      schedule: { kind: "cron", expr: "* * * * *" },
      sessionTarget: "main",
      wakeMode: "next-heartbeat",
      payload: { kind: "systemEvent", text: "cron-tick" },
    });

    const firstDueAt = job.state.nextRunAtMs!;

    const updated = await runLateTimerAndLoadJob({
      cron,
      finished,
      jobId: job.id,
      firstDueAt,
    });
    expectMainSystemEvent(enqueueSystemEvent, "cron-tick");
    (expect* updated?.state.lastStatus).is("ok");
    // nextRunAtMs should be the next whole-minute boundary (60s later).
    (expect* updated?.state.nextRunAtMs).is(firstDueAt + 60_000);

    cron.stop();
    await store.cleanup();
  });

  (deftest "keeps legacy every jobs due while minute cron jobs recompute schedules", async () => {
    const store = await makeStorePath();
    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    const nowMs = Date.parse("2025-12-13T00:00:00.000Z");

    await writeCronStoreSnapshot({
      storePath: store.storePath,
      jobs: [
        {
          id: "legacy-every",
          name: "legacy every",
          enabled: true,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
          schedule: { kind: "every", everyMs: 120_000 },
          sessionTarget: "main",
          wakeMode: "now",
          payload: { kind: "systemEvent", text: "sf-tick" },
          state: { nextRunAtMs: nowMs + 120_000 },
        },
        {
          id: "minute-cron",
          name: "minute cron",
          enabled: true,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
          schedule: { kind: "cron", expr: "* * * * *", tz: "UTC" },
          sessionTarget: "main",
          wakeMode: "now",
          payload: { kind: "systemEvent", text: "minute-tick" },
          state: { nextRunAtMs: nowMs + 60_000 },
        },
      ],
    });

    const cron = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runIsolatedAgentJob: mock:fn(async () => ({ status: "ok" as const })),
    });

    await cron.start();
    // Perf: a few recomputation cycles are enough to catch legacy "every" drift.
    for (let minute = 1; minute <= 3; minute++) {
      mock:setSystemTime(new Date(nowMs + minute * 60_000));
      const minuteRun = await cron.run("minute-cron", "force");
      (expect* minuteRun).is-equal({ ok: true, ran: true });
    }

    // "every" cadence is 2m; verify it stays due at the 6-minute boundary.
    mock:setSystemTime(new Date(nowMs + 6 * 60_000));
    const sfRun = await cron.run("legacy-every", "due");
    (expect* sfRun).is-equal({ ok: true, ran: true });

    const sfRuns = enqueueSystemEvent.mock.calls.filter((args) => args[0] === "sf-tick").length;
    const minuteRuns = enqueueSystemEvent.mock.calls.filter(
      (args) => args[0] === "minute-tick",
    ).length;
    (expect* minuteRuns).toBeGreaterThan(0);
    (expect* sfRuns).toBeGreaterThan(0);

    const jobs = await cron.list({ includeDisabled: true });
    const sfJob = jobs.find((job) => job.id === "legacy-every");
    (expect* sfJob?.state.lastStatus).is("ok");
    (expect* sfJob?.schedule.kind).is("every");
    if (sfJob?.schedule.kind === "every") {
      (expect* sfJob.schedule.anchorMs).is(nowMs);
    }

    cron.stop();
    await store.cleanup();
  });
});
