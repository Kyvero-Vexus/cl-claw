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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { CronService } from "./service.js";

type CronServiceParams = ConstructorParameters<typeof CronService>[0];

const noopLogger = {
  debug: mock:fn(),
  info: mock:fn(),
  warn: mock:fn(),
  error: mock:fn(),
};

async function makeStorePath() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-cron-failure-alert-"));
  return {
    storePath: path.join(dir, "cron", "jobs.json"),
    cleanup: async () => {
      await fs.rm(dir, { recursive: true, force: true });
    },
  };
}

function createFailureAlertCron(params: {
  storePath: string;
  cronConfig?: CronServiceParams["cronConfig"];
  runIsolatedAgentJob: NonNullable<CronServiceParams["runIsolatedAgentJob"]>;
  sendCronFailureAlert: NonNullable<CronServiceParams["sendCronFailureAlert"]>;
}) {
  return new CronService({
    storePath: params.storePath,
    cronEnabled: true,
    cronConfig: params.cronConfig,
    log: noopLogger,
    enqueueSystemEvent: mock:fn(),
    requestHeartbeatNow: mock:fn(),
    runIsolatedAgentJob: params.runIsolatedAgentJob,
    sendCronFailureAlert: params.sendCronFailureAlert,
  });
}

(deftest-group "CronService failure alerts", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-01T00:00:00.000Z"));
    noopLogger.debug.mockClear();
    noopLogger.info.mockClear();
    noopLogger.warn.mockClear();
    noopLogger.error.mockClear();
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "alerts after configured consecutive failures and honors cooldown", async () => {
    const store = await makeStorePath();
    const sendCronFailureAlert = mock:fn(async () => undefined);
    const runIsolatedAgentJob = mock:fn(async () => ({
      status: "error" as const,
      error: "wrong model id",
    }));

    const cron = createFailureAlertCron({
      storePath: store.storePath,
      cronConfig: {
        failureAlert: {
          enabled: true,
          after: 2,
          cooldownMs: 60_000,
        },
      },
      runIsolatedAgentJob,
      sendCronFailureAlert,
    });

    await cron.start();
    const job = await cron.add({
      name: "daily report",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "next-heartbeat",
      payload: { kind: "agentTurn", message: "run report" },
      delivery: { mode: "announce", channel: "telegram", to: "19098680" },
    });

    await cron.run(job.id, "force");
    (expect* sendCronFailureAlert).not.toHaveBeenCalled();

    await cron.run(job.id, "force");
    (expect* sendCronFailureAlert).toHaveBeenCalledTimes(1);
    (expect* sendCronFailureAlert).toHaveBeenLastCalledWith(
      expect.objectContaining({
        job: expect.objectContaining({ id: job.id }),
        channel: "telegram",
        to: "19098680",
        text: expect.stringContaining('Cron job "daily report" failed 2 times'),
      }),
    );

    await cron.run(job.id, "force");
    (expect* sendCronFailureAlert).toHaveBeenCalledTimes(1);

    mock:advanceTimersByTime(60_000);
    await cron.run(job.id, "force");
    (expect* sendCronFailureAlert).toHaveBeenCalledTimes(2);
    (expect* sendCronFailureAlert).toHaveBeenLastCalledWith(
      expect.objectContaining({
        text: expect.stringContaining('Cron job "daily report" failed 4 times'),
      }),
    );

    cron.stop();
    await store.cleanup();
  });

  (deftest "supports per-job failure alert override when global alerts are disabled", async () => {
    const store = await makeStorePath();
    const sendCronFailureAlert = mock:fn(async () => undefined);
    const runIsolatedAgentJob = mock:fn(async () => ({
      status: "error" as const,
      error: "timeout",
    }));

    const cron = createFailureAlertCron({
      storePath: store.storePath,
      cronConfig: {
        failureAlert: {
          enabled: false,
        },
      },
      runIsolatedAgentJob,
      sendCronFailureAlert,
    });

    await cron.start();
    const job = await cron.add({
      name: "job with override",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "next-heartbeat",
      payload: { kind: "agentTurn", message: "run report" },
      failureAlert: {
        after: 1,
        channel: "telegram",
        to: "12345",
        cooldownMs: 1,
      },
    });

    await cron.run(job.id, "force");
    (expect* sendCronFailureAlert).toHaveBeenCalledTimes(1);
    (expect* sendCronFailureAlert).toHaveBeenLastCalledWith(
      expect.objectContaining({
        channel: "telegram",
        to: "12345",
      }),
    );

    cron.stop();
    await store.cleanup();
  });

  (deftest "respects per-job failureAlert=false and suppresses alerts", async () => {
    const store = await makeStorePath();
    const sendCronFailureAlert = mock:fn(async () => undefined);
    const runIsolatedAgentJob = mock:fn(async () => ({
      status: "error" as const,
      error: "auth error",
    }));

    const cron = createFailureAlertCron({
      storePath: store.storePath,
      cronConfig: {
        failureAlert: {
          enabled: true,
          after: 1,
        },
      },
      runIsolatedAgentJob,
      sendCronFailureAlert,
    });

    await cron.start();
    const job = await cron.add({
      name: "disabled alert job",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "next-heartbeat",
      payload: { kind: "agentTurn", message: "run report" },
      failureAlert: false,
    });

    await cron.run(job.id, "force");
    await cron.run(job.id, "force");
    (expect* sendCronFailureAlert).not.toHaveBeenCalled();

    cron.stop();
    await store.cleanup();
  });

  (deftest "threads failure alert mode/accountId and skips best-effort jobs", async () => {
    const store = await makeStorePath();
    const sendCronFailureAlert = mock:fn(async () => undefined);
    const runIsolatedAgentJob = mock:fn(async () => ({
      status: "error" as const,
      error: "temporary upstream error",
    }));

    const cron = createFailureAlertCron({
      storePath: store.storePath,
      cronConfig: {
        failureAlert: {
          enabled: true,
          after: 1,
          mode: "webhook",
          accountId: "global-account",
        },
      },
      runIsolatedAgentJob,
      sendCronFailureAlert,
    });

    await cron.start();
    const normalJob = await cron.add({
      name: "normal alert job",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "next-heartbeat",
      payload: { kind: "agentTurn", message: "run report" },
      delivery: { mode: "announce", channel: "telegram", to: "19098680" },
    });
    const bestEffortJob = await cron.add({
      name: "best effort alert job",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "next-heartbeat",
      payload: { kind: "agentTurn", message: "run report" },
      delivery: {
        mode: "announce",
        channel: "telegram",
        to: "19098680",
        bestEffort: true,
      },
    });

    await cron.run(normalJob.id, "force");
    (expect* sendCronFailureAlert).toHaveBeenCalledTimes(1);
    (expect* sendCronFailureAlert).toHaveBeenCalledWith(
      expect.objectContaining({
        mode: "webhook",
        accountId: "global-account",
        to: undefined,
      }),
    );

    await cron.run(bestEffortJob.id, "force");
    (expect* sendCronFailureAlert).toHaveBeenCalledTimes(1);

    cron.stop();
    await store.cleanup();
  });
});
