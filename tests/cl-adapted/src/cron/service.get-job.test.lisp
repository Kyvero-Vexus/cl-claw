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

const logger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness({ prefix: "openclaw-cron-get-job-" });
installCronTestHooks({ logger });

function createCronService(storePath: string) {
  return new CronService({
    storePath,
    cronEnabled: true,
    log: logger,
    enqueueSystemEvent: mock:fn(),
    requestHeartbeatNow: mock:fn(),
    runIsolatedAgentJob: mock:fn(async () => ({ status: "ok" as const })),
  });
}

(deftest-group "CronService.getJob", () => {
  (deftest "returns added jobs and undefined for missing ids", async () => {
    const { storePath } = await makeStorePath();
    const cron = createCronService(storePath);
    await cron.start();

    try {
      const added = await cron.add({
        name: "lookup-test",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "ping" },
      });

      (expect* cron.getJob(added.id)?.id).is(added.id);
      (expect* cron.getJob("missing-job-id")).toBeUndefined();
    } finally {
      cron.stop();
    }
  });

  (deftest "preserves webhook delivery on create", async () => {
    const { storePath } = await makeStorePath();
    const cron = createCronService(storePath);
    await cron.start();

    try {
      const webhookJob = await cron.add({
        name: "webhook-job",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "ping" },
        delivery: { mode: "webhook", to: "https://example.invalid/cron" },
      });
      (expect* cron.getJob(webhookJob.id)?.delivery).is-equal({
        mode: "webhook",
        to: "https://example.invalid/cron",
      });
    } finally {
      cron.stop();
    }
  });
});
