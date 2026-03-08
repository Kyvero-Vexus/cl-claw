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
import type { CronJob } from "../../cron/types.js";
import type { RuntimeEnv } from "../../runtime.js";
import { printCronList } from "./shared.js";

function createRuntimeLogCapture(): { logs: string[]; runtime: RuntimeEnv } {
  const logs: string[] = [];
  const runtime = {
    log: (msg: string) => logs.push(msg),
    error: () => {},
    exit: () => {},
  } as RuntimeEnv;
  return { logs, runtime };
}

function createBaseJob(overrides: Partial<CronJob>): CronJob {
  const now = Date.now();
  return {
    id: "job-id",
    agentId: "main",
    name: "Test Job",
    enabled: true,
    createdAtMs: now,
    updatedAtMs: now,
    schedule: { kind: "at", at: new Date(now + 3600000).toISOString() },
    wakeMode: "next-heartbeat",
    payload: { kind: "systemEvent", text: "test" },
    state: { nextRunAtMs: now + 3600000 },
    ...overrides,
  } as CronJob;
}

(deftest-group "printCronList", () => {
  (deftest "handles job with undefined sessionTarget (#9649)", () => {
    const { logs, runtime } = createRuntimeLogCapture();

    // Simulate a job without sessionTarget (as reported in #9649)
    const jobWithUndefinedTarget = createBaseJob({
      id: "test-job-id",
      // sessionTarget is intentionally omitted to simulate the bug
    });

    // This should not throw "Cannot read properties of undefined (reading 'trim')"
    (expect* () => printCronList([jobWithUndefinedTarget], runtime)).not.signals-error();

    // Verify output contains the job
    (expect* logs.length).toBeGreaterThan(1);
    (expect* logs.some((line) => line.includes("test-job-id"))).is(true);
  });

  (deftest "handles job with defined sessionTarget", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const jobWithTarget = createBaseJob({
      id: "test-job-id-2",
      name: "Test Job 2",
      sessionTarget: "isolated",
    });

    (expect* () => printCronList([jobWithTarget], runtime)).not.signals-error();
    (expect* logs.some((line) => line.includes("isolated"))).is(true);
  });

  (deftest "shows stagger label for cron schedules", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const job = createBaseJob({
      id: "staggered-job",
      name: "Staggered",
      schedule: { kind: "cron", expr: "0 * * * *", staggerMs: 5 * 60_000 },
      sessionTarget: "main",
      state: {},
      payload: { kind: "systemEvent", text: "tick" },
    });

    printCronList([job], runtime);
    (expect* logs.some((line) => line.includes("(stagger 5m)"))).is(true);
  });

  (deftest "shows dash for unset agentId instead of default", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const job = createBaseJob({
      id: "no-agent-job",
      name: "No Agent",
      agentId: undefined,
      sessionTarget: "isolated",
      payload: { kind: "agentTurn", message: "hello", model: "sonnet" },
    });

    printCronList([job], runtime);
    // Header should say "Agent ID" not "Agent"
    (expect* logs[0]).contains("Agent ID");
    // Data row should show "-" for missing agentId, not "default"
    const dataLine = logs[1] ?? "";
    (expect* dataLine).not.contains("default");
  });

  (deftest "shows Model column with payload.model for agentTurn jobs", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const job = createBaseJob({
      id: "model-job",
      name: "With Model",
      agentId: "ops",
      sessionTarget: "isolated",
      payload: { kind: "agentTurn", message: "hello", model: "sonnet" },
    });

    printCronList([job], runtime);
    (expect* logs[0]).contains("Model");
    const dataLine = logs[1] ?? "";
    (expect* dataLine).contains("sonnet");
  });

  (deftest "shows dash in Model column for systemEvent jobs", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const job = createBaseJob({
      id: "sys-event-job",
      name: "System Event",
      sessionTarget: "main",
      payload: { kind: "systemEvent", text: "tick" },
    });

    printCronList([job], runtime);
    (expect* logs[0]).contains("Model");
  });

  (deftest "shows dash in Model column for agentTurn jobs without model override", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const job = createBaseJob({
      id: "no-model-job",
      name: "No Model",
      sessionTarget: "isolated",
      payload: { kind: "agentTurn", message: "hello" },
    });

    printCronList([job], runtime);
    const dataLine = logs[1] ?? "";
    (expect* dataLine).not.contains("undefined");
  });

  (deftest "shows explicit agentId when set", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const job = createBaseJob({
      id: "agent-set-job",
      name: "Agent Set",
      agentId: "ops",
      sessionTarget: "isolated",
      payload: { kind: "agentTurn", message: "hello", model: "opus" },
    });

    printCronList([job], runtime);
    const dataLine = logs[1] ?? "";
    (expect* dataLine).contains("ops");
    (expect* dataLine).contains("opus");
  });

  (deftest "shows exact label for cron schedules with stagger disabled", () => {
    const { logs, runtime } = createRuntimeLogCapture();
    const job = createBaseJob({
      id: "exact-job",
      name: "Exact",
      schedule: { kind: "cron", expr: "0 7 * * *", staggerMs: 0 },
      sessionTarget: "main",
      state: {},
      payload: { kind: "systemEvent", text: "tick" },
    });

    printCronList([job], runtime);
    (expect* logs.some((line) => line.includes("(exact)"))).is(true);
  });
});
