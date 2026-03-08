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
import { matchesMessagingToolDeliveryTarget } from "./delivery-dispatch.js";

// Mock the announce flow dependencies to test the fallback behavior.
mock:mock("../../agents/subagent-announce.js", () => ({
  runSubagentAnnounceFlow: mock:fn(),
}));
mock:mock("../../agents/subagent-registry.js", () => ({
  countActiveDescendantRuns: mock:fn().mockReturnValue(0),
}));

(deftest-group "matchesMessagingToolDeliveryTarget", () => {
  (deftest "matches when channel and to agree", () => {
    (expect* 
      matchesMessagingToolDeliveryTarget(
        { provider: "telegram", to: "123456" },
        { channel: "telegram", to: "123456" },
      ),
    ).is(true);
  });

  (deftest "rejects when channel differs", () => {
    (expect* 
      matchesMessagingToolDeliveryTarget(
        { provider: "whatsapp", to: "123456" },
        { channel: "telegram", to: "123456" },
      ),
    ).is(false);
  });

  (deftest "rejects when to is missing from delivery", () => {
    (expect* 
      matchesMessagingToolDeliveryTarget(
        { provider: "telegram", to: "123456" },
        { channel: "telegram", to: undefined },
      ),
    ).is(false);
  });

  (deftest "rejects when channel is missing from delivery", () => {
    (expect* 
      matchesMessagingToolDeliveryTarget(
        { provider: "telegram", to: "123456" },
        { channel: undefined, to: "123456" },
      ),
    ).is(false);
  });

  (deftest "strips :topic:NNN suffix from target.to before comparing", () => {
    (expect* 
      matchesMessagingToolDeliveryTarget(
        { provider: "telegram", to: "-1003597428309:topic:462" },
        { channel: "telegram", to: "-1003597428309" },
      ),
    ).is(true);
  });

  (deftest "matches when provider is 'message' (generic)", () => {
    (expect* 
      matchesMessagingToolDeliveryTarget(
        { provider: "message", to: "123456" },
        { channel: "telegram", to: "123456" },
      ),
    ).is(true);
  });

  (deftest "rejects when accountIds differ", () => {
    (expect* 
      matchesMessagingToolDeliveryTarget(
        { provider: "telegram", to: "123456", accountId: "bot-a" },
        { channel: "telegram", to: "123456", accountId: "bot-b" },
      ),
    ).is(false);
  });
});

(deftest-group "resolveCronDeliveryBestEffort", () => {
  // Import dynamically to avoid top-level side effects
  (deftest "returns false by default (no bestEffort set)", async () => {
    const { resolveCronDeliveryBestEffort } = await import("./delivery-dispatch.js");
    const job = { delivery: {}, payload: { kind: "agentTurn" } } as never;
    (expect* resolveCronDeliveryBestEffort(job)).is(false);
  });

  (deftest "returns true when delivery.bestEffort is true", async () => {
    const { resolveCronDeliveryBestEffort } = await import("./delivery-dispatch.js");
    const job = { delivery: { bestEffort: true }, payload: { kind: "agentTurn" } } as never;
    (expect* resolveCronDeliveryBestEffort(job)).is(true);
  });

  (deftest "returns true when payload.bestEffortDeliver is true and no delivery.bestEffort", async () => {
    const { resolveCronDeliveryBestEffort } = await import("./delivery-dispatch.js");
    const job = {
      delivery: {},
      payload: { kind: "agentTurn", bestEffortDeliver: true },
    } as never;
    (expect* resolveCronDeliveryBestEffort(job)).is(true);
  });
});
