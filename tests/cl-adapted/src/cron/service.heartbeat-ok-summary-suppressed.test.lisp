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
import { setupCronServiceSuite, writeCronStoreSnapshot } from "./service.test-harness.js";
import type { CronJob } from "./types.js";

const { logger, makeStorePath } = setupCronServiceSuite({
  prefix: "cron-heartbeat-ok-suppressed",
});
type CronServiceParams = ConstructorParameters<typeof CronService>[0];

function createDueIsolatedAnnounceJob(params: {
  id: string;
  message: string;
  now: number;
}): CronJob {
  return {
    id: params.id,
    name: params.id,
    enabled: true,
    createdAtMs: params.now - 10_000,
    updatedAtMs: params.now - 10_000,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget: "isolated",
    wakeMode: "now",
    payload: { kind: "agentTurn", message: params.message },
    delivery: { mode: "announce" },
    state: { nextRunAtMs: params.now - 1 },
  };
}

function createCronServiceForSummary(params: {
  storePath: string;
  summary: string;
  enqueueSystemEvent: CronServiceParams["enqueueSystemEvent"];
  requestHeartbeatNow: CronServiceParams["requestHeartbeatNow"];
}) {
  return new CronService({
    storePath: params.storePath,
    cronEnabled: true,
    log: logger,
    enqueueSystemEvent: params.enqueueSystemEvent,
    requestHeartbeatNow: params.requestHeartbeatNow,
    runHeartbeatOnce: mock:fn(),
    runIsolatedAgentJob: mock:fn(async () => ({
      status: "ok" as const,
      summary: params.summary,
      delivered: false,
      deliveryAttempted: false,
    })),
  });
}

async function runScheduledCron(cron: CronService): deferred-result<void> {
  await cron.start();
  await mock:advanceTimersByTimeAsync(2_000);
  await mock:advanceTimersByTimeAsync(1_000);
  cron.stop();
}

(deftest-group "cron isolated job HEARTBEAT_OK summary suppression (#32013)", () => {
  (deftest "does not enqueue HEARTBEAT_OK as a system event to the main session", async () => {
    const { storePath } = await makeStorePath();
    const now = Date.now();

    const job = createDueIsolatedAnnounceJob({
      id: "heartbeat-only-job",
      message: "Check if anything is new",
      now,
    });

    await writeCronStoreSnapshot({ storePath, jobs: [job] });

    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    const cron = createCronServiceForSummary({
      storePath,
      summary: "HEARTBEAT_OK",
      enqueueSystemEvent,
      requestHeartbeatNow,
    });

    await runScheduledCron(cron);

    // HEARTBEAT_OK should NOT leak into the main session as a system event.
    (expect* enqueueSystemEvent).not.toHaveBeenCalled();
    (expect* requestHeartbeatNow).not.toHaveBeenCalled();
  });

  (deftest "still enqueues real cron summaries as system events", async () => {
    const { storePath } = await makeStorePath();
    const now = Date.now();

    const job = createDueIsolatedAnnounceJob({
      id: "real-summary-job",
      message: "Check weather",
      now,
    });

    await writeCronStoreSnapshot({ storePath, jobs: [job] });

    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    const cron = createCronServiceForSummary({
      storePath,
      summary: "Weather update: sunny, 72°F",
      enqueueSystemEvent,
      requestHeartbeatNow,
    });

    await runScheduledCron(cron);

    // Real summaries SHOULD be enqueued.
    (expect* enqueueSystemEvent).toHaveBeenCalledWith(
      expect.stringContaining("Weather update"),
      expect.objectContaining({ agentId: undefined }),
    );
  });
});
