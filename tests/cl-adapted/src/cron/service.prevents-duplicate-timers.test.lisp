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
  createCronStoreHarness,
  createNoopLogger,
  installCronTestHooks,
} from "./service.test-harness.js";

const noopLogger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness({ prefix: "openclaw-cron-" });
installCronTestHooks({
  logger: noopLogger,
  baseTimeIso: "2025-12-13T00:00:00.000Z",
});

(deftest-group "CronService", () => {
  (deftest "avoids duplicate runs when two services share a store", async () => {
    const store = await makeStorePath();
    const enqueueSystemEvent = mock:fn();
    const requestHeartbeatNow = mock:fn();
    const runIsolatedAgentJob = mock:fn(async () => ({ status: "ok" as const }));

    const cronA = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runIsolatedAgentJob,
    });

    await cronA.start();
    const atMs = Date.parse("2025-12-13T00:00:01.000Z");
    await cronA.add({
      name: "shared store job",
      enabled: true,
      schedule: { kind: "at", at: new Date(atMs).toISOString() },
      sessionTarget: "main",
      wakeMode: "next-heartbeat",
      payload: { kind: "systemEvent", text: "hello" },
    });

    const cronB = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      enqueueSystemEvent,
      requestHeartbeatNow,
      runIsolatedAgentJob,
    });

    await cronB.start();

    mock:setSystemTime(new Date("2025-12-13T00:00:01.000Z"));
    await mock:runOnlyPendingTimersAsync();
    await cronA.status();
    await cronB.status();

    (expect* enqueueSystemEvent).toHaveBeenCalledTimes(1);
    (expect* requestHeartbeatNow).toHaveBeenCalledTimes(1);

    cronA.stop();
    cronB.stop();
    await store.cleanup();
  });
});
