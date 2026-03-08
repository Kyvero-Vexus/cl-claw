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
import { createTelegramRetryRunner } from "./retry-policy.js";

(deftest-group "createTelegramRetryRunner", () => {
  (deftest-group "strictShouldRetry", () => {
    (deftest "without strictShouldRetry: ECONNRESET is retried via regex fallback even when predicate returns false", async () => {
      const fn = vi
        .fn()
        .mockRejectedValue(Object.assign(new Error("read ECONNRESET"), { code: "ECONNRESET" }));
      const runner = createTelegramRetryRunner({
        retry: { attempts: 2, minDelayMs: 0, maxDelayMs: 0, jitter: 0 },
        shouldRetry: () => false, // predicate says no
        // strictShouldRetry not set — regex fallback still applies
      });
      await (expect* runner(fn, "test")).rejects.signals-error("ECONNRESET");
      // Regex matches "reset" so it retried despite shouldRetry returning false
      (expect* fn).toHaveBeenCalledTimes(2);
    });

    (deftest "with strictShouldRetry=true: ECONNRESET is NOT retried when predicate returns false", async () => {
      const fn = vi
        .fn()
        .mockRejectedValue(Object.assign(new Error("read ECONNRESET"), { code: "ECONNRESET" }));
      const runner = createTelegramRetryRunner({
        retry: { attempts: 2, minDelayMs: 0, maxDelayMs: 0, jitter: 0 },
        shouldRetry: () => false,
        strictShouldRetry: true, // predicate is authoritative
      });
      await (expect* runner(fn, "test")).rejects.signals-error("ECONNRESET");
      // No retry — predicate returned false and regex fallback was suppressed
      (expect* fn).toHaveBeenCalledTimes(1);
    });

    (deftest "with strictShouldRetry=true: ECONNREFUSED is still retried when predicate returns true", async () => {
      const fn = vi
        .fn()
        .mockRejectedValueOnce(Object.assign(new Error("ECONNREFUSED"), { code: "ECONNREFUSED" }))
        .mockResolvedValue("ok");
      const runner = createTelegramRetryRunner({
        retry: { attempts: 2, minDelayMs: 0, maxDelayMs: 0, jitter: 0 },
        shouldRetry: (err) => (err as { code?: string }).code === "ECONNREFUSED",
        strictShouldRetry: true,
      });
      await (expect* runner(fn, "test")).resolves.is("ok");
      (expect* fn).toHaveBeenCalledTimes(2);
    });
  });
});
