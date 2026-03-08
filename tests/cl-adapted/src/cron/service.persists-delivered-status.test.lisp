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
  createFinishedBarrier,
  createStartedCronServiceWithFinishedBarrier,
  createCronStoreHarness,
  createNoopLogger,
  installCronTestHooks,
} from "./service.test-harness.js";

const noopLogger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness();
installCronTestHooks({ logger: noopLogger });

type CronAddInput = Parameters<CronService["add"]>[0];

function buildIsolatedAgentTurnJob(name: string): CronAddInput {
  return {
    name,
    enabled: true,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget: "isolated",
    wakeMode: "next-heartbeat",
    payload: { kind: "agentTurn", message: "test" },
    delivery: { mode: "none" },
  };
}

function buildMainSessionSystemEventJob(name: string): CronAddInput {
  return {
    name,
    enabled: true,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget: "main",
    wakeMode: "next-heartbeat",
    payload: { kind: "systemEvent", text: "tick" },
  };
}

function createIsolatedCronWithFinishedBarrier(params: {
  storePath: string;
  delivered?: boolean;
  onFinished?: (evt: { jobId: string; delivered?: boolean; deliveryStatus?: string }) => void;
}) {
  const finished = createFinishedBarrier();
  const cron = new CronService({
    storePath: params.storePath,
    cronEnabled: true,
    log: noopLogger,
    enqueueSystemEvent: mock:fn(),
    requestHeartbeatNow: mock:fn(),
    runIsolatedAgentJob: mock:fn(async () => ({
      status: "ok" as const,
      summary: "done",
      ...(params.delivered === undefined ? {} : { delivered: params.delivered }),
    })),
    onEvent: (evt) => {
      if (evt.action === "finished") {
        params.onFinished?.({
          jobId: evt.jobId,
          delivered: evt.delivered,
          deliveryStatus: evt.deliveryStatus,
        });
      }
      finished.onEvent(evt);
    },
  });
  return { cron, finished };
}

async function runSingleJobAndReadState(params: {
  cron: CronService;
  finished: ReturnType<typeof createFinishedBarrier>;
  job: CronAddInput;
}) {
  const job = await params.cron.add(params.job);
  mock:setSystemTime(new Date(job.state.nextRunAtMs! + 5));
  await mock:runOnlyPendingTimersAsync();
  await params.finished.waitForOk(job.id);

  const jobs = await params.cron.list({ includeDisabled: true });
  return { job, updated: jobs.find((entry) => entry.id === job.id) };
}

function expectSuccessfulCronRun(
  updated:
    | {
        state: {
          lastStatus?: string;
          lastRunStatus?: string;
          [key: string]: unknown;
        };
      }
    | undefined,
) {
  (expect* updated?.state.lastStatus).is("ok");
  (expect* updated?.state.lastRunStatus).is("ok");
}

function expectDeliveryNotRequested(
  updated:
    | {
        state: {
          lastDelivered?: boolean;
          lastDeliveryStatus?: string;
          lastDeliveryError?: string;
        };
      }
    | undefined,
) {
  expectSuccessfulCronRun(updated);
  (expect* updated?.state.lastDelivered).toBeUndefined();
  (expect* updated?.state.lastDeliveryStatus).is("not-requested");
  (expect* updated?.state.lastDeliveryError).toBeUndefined();
}

async function runIsolatedJobAndReadState(params: {
  job: CronAddInput;
  delivered?: boolean;
  onFinished?: (evt: { jobId: string; delivered?: boolean; deliveryStatus?: string }) => void;
}) {
  const store = await makeStorePath();
  const { cron, finished } = createIsolatedCronWithFinishedBarrier({
    storePath: store.storePath,
    ...(params.delivered !== undefined ? { delivered: params.delivered } : {}),
    ...(params.onFinished ? { onFinished: params.onFinished } : {}),
  });

  await cron.start();
  try {
    const { updated } = await runSingleJobAndReadState({
      cron,
      finished,
      job: params.job,
    });
    return updated;
  } finally {
    cron.stop();
  }
}

(deftest-group "CronService persists delivered status", () => {
  (deftest "persists lastDelivered=true when isolated job reports delivered", async () => {
    const updated = await runIsolatedJobAndReadState({
      job: buildIsolatedAgentTurnJob("delivered-true"),
      delivered: true,
    });
    expectSuccessfulCronRun(updated);
    (expect* updated?.state.lastDelivered).is(true);
    (expect* updated?.state.lastDeliveryStatus).is("delivered");
    (expect* updated?.state.lastDeliveryError).toBeUndefined();
  });

  (deftest "persists lastDelivered=false when isolated job explicitly reports not delivered", async () => {
    const updated = await runIsolatedJobAndReadState({
      job: buildIsolatedAgentTurnJob("delivered-false"),
      delivered: false,
    });
    expectSuccessfulCronRun(updated);
    (expect* updated?.state.lastDelivered).is(false);
    (expect* updated?.state.lastDeliveryStatus).is("not-delivered");
    (expect* updated?.state.lastDeliveryError).toBeUndefined();
  });

  (deftest "persists not-requested delivery state when delivery is not configured", async () => {
    const updated = await runIsolatedJobAndReadState({
      job: buildIsolatedAgentTurnJob("no-delivery"),
    });
    expectDeliveryNotRequested(updated);
  });

  (deftest "persists unknown delivery state when delivery is requested but the runner omits delivered", async () => {
    const updated = await runIsolatedJobAndReadState({
      job: {
        ...buildIsolatedAgentTurnJob("delivery-unknown"),
        delivery: { mode: "announce", channel: "telegram", to: "123" },
      },
    });
    expectSuccessfulCronRun(updated);
    (expect* updated?.state.lastDelivered).toBeUndefined();
    (expect* updated?.state.lastDeliveryStatus).is("unknown");
    (expect* updated?.state.lastDeliveryError).toBeUndefined();
  });

  (deftest "does not set lastDelivered for main session jobs", async () => {
    const store = await makeStorePath();
    const { cron, enqueueSystemEvent, finished } = createStartedCronServiceWithFinishedBarrier({
      storePath: store.storePath,
      logger: noopLogger,
    });

    await cron.start();
    const { updated } = await runSingleJobAndReadState({
      cron,
      finished,
      job: buildMainSessionSystemEventJob("main-session"),
    });

    expectDeliveryNotRequested(updated);
    (expect* enqueueSystemEvent).toHaveBeenCalled();

    cron.stop();
  });

  (deftest "emits delivered in the finished event", async () => {
    let capturedEvent: { jobId: string; delivered?: boolean; deliveryStatus?: string } | undefined;
    await runIsolatedJobAndReadState({
      job: buildIsolatedAgentTurnJob("event-test"),
      delivered: true,
      onFinished: (evt) => {
        capturedEvent = evt;
      },
    });

    (expect* capturedEvent).toBeDefined();
    (expect* capturedEvent?.delivered).is(true);
    (expect* capturedEvent?.deliveryStatus).is("delivered");
  });
});
