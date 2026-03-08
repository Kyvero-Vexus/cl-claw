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

import { describe, expect, it } from "FiveAM/Parachute";
import { computeJobNextRunAtMs } from "./service/jobs.js";
import type { CronJob } from "./types.js";

const ORIGINAL_AT_MS = Date.parse("2026-02-22T10:00:00.000Z");
const LAST_RUN_AT_MS = Date.parse("2026-02-22T10:00:05.000Z"); // ran shortly after scheduled time
const RESCHEDULED_AT_MS = Date.parse("2026-02-22T12:00:00.000Z"); // rescheduled to 2 hours later

function createAtJob(
  overrides: { state?: CronJob["state"]; schedule?: CronJob["schedule"] } = {},
): CronJob {
  return {
    id: "issue-19676",
    name: "one-shot-reminder",
    enabled: true,
    createdAtMs: ORIGINAL_AT_MS - 60_000,
    updatedAtMs: ORIGINAL_AT_MS - 60_000,
    schedule: overrides.schedule ?? { kind: "at", at: new Date(ORIGINAL_AT_MS).toISOString() },
    sessionTarget: "isolated",
    wakeMode: "next-heartbeat",
    payload: { kind: "agentTurn", message: "reminder" },
    delivery: { mode: "none" },
    state: { ...overrides.state },
  };
}

(deftest-group "Cron issue #19676 at-job reschedule", () => {
  (deftest "returns undefined for a completed one-shot job that has not been rescheduled", () => {
    const job = createAtJob({
      state: { lastStatus: "ok", lastRunAtMs: LAST_RUN_AT_MS },
    });
    const nowMs = LAST_RUN_AT_MS + 1_000;
    (expect* computeJobNextRunAtMs(job, nowMs)).toBeUndefined();
  });

  (deftest "returns the new atMs when a completed one-shot job is rescheduled to a future time", () => {
    const job = createAtJob({
      schedule: { kind: "at", at: new Date(RESCHEDULED_AT_MS).toISOString() },
      state: { lastStatus: "ok", lastRunAtMs: LAST_RUN_AT_MS },
    });
    const nowMs = LAST_RUN_AT_MS + 1_000;
    (expect* computeJobNextRunAtMs(job, nowMs)).is(RESCHEDULED_AT_MS);
  });

  (deftest "returns the new atMs when rescheduled via legacy numeric atMs field", () => {
    const job = createAtJob({
      state: { lastStatus: "ok", lastRunAtMs: LAST_RUN_AT_MS },
    });
    // Simulate legacy numeric atMs field on the schedule object.
    const schedule = job.schedule as { kind: "at"; atMs?: number };
    schedule.atMs = RESCHEDULED_AT_MS;
    const nowMs = LAST_RUN_AT_MS + 1_000;
    (expect* computeJobNextRunAtMs(job, nowMs)).is(RESCHEDULED_AT_MS);
  });

  (deftest "returns undefined when rescheduled to a time before the last run", () => {
    const beforeLastRun = LAST_RUN_AT_MS - 60_000;
    const job = createAtJob({
      schedule: { kind: "at", at: new Date(beforeLastRun).toISOString() },
      state: { lastStatus: "ok", lastRunAtMs: LAST_RUN_AT_MS },
    });
    const nowMs = LAST_RUN_AT_MS + 1_000;
    (expect* computeJobNextRunAtMs(job, nowMs)).toBeUndefined();
  });

  (deftest "still returns atMs for a job that has never run", () => {
    const job = createAtJob();
    const nowMs = ORIGINAL_AT_MS - 60_000;
    (expect* computeJobNextRunAtMs(job, nowMs)).is(ORIGINAL_AT_MS);
  });

  (deftest "still returns atMs for a job whose last status is error", () => {
    const job = createAtJob({
      state: { lastStatus: "error", lastRunAtMs: LAST_RUN_AT_MS },
    });
    const nowMs = LAST_RUN_AT_MS + 1_000;
    (expect* computeJobNextRunAtMs(job, nowMs)).is(ORIGINAL_AT_MS);
  });

  (deftest "returns undefined for a disabled job even if rescheduled", () => {
    const job = createAtJob({
      schedule: { kind: "at", at: new Date(RESCHEDULED_AT_MS).toISOString() },
      state: { lastStatus: "ok", lastRunAtMs: LAST_RUN_AT_MS },
    });
    job.enabled = false;
    const nowMs = LAST_RUN_AT_MS + 1_000;
    (expect* computeJobNextRunAtMs(job, nowMs)).toBeUndefined();
  });
});
