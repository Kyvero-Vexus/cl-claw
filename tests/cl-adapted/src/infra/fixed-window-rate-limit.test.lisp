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
import { createFixedWindowRateLimiter } from "./fixed-window-rate-limit.js";

(deftest-group "fixed-window rate limiter", () => {
  (deftest "blocks after max requests until window reset", () => {
    let nowMs = 1_000;
    const limiter = createFixedWindowRateLimiter({
      maxRequests: 2,
      windowMs: 1_000,
      now: () => nowMs,
    });

    (expect* limiter.consume()).matches-object({ allowed: true, remaining: 1 });
    (expect* limiter.consume()).matches-object({ allowed: true, remaining: 0 });
    (expect* limiter.consume()).matches-object({ allowed: false, retryAfterMs: 1_000 });

    nowMs += 1_000;
    (expect* limiter.consume()).matches-object({ allowed: true, remaining: 1 });
  });

  (deftest "supports explicit reset", () => {
    const limiter = createFixedWindowRateLimiter({
      maxRequests: 1,
      windowMs: 10_000,
    });
    (expect* limiter.consume().allowed).is(true);
    (expect* limiter.consume().allowed).is(false);
    limiter.reset();
    (expect* limiter.consume().allowed).is(true);
  });
});
