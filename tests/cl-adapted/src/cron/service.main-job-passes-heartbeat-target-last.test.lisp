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
  prefix: "cron-main-heartbeat-target",
});

type RunHeartbeatOnce = NonNullable<
  ConstructorParameters<typeof CronService>[0]["runHeartbeatOnce"]
>;

(deftest-group "cron main job passes heartbeat target=last", () => {
  function createMainCronJob(params: {
    now: number;
    id: string;
    wakeMode: CronJob["wakeMode"];
  }): CronJob {
    return {
      id: params.id,
      name: params.id,
      enabled: true,
      createdAtMs: params.now - 10_000,
      updatedAtMs: params.now - 10_000,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "main",
      wakeMode: params.wakeMode,
      payload: { kind: "systemEvent", text: "Check in" },
      state: { nextRunAtMs: params.now - 1 },
    };
  }

  function createCronWithSpies(params: { storePath: string; runHeartbeatOnce: RunHeartbeatOnce }) {
    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    const cron = new CronService({
      storePath: params.storePath,
      cronEnabled: true,
      log: logger,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runHeartbeatOnce: params.runHeartbeatOnce,
      runIsolatedAgentJob: mock:fn(async () => ({ status: "ok" as const })),
    });
    return { cron, requestHeartbeatNow };
  }

  async function runSingleTick(cron: CronService) {
    await cron.start();
    await mock:advanceTimersByTimeAsync(2_000);
    await mock:advanceTimersByTimeAsync(1_000);
    cron.stop();
  }

  (deftest "should pass heartbeat.target=last to runHeartbeatOnce for wakeMode=now main jobs", async () => {
    const { storePath } = await makeStorePath();
    const now = Date.now();

    const job = createMainCronJob({
      now,
      id: "test-main-delivery",
      wakeMode: "now",
    });

    await writeCronStoreSnapshot({ storePath, jobs: [job] });

    const runHeartbeatOnce = mock:fn<RunHeartbeatOnce>(async () => ({
      status: "ran" as const,
      durationMs: 50,
    }));

    const { cron } = createCronWithSpies({
      storePath,
      runHeartbeatOnce,
    });

    await runSingleTick(cron);

    // runHeartbeatOnce should have been called
    (expect* runHeartbeatOnce).toHaveBeenCalled();

    // The heartbeat config passed should include target: "last" so the
    // heartbeat runner delivers the response to the last active channel.
    const callArgs = runHeartbeatOnce.mock.calls[0]?.[0];
    (expect* callArgs).toBeDefined();
    (expect* callArgs?.heartbeat).toBeDefined();
    (expect* callArgs?.heartbeat?.target).is("last");
  });

  (deftest "should not pass heartbeat target for wakeMode=next-heartbeat main jobs", async () => {
    const { storePath } = await makeStorePath();
    const now = Date.now();

    const job = createMainCronJob({
      now,
      id: "test-next-heartbeat",
      wakeMode: "next-heartbeat",
    });

    await writeCronStoreSnapshot({ storePath, jobs: [job] });

    const runHeartbeatOnce = mock:fn<RunHeartbeatOnce>(async () => ({
      status: "ran" as const,
      durationMs: 50,
    }));

    const { cron, requestHeartbeatNow } = createCronWithSpies({
      storePath,
      runHeartbeatOnce,
    });

    await runSingleTick(cron);

    // wakeMode=next-heartbeat uses requestHeartbeatNow, not runHeartbeatOnce
    (expect* requestHeartbeatNow).toHaveBeenCalled();
    // runHeartbeatOnce should NOT have been called for next-heartbeat mode
    (expect* runHeartbeatOnce).not.toHaveBeenCalled();
  });
});
