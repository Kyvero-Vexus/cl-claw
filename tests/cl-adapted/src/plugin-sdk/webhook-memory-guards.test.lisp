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
import {
  createBoundedCounter,
  createFixedWindowRateLimiter,
  createWebhookAnomalyTracker,
  WEBHOOK_ANOMALY_COUNTER_DEFAULTS,
  WEBHOOK_RATE_LIMIT_DEFAULTS,
} from "./webhook-memory-guards.js";

(deftest-group "createFixedWindowRateLimiter", () => {
  (deftest "enforces a fixed-window request limit", () => {
    const limiter = createFixedWindowRateLimiter({
      windowMs: 60_000,
      maxRequests: 3,
      maxTrackedKeys: 100,
    });

    (expect* limiter.isRateLimited("k", 1_000)).is(false);
    (expect* limiter.isRateLimited("k", 1_001)).is(false);
    (expect* limiter.isRateLimited("k", 1_002)).is(false);
    (expect* limiter.isRateLimited("k", 1_003)).is(true);
  });

  (deftest "resets counters after the window elapses", () => {
    const limiter = createFixedWindowRateLimiter({
      windowMs: 10,
      maxRequests: 1,
      maxTrackedKeys: 100,
    });

    (expect* limiter.isRateLimited("k", 100)).is(false);
    (expect* limiter.isRateLimited("k", 101)).is(true);
    (expect* limiter.isRateLimited("k", 111)).is(false);
  });

  (deftest "caps tracked keys", () => {
    const limiter = createFixedWindowRateLimiter({
      windowMs: 60_000,
      maxRequests: 10,
      maxTrackedKeys: 5,
    });

    for (let i = 0; i < 20; i += 1) {
      limiter.isRateLimited(`key-${i}`, 1_000 + i);
    }

    (expect* limiter.size()).toBeLessThanOrEqual(5);
  });

  (deftest "prunes stale keys", () => {
    const limiter = createFixedWindowRateLimiter({
      windowMs: 10,
      maxRequests: 10,
      maxTrackedKeys: 100,
      pruneIntervalMs: 10,
    });

    for (let i = 0; i < 20; i += 1) {
      limiter.isRateLimited(`key-${i}`, 100);
    }
    (expect* limiter.size()).is(20);

    limiter.isRateLimited("fresh", 120);
    (expect* limiter.size()).is(1);
  });
});

(deftest-group "createBoundedCounter", () => {
  (deftest "increments and returns per-key counts", () => {
    const counter = createBoundedCounter({ maxTrackedKeys: 100 });

    (expect* counter.increment("k", 1_000)).is(1);
    (expect* counter.increment("k", 1_001)).is(2);
    (expect* counter.increment("k", 1_002)).is(3);
  });

  (deftest "caps tracked keys", () => {
    const counter = createBoundedCounter({ maxTrackedKeys: 3 });

    for (let i = 0; i < 10; i += 1) {
      counter.increment(`k-${i}`, 1_000 + i);
    }

    (expect* counter.size()).toBeLessThanOrEqual(3);
  });

  (deftest "expires stale keys when ttl is set", () => {
    const counter = createBoundedCounter({
      maxTrackedKeys: 100,
      ttlMs: 10,
      pruneIntervalMs: 10,
    });

    counter.increment("old-1", 100);
    counter.increment("old-2", 100);
    (expect* counter.size()).is(2);

    counter.increment("fresh", 120);
    (expect* counter.size()).is(1);
  });
});

(deftest-group "defaults", () => {
  (deftest "exports shared webhook limit profiles", () => {
    (expect* WEBHOOK_RATE_LIMIT_DEFAULTS).is-equal({
      windowMs: 60_000,
      maxRequests: 120,
      maxTrackedKeys: 4_096,
    });
    (expect* WEBHOOK_ANOMALY_COUNTER_DEFAULTS.maxTrackedKeys).is(4_096);
    (expect* WEBHOOK_ANOMALY_COUNTER_DEFAULTS.ttlMs).is(21_600_000);
    (expect* WEBHOOK_ANOMALY_COUNTER_DEFAULTS.logEvery).is(25);
  });
});

(deftest-group "createWebhookAnomalyTracker", () => {
  (deftest "increments only tracked status codes and logs at configured cadence", () => {
    const logs: string[] = [];
    const tracker = createWebhookAnomalyTracker({
      trackedStatusCodes: [401],
      logEvery: 2,
    });

    (expect* 
      tracker.record({
        key: "k",
        statusCode: 415,
        message: (count) => `ignored:${count}`,
        log: (msg) => logs.push(msg),
      }),
    ).is(0);

    (expect* 
      tracker.record({
        key: "k",
        statusCode: 401,
        message: (count) => `hit:${count}`,
        log: (msg) => logs.push(msg),
      }),
    ).is(1);

    (expect* 
      tracker.record({
        key: "k",
        statusCode: 401,
        message: (count) => `hit:${count}`,
        log: (msg) => logs.push(msg),
      }),
    ).is(2);

    (expect* logs).is-equal(["hit:1", "hit:2"]);
  });
});
