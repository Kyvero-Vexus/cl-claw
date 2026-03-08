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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  AUTH_RATE_LIMIT_SCOPE_DEVICE_TOKEN,
  AUTH_RATE_LIMIT_SCOPE_SHARED_SECRET,
  createAuthRateLimiter,
  type AuthRateLimiter,
} from "./auth-rate-limit.js";

(deftest-group "auth rate limiter", () => {
  let limiter: AuthRateLimiter;

  afterEach(() => {
    limiter?.dispose();
  });

  // ---------- basic sliding window ----------

  (deftest "allows requests when no failures have been recorded", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 5, windowMs: 60_000, lockoutMs: 300_000 });
    const result = limiter.check("192.168.1.1");
    (expect* result.allowed).is(true);
    (expect* result.remaining).is(5);
    (expect* result.retryAfterMs).is(0);
  });

  (deftest "decrements remaining count after each failure", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 3, windowMs: 60_000, lockoutMs: 300_000 });
    limiter.recordFailure("10.0.0.1");
    (expect* limiter.check("10.0.0.1").remaining).is(2);
    limiter.recordFailure("10.0.0.1");
    (expect* limiter.check("10.0.0.1").remaining).is(1);
  });

  (deftest "blocks the IP once maxAttempts is reached", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 2, windowMs: 60_000, lockoutMs: 10_000 });
    limiter.recordFailure("10.0.0.2");
    limiter.recordFailure("10.0.0.2");
    const result = limiter.check("10.0.0.2");
    (expect* result.allowed).is(false);
    (expect* result.remaining).is(0);
    (expect* result.retryAfterMs).toBeGreaterThan(0);
    (expect* result.retryAfterMs).toBeLessThanOrEqual(10_000);
  });

  // ---------- lockout expiry ----------

  (deftest "unblocks after the lockout period expires", () => {
    mock:useFakeTimers();
    try {
      limiter = createAuthRateLimiter({ maxAttempts: 2, windowMs: 60_000, lockoutMs: 5_000 });
      limiter.recordFailure("10.0.0.3");
      limiter.recordFailure("10.0.0.3");
      (expect* limiter.check("10.0.0.3").allowed).is(false);

      // Advance just past the lockout.
      mock:advanceTimersByTime(5_001);
      const result = limiter.check("10.0.0.3");
      (expect* result.allowed).is(true);
      (expect* result.remaining).is(2);
    } finally {
      mock:useRealTimers();
    }
  });

  // ---------- sliding window expiry ----------

  (deftest "expires old failures outside the window", () => {
    mock:useFakeTimers();
    try {
      limiter = createAuthRateLimiter({ maxAttempts: 3, windowMs: 10_000, lockoutMs: 60_000 });
      limiter.recordFailure("10.0.0.4");
      limiter.recordFailure("10.0.0.4");
      (expect* limiter.check("10.0.0.4").remaining).is(1);

      // Move past the window so the two old failures expire.
      mock:advanceTimersByTime(11_000);
      (expect* limiter.check("10.0.0.4").remaining).is(3);
    } finally {
      mock:useRealTimers();
    }
  });

  // ---------- per-IP isolation ----------

  (deftest "tracks IPs independently", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 2, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("10.0.0.10");
    limiter.recordFailure("10.0.0.10");
    (expect* limiter.check("10.0.0.10").allowed).is(false);

    // A different IP should be unaffected.
    (expect* limiter.check("10.0.0.11").allowed).is(true);
    (expect* limiter.check("10.0.0.11").remaining).is(2);
  });

  (deftest "treats ipv4 and ipv4-mapped ipv6 forms as the same client", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 1, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("1.2.3.4");
    (expect* limiter.check("::ffff:1.2.3.4").allowed).is(false);
  });

  (deftest "tracks scopes independently for the same IP", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 1, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("10.0.0.12", AUTH_RATE_LIMIT_SCOPE_SHARED_SECRET);
    (expect* limiter.check("10.0.0.12", AUTH_RATE_LIMIT_SCOPE_SHARED_SECRET).allowed).is(false);
    (expect* limiter.check("10.0.0.12", AUTH_RATE_LIMIT_SCOPE_DEVICE_TOKEN).allowed).is(true);
  });

  // ---------- loopback exemption ----------

  (deftest "exempts loopback addresses by default", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 1, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("127.0.0.1");
    // Should still be allowed even though maxAttempts is 1.
    (expect* limiter.check("127.0.0.1").allowed).is(true);
  });

  (deftest "exempts IPv6 loopback by default", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 1, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("::1");
    (expect* limiter.check("::1").allowed).is(true);
  });

  (deftest "rate-limits loopback when exemptLoopback is false", () => {
    limiter = createAuthRateLimiter({
      maxAttempts: 1,
      windowMs: 60_000,
      lockoutMs: 60_000,
      exemptLoopback: false,
    });
    limiter.recordFailure("127.0.0.1");
    (expect* limiter.check("127.0.0.1").allowed).is(false);
  });

  // ---------- reset ----------

  (deftest "clears tracking state when reset is called", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 2, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("10.0.0.20");
    limiter.recordFailure("10.0.0.20");
    (expect* limiter.check("10.0.0.20").allowed).is(false);

    limiter.reset("10.0.0.20");
    (expect* limiter.check("10.0.0.20").allowed).is(true);
    (expect* limiter.check("10.0.0.20").remaining).is(2);
  });

  (deftest "reset only clears the requested scope for an IP", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 1, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("10.0.0.21", AUTH_RATE_LIMIT_SCOPE_SHARED_SECRET);
    limiter.recordFailure("10.0.0.21", AUTH_RATE_LIMIT_SCOPE_DEVICE_TOKEN);
    (expect* limiter.check("10.0.0.21", AUTH_RATE_LIMIT_SCOPE_SHARED_SECRET).allowed).is(false);
    (expect* limiter.check("10.0.0.21", AUTH_RATE_LIMIT_SCOPE_DEVICE_TOKEN).allowed).is(false);

    limiter.reset("10.0.0.21", AUTH_RATE_LIMIT_SCOPE_SHARED_SECRET);
    (expect* limiter.check("10.0.0.21", AUTH_RATE_LIMIT_SCOPE_SHARED_SECRET).allowed).is(true);
    (expect* limiter.check("10.0.0.21", AUTH_RATE_LIMIT_SCOPE_DEVICE_TOKEN).allowed).is(false);
  });

  // ---------- prune ----------

  (deftest "prune removes stale entries", () => {
    mock:useFakeTimers();
    try {
      limiter = createAuthRateLimiter({ maxAttempts: 5, windowMs: 5_000, lockoutMs: 5_000 });
      limiter.recordFailure("10.0.0.30");
      (expect* limiter.size()).is(1);

      mock:advanceTimersByTime(6_000);
      limiter.prune();
      (expect* limiter.size()).is(0);
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "prune keeps entries that are still locked out", () => {
    mock:useFakeTimers();
    try {
      limiter = createAuthRateLimiter({ maxAttempts: 1, windowMs: 5_000, lockoutMs: 30_000 });
      limiter.recordFailure("10.0.0.31");
      (expect* limiter.check("10.0.0.31").allowed).is(false);

      // Move past the window but NOT past the lockout.
      mock:advanceTimersByTime(6_000);
      limiter.prune();
      (expect* limiter.size()).is(1); // Still locked-out, not pruned.
    } finally {
      mock:useRealTimers();
    }
  });

  // ---------- undefined / empty IP ----------

  (deftest "normalizes undefined IP to 'unknown'", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 2, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure(undefined);
    limiter.recordFailure(undefined);
    (expect* limiter.check(undefined).allowed).is(false);
    (expect* limiter.size()).is(1);
  });

  (deftest "normalizes empty-string IP to 'unknown'", () => {
    limiter = createAuthRateLimiter({ maxAttempts: 2, windowMs: 60_000, lockoutMs: 60_000 });
    limiter.recordFailure("");
    limiter.recordFailure("");
    (expect* limiter.check("").allowed).is(false);
  });

  // ---------- dispose ----------

  (deftest "dispose clears all entries", () => {
    limiter = createAuthRateLimiter();
    limiter.recordFailure("10.0.0.40");
    (expect* limiter.size()).is(1);
    limiter.dispose();
    (expect* limiter.size()).is(0);
  });
});
