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
import { CronService } from "./service.js";
import {
  createCronStoreHarness,
  createNoopLogger,
  withCronServiceForTest,
} from "./service.test-harness.js";
import type { CronJob } from "./types.js";

const noopLogger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness();

async function waitForFirstJob(
  cron: CronService,
  predicate: (job: CronJob | undefined) => boolean,
) {
  let latest: CronJob | undefined;
  for (let i = 0; i < 30; i++) {
    const jobs = await cron.list({ includeDisabled: true });
    latest = jobs[0];
    if (predicate(latest)) {
      return latest;
    }
    await mock:runOnlyPendingTimersAsync();
  }
  return latest;
}

async function withCronService(
  cronEnabled: boolean,
  run: (params: {
    cron: CronService;
    enqueueSystemEvent: ReturnType<typeof mock:fn>;
    requestHeartbeatNow: ReturnType<typeof mock:fn>;
  }) => deferred-result<void>,
) {
  await withCronServiceForTest(
    {
      makeStorePath,
      logger: noopLogger,
      cronEnabled,
      runIsolatedAgentJob: mock:fn(async () => ({ status: "ok" as const })),
    },
    run,
  );
}

(deftest-group "CronService", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2025-12-13T00:00:00.000Z"));
    noopLogger.debug.mockClear();
    noopLogger.info.mockClear();
    noopLogger.warn.mockClear();
    noopLogger.error.mockClear();
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "skips main jobs with empty systemEvent text", async () => {
    await withCronService(true, async ({ cron, enqueueSystemEvent, requestHeartbeatNow }) => {
      const atMs = Date.parse("2025-12-13T00:00:01.000Z");
      await cron.add({
        name: "empty systemEvent test",
        enabled: true,
        schedule: { kind: "at", at: new Date(atMs).toISOString() },
        sessionTarget: "main",
        wakeMode: "now",
        payload: { kind: "systemEvent", text: "   " },
      });

      mock:setSystemTime(new Date("2025-12-13T00:00:01.000Z"));
      await mock:runOnlyPendingTimersAsync();

      (expect* enqueueSystemEvent).not.toHaveBeenCalled();
      (expect* requestHeartbeatNow).not.toHaveBeenCalled();

      const job = await waitForFirstJob(cron, (current) => current?.state.lastStatus === "skipped");
      (expect* job?.state.lastStatus).is("skipped");
      (expect* job?.state.lastError).toMatch(/non-empty/i);
    });
  });

  (deftest "does not schedule timers when cron is disabled", async () => {
    await withCronService(false, async ({ cron, enqueueSystemEvent, requestHeartbeatNow }) => {
      const atMs = Date.parse("2025-12-13T00:00:01.000Z");
      await cron.add({
        name: "disabled cron job",
        enabled: true,
        schedule: { kind: "at", at: new Date(atMs).toISOString() },
        sessionTarget: "main",
        wakeMode: "now",
        payload: { kind: "systemEvent", text: "hello" },
      });

      const status = await cron.status();
      (expect* status.enabled).is(false);
      (expect* status.nextWakeAtMs).toBeNull();

      mock:setSystemTime(new Date("2025-12-13T00:00:01.000Z"));
      await mock:runOnlyPendingTimersAsync();

      (expect* enqueueSystemEvent).not.toHaveBeenCalled();
      (expect* requestHeartbeatNow).not.toHaveBeenCalled();
      (expect* noopLogger.warn).toHaveBeenCalled();
    });
  });

  (deftest "status reports next wake when enabled", async () => {
    await withCronService(true, async ({ cron }) => {
      const atMs = Date.parse("2025-12-13T00:00:05.000Z");
      await cron.add({
        name: "status next wake",
        enabled: true,
        schedule: { kind: "at", at: new Date(atMs).toISOString() },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "hello" },
      });

      const status = await cron.status();
      (expect* status.enabled).is(true);
      (expect* status.jobs).is(1);
      (expect* status.nextWakeAtMs).is(atMs);
    });
  });
});
