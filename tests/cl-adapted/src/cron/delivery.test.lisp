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
import { resolveCronDeliveryPlan, resolveFailureDestination } from "./delivery.js";
import type { CronJob } from "./types.js";

function makeJob(overrides: Partial<CronJob>): CronJob {
  const now = Date.now();
  return {
    id: "job-1",
    name: "test",
    enabled: true,
    createdAtMs: now,
    updatedAtMs: now,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget: "isolated",
    wakeMode: "next-heartbeat",
    payload: { kind: "agentTurn", message: "hello" },
    state: {},
    ...overrides,
  };
}

(deftest-group "resolveCronDeliveryPlan", () => {
  (deftest "defaults to announce when delivery object has no mode", () => {
    const plan = resolveCronDeliveryPlan(
      makeJob({
        delivery: { channel: "telegram", to: "123", mode: undefined as never },
      }),
    );
    (expect* plan.mode).is("announce");
    (expect* plan.requested).is(true);
    (expect* plan.channel).is("telegram");
    (expect* plan.to).is("123");
  });

  (deftest "respects legacy payload deliver=false", () => {
    const plan = resolveCronDeliveryPlan(
      makeJob({
        delivery: undefined,
        payload: { kind: "agentTurn", message: "hello", deliver: false },
      }),
    );
    (expect* plan.mode).is("none");
    (expect* plan.requested).is(false);
  });

  (deftest "resolves mode=none with requested=false and no channel (#21808)", () => {
    const plan = resolveCronDeliveryPlan(
      makeJob({
        delivery: { mode: "none", to: "telegram:123" },
      }),
    );
    (expect* plan.mode).is("none");
    (expect* plan.requested).is(false);
    (expect* plan.channel).toBeUndefined();
    (expect* plan.to).is("telegram:123");
  });

  (deftest "resolves webhook mode without channel routing", () => {
    const plan = resolveCronDeliveryPlan(
      makeJob({
        delivery: { mode: "webhook", to: "https://example.invalid/cron" },
      }),
    );
    (expect* plan.mode).is("webhook");
    (expect* plan.requested).is(false);
    (expect* plan.channel).toBeUndefined();
    (expect* plan.to).is("https://example.invalid/cron");
  });

  (deftest "threads delivery.accountId when explicitly configured", () => {
    const plan = resolveCronDeliveryPlan(
      makeJob({
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "123",
          accountId: " bot-a ",
        },
      }),
    );
    (expect* plan.mode).is("announce");
    (expect* plan.requested).is(true);
    (expect* plan.channel).is("telegram");
    (expect* plan.to).is("123");
    (expect* plan.accountId).is("bot-a");
  });
});

(deftest-group "resolveFailureDestination", () => {
  (deftest "merges global defaults with job-level overrides", () => {
    const plan = resolveFailureDestination(
      makeJob({
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "111",
          failureDestination: { channel: "signal", mode: "announce" },
        },
      }),
      {
        channel: "telegram",
        to: "222",
        mode: "announce",
        accountId: "global-account",
      },
    );
    (expect* plan).is-equal({
      mode: "announce",
      channel: "signal",
      to: "222",
      accountId: "global-account",
    });
  });

  (deftest "returns null for webhook mode without destination URL", () => {
    const plan = resolveFailureDestination(
      makeJob({
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "111",
          failureDestination: { mode: "webhook" },
        },
      }),
      undefined,
    );
    (expect* plan).toBeNull();
  });

  (deftest "returns null when failure destination matches primary delivery target", () => {
    const plan = resolveFailureDestination(
      makeJob({
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "111",
          accountId: "bot-a",
          failureDestination: {
            mode: "announce",
            channel: "telegram",
            to: "111",
            accountId: "bot-a",
          },
        },
      }),
      undefined,
    );
    (expect* plan).toBeNull();
  });

  (deftest "allows job-level failure destination fields to clear inherited global values", () => {
    const plan = resolveFailureDestination(
      makeJob({
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "111",
          failureDestination: {
            mode: "announce",
            channel: undefined as never,
            to: undefined as never,
            accountId: undefined as never,
          },
        },
      }),
      {
        channel: "signal",
        to: "group-abc",
        accountId: "global-account",
        mode: "announce",
      },
    );
    (expect* plan).is-equal({
      mode: "announce",
      channel: "last",
      to: undefined,
      accountId: undefined,
    });
  });
});
