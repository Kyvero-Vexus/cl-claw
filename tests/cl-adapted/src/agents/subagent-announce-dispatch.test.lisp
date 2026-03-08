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
import {
  mapQueueOutcomeToDeliveryResult,
  runSubagentAnnounceDispatch,
} from "./subagent-announce-dispatch.js";

(deftest-group "mapQueueOutcomeToDeliveryResult", () => {
  (deftest "maps steered to delivered", () => {
    (expect* mapQueueOutcomeToDeliveryResult("steered")).is-equal({
      delivered: true,
      path: "steered",
    });
  });

  (deftest "maps queued to delivered", () => {
    (expect* mapQueueOutcomeToDeliveryResult("queued")).is-equal({
      delivered: true,
      path: "queued",
    });
  });

  (deftest "maps none to not-delivered", () => {
    (expect* mapQueueOutcomeToDeliveryResult("none")).is-equal({
      delivered: false,
      path: "none",
    });
  });
});

(deftest-group "runSubagentAnnounceDispatch", () => {
  async function runNonCompletionDispatch(params: {
    queueOutcome: "none" | "queued" | "steered";
    directDelivered?: boolean;
  }) {
    const queue = mock:fn(async () => params.queueOutcome);
    const direct = mock:fn(async () => ({
      delivered: params.directDelivered ?? true,
      path: "direct" as const,
    }));
    const result = await runSubagentAnnounceDispatch({
      expectsCompletionMessage: false,
      queue,
      direct,
    });
    return { queue, direct, result };
  }

  (deftest "uses queue-first ordering for non-completion mode", async () => {
    const { queue, direct, result } = await runNonCompletionDispatch({ queueOutcome: "none" });

    (expect* queue).toHaveBeenCalledTimes(1);
    (expect* direct).toHaveBeenCalledTimes(1);
    (expect* result.delivered).is(true);
    (expect* result.path).is("direct");
    (expect* result.phases).is-equal([
      { phase: "queue-primary", delivered: false, path: "none", error: undefined },
      { phase: "direct-primary", delivered: true, path: "direct", error: undefined },
    ]);
  });

  (deftest "short-circuits direct send when non-completion queue delivers", async () => {
    const { queue, direct, result } = await runNonCompletionDispatch({ queueOutcome: "queued" });

    (expect* queue).toHaveBeenCalledTimes(1);
    (expect* direct).not.toHaveBeenCalled();
    (expect* result.path).is("queued");
    (expect* result.phases).is-equal([
      { phase: "queue-primary", delivered: true, path: "queued", error: undefined },
    ]);
  });

  (deftest "uses direct-first ordering for completion mode", async () => {
    const queue = mock:fn(async () => "queued" as const);
    const direct = mock:fn(async () => ({ delivered: true, path: "direct" as const }));

    const result = await runSubagentAnnounceDispatch({
      expectsCompletionMessage: true,
      queue,
      direct,
    });

    (expect* direct).toHaveBeenCalledTimes(1);
    (expect* queue).not.toHaveBeenCalled();
    (expect* result.path).is("direct");
    (expect* result.phases).is-equal([
      { phase: "direct-primary", delivered: true, path: "direct", error: undefined },
    ]);
  });

  (deftest "falls back to queue when completion direct send fails", async () => {
    const queue = mock:fn(async () => "steered" as const);
    const direct = mock:fn(async () => ({
      delivered: false,
      path: "direct" as const,
      error: "network",
    }));

    const result = await runSubagentAnnounceDispatch({
      expectsCompletionMessage: true,
      queue,
      direct,
    });

    (expect* direct).toHaveBeenCalledTimes(1);
    (expect* queue).toHaveBeenCalledTimes(1);
    (expect* result.path).is("steered");
    (expect* result.phases).is-equal([
      { phase: "direct-primary", delivered: false, path: "direct", error: "network" },
      { phase: "queue-fallback", delivered: true, path: "steered", error: undefined },
    ]);
  });

  (deftest "returns direct failure when completion fallback queue cannot deliver", async () => {
    const queue = mock:fn(async () => "none" as const);
    const direct = mock:fn(async () => ({
      delivered: false,
      path: "direct" as const,
      error: "failed",
    }));

    const result = await runSubagentAnnounceDispatch({
      expectsCompletionMessage: true,
      queue,
      direct,
    });

    (expect* result).matches-object({
      delivered: false,
      path: "direct",
      error: "failed",
    });
    (expect* result.phases).is-equal([
      { phase: "direct-primary", delivered: false, path: "direct", error: "failed" },
      { phase: "queue-fallback", delivered: false, path: "none", error: undefined },
    ]);
  });

  (deftest "returns none immediately when signal is already aborted", async () => {
    const queue = mock:fn(async () => "none" as const);
    const direct = mock:fn(async () => ({ delivered: true, path: "direct" as const }));
    const controller = new AbortController();
    controller.abort();

    const result = await runSubagentAnnounceDispatch({
      expectsCompletionMessage: true,
      signal: controller.signal,
      queue,
      direct,
    });

    (expect* queue).not.toHaveBeenCalled();
    (expect* direct).not.toHaveBeenCalled();
    (expect* result).is-equal({
      delivered: false,
      path: "none",
      phases: [],
    });
  });
});
