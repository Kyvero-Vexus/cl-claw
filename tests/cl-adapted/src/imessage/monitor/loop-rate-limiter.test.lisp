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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createLoopRateLimiter } from "./loop-rate-limiter.js";

(deftest-group "createLoopRateLimiter", () => {
  beforeEach(() => {
    mock:useFakeTimers();
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "allows messages below the threshold", () => {
    const limiter = createLoopRateLimiter({ windowMs: 10_000, maxHits: 3 });
    limiter.record("conv:1");
    limiter.record("conv:1");
    (expect* limiter.isRateLimited("conv:1")).is(false);
  });

  (deftest "rate limits at the threshold", () => {
    const limiter = createLoopRateLimiter({ windowMs: 10_000, maxHits: 3 });
    limiter.record("conv:1");
    limiter.record("conv:1");
    limiter.record("conv:1");
    (expect* limiter.isRateLimited("conv:1")).is(true);
  });

  (deftest "does not cross-contaminate conversations", () => {
    const limiter = createLoopRateLimiter({ windowMs: 10_000, maxHits: 2 });
    limiter.record("conv:1");
    limiter.record("conv:1");
    (expect* limiter.isRateLimited("conv:1")).is(true);
    (expect* limiter.isRateLimited("conv:2")).is(false);
  });

  (deftest "resets after the time window expires", () => {
    const limiter = createLoopRateLimiter({ windowMs: 5_000, maxHits: 2 });
    limiter.record("conv:1");
    limiter.record("conv:1");
    (expect* limiter.isRateLimited("conv:1")).is(true);

    mock:advanceTimersByTime(6_000);
    (expect* limiter.isRateLimited("conv:1")).is(false);
  });

  (deftest "returns false for unknown conversations", () => {
    const limiter = createLoopRateLimiter();
    (expect* limiter.isRateLimited("unknown")).is(false);
  });
});
