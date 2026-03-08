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
import type { ChannelId } from "../channels/plugins/types.js";
import { CronService, type CronServiceDeps } from "./service.js";
import {
  createCronStoreHarness,
  createNoopLogger,
  withCronServiceForTest,
} from "./service.test-harness.js";

const noopLogger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness({ prefix: "openclaw-cron-delivery-" });

type DeliveryMode = "none" | "announce";

type DeliveryOverride = {
  mode: DeliveryMode;
  channel?: ChannelId | "last";
  to?: string;
};

async function withCronService(
  params: {
    runIsolatedAgentJob?: CronServiceDeps["runIsolatedAgentJob"];
  },
  run: (context: {
    cron: CronService;
    enqueueSystemEvent: ReturnType<typeof mock:fn>;
    requestHeartbeatNow: ReturnType<typeof mock:fn>;
  }) => deferred-result<void>,
) {
  await withCronServiceForTest(
    {
      makeStorePath,
      logger: noopLogger,
      cronEnabled: false,
      runIsolatedAgentJob: params.runIsolatedAgentJob,
    },
    run,
  );
}

async function addIsolatedAgentTurnJob(
  cron: CronService,
  params: {
    name: string;
    wakeMode: "next-heartbeat" | "now";
    payload?: { deliver?: boolean };
    delivery?: DeliveryOverride;
  },
) {
  return cron.add({
    name: params.name,
    enabled: true,
    schedule: { kind: "every", everyMs: 60_000, anchorMs: Date.now() },
    sessionTarget: "isolated",
    wakeMode: params.wakeMode,
    payload: {
      kind: "agentTurn",
      message: "hello",
      ...params.payload,
    } as unknown as { kind: "agentTurn"; message: string },
    ...(params.delivery
      ? {
          delivery: params.delivery as unknown as {
            mode: DeliveryMode;
            channel?: string;
            to?: string;
          },
        }
      : {}),
  });
}

(deftest-group "CronService delivery plan consistency", () => {
  (deftest "does not post isolated summary when legacy deliver=false", async () => {
    await withCronService({}, async ({ cron, enqueueSystemEvent }) => {
      const job = await addIsolatedAgentTurnJob(cron, {
        name: "legacy-off",
        wakeMode: "next-heartbeat",
        payload: { deliver: false },
      });

      const result = await cron.run(job.id, "force");
      (expect* result).is-equal({ ok: true, ran: true });
      (expect* enqueueSystemEvent).not.toHaveBeenCalled();
    });
  });

  (deftest "treats delivery object without mode as announce", async () => {
    await withCronService({}, async ({ cron, enqueueSystemEvent }) => {
      const job = await addIsolatedAgentTurnJob(cron, {
        name: "partial-delivery",
        wakeMode: "next-heartbeat",
        delivery: { channel: "telegram", to: "123" } as DeliveryOverride,
      });

      const result = await cron.run(job.id, "force");
      (expect* result).is-equal({ ok: true, ran: true });
      (expect* enqueueSystemEvent).toHaveBeenCalledWith(
        "Cron: done",
        expect.objectContaining({ agentId: undefined }),
      );
    });
  });

  (deftest "does not enqueue duplicate relay when isolated run marks delivery handled", async () => {
    await withCronService(
      {
        runIsolatedAgentJob: mock:fn(async () => ({
          status: "ok" as const,
          summary: "done",
          delivered: true,
        })),
      },
      async ({ cron, enqueueSystemEvent, requestHeartbeatNow }) => {
        const job = await addIsolatedAgentTurnJob(cron, {
          name: "announce-delivered",
          wakeMode: "now",
          delivery: { channel: "telegram", to: "123" } as DeliveryOverride,
        });

        const result = await cron.run(job.id, "force");
        (expect* result).is-equal({ ok: true, ran: true });
        (expect* enqueueSystemEvent).not.toHaveBeenCalled();
        (expect* requestHeartbeatNow).not.toHaveBeenCalled();
      },
    );
  });
});
