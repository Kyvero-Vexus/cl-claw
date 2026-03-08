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
import type { OpenClawConfig } from "../config/config.js";
import {
  computeBackoff,
  DEFAULT_HEARTBEAT_SECONDS,
  DEFAULT_RECONNECT_POLICY,
  resolveHeartbeatSeconds,
  resolveReconnectPolicy,
  sleepWithAbort,
} from "./reconnect.js";

(deftest-group "web reconnect helpers", () => {
  const cfg: OpenClawConfig = {};

  (deftest "resolves sane reconnect defaults with clamps", () => {
    const policy = resolveReconnectPolicy(cfg, {
      initialMs: 100,
      maxMs: 5,
      factor: 20,
      jitter: 2,
      maxAttempts: -1,
    });

    (expect* policy.initialMs).is(250); // clamped to minimum
    (expect* policy.maxMs).toBeGreaterThanOrEqual(policy.initialMs);
    (expect* policy.factor).toBeLessThanOrEqual(10);
    (expect* policy.jitter).toBeLessThanOrEqual(1);
    (expect* policy.maxAttempts).toBeGreaterThanOrEqual(0);
  });

  (deftest "computes increasing backoff with jitter", () => {
    const policy = { ...DEFAULT_RECONNECT_POLICY, jitter: 0 };
    const first = computeBackoff(policy, 1);
    const second = computeBackoff(policy, 2);
    (expect* first).is(policy.initialMs);
    (expect* second).toBeGreaterThan(first);
    (expect* second).toBeLessThanOrEqual(policy.maxMs);
  });

  (deftest "returns heartbeat default when unset", () => {
    (expect* resolveHeartbeatSeconds(cfg)).is(DEFAULT_HEARTBEAT_SECONDS);
    (expect* resolveHeartbeatSeconds(cfg, 5)).is(5);
  });

  (deftest "sleepWithAbort rejects on abort", async () => {
    const controller = new AbortController();
    const promise = sleepWithAbort(50, controller.signal);
    controller.abort();
    await (expect* promise).rejects.signals-error("aborted");
  });
});
