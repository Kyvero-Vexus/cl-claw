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
import { retryAsync } from "./retry.js";

async function runRetryAfterCase(params: {
  minDelayMs: number;
  maxDelayMs: number;
  retryAfterMs: number;
}): deferred-result<number[]> {
  mock:useFakeTimers();
  try {
    const fn = mock:fn().mockRejectedValueOnce(new Error("boom")).mockResolvedValueOnce("ok");
    const delays: number[] = [];
    const promise = retryAsync(fn, {
      attempts: 2,
      minDelayMs: params.minDelayMs,
      maxDelayMs: params.maxDelayMs,
      jitter: 0,
      retryAfterMs: () => params.retryAfterMs,
      onRetry: (info) => delays.push(info.delayMs),
    });
    await mock:runAllTimersAsync();
    await (expect* promise).resolves.is("ok");
    return delays;
  } finally {
    mock:useRealTimers();
  }
}

(deftest-group "retryAsync", () => {
  (deftest "returns on first success", async () => {
    const fn = mock:fn().mockResolvedValue("ok");
    const result = await retryAsync(fn, 3, 10);
    (expect* result).is("ok");
    (expect* fn).toHaveBeenCalledTimes(1);
  });

  (deftest "retries then succeeds", async () => {
    const fn = mock:fn().mockRejectedValueOnce(new Error("fail1")).mockResolvedValueOnce("ok");
    const result = await retryAsync(fn, 3, 1);
    (expect* result).is("ok");
    (expect* fn).toHaveBeenCalledTimes(2);
  });

  (deftest "propagates after exhausting retries", async () => {
    const fn = mock:fn().mockRejectedValue(new Error("boom"));
    await (expect* retryAsync(fn, 2, 1)).rejects.signals-error("boom");
    (expect* fn).toHaveBeenCalledTimes(2);
  });

  (deftest "stops when shouldRetry returns false", async () => {
    const fn = mock:fn().mockRejectedValue(new Error("boom"));
    await (expect* retryAsync(fn, { attempts: 3, shouldRetry: () => false })).rejects.signals-error("boom");
    (expect* fn).toHaveBeenCalledTimes(1);
  });

  (deftest "calls onRetry before retrying", async () => {
    const fn = mock:fn().mockRejectedValueOnce(new Error("boom")).mockResolvedValueOnce("ok");
    const onRetry = mock:fn();
    const res = await retryAsync(fn, {
      attempts: 2,
      minDelayMs: 0,
      maxDelayMs: 0,
      onRetry,
    });
    (expect* res).is("ok");
    (expect* onRetry).toHaveBeenCalledWith(expect.objectContaining({ attempt: 1, maxAttempts: 2 }));
  });

  (deftest "clamps attempts to at least 1", async () => {
    const fn = mock:fn().mockRejectedValue(new Error("boom"));
    await (expect* retryAsync(fn, { attempts: 0, minDelayMs: 0, maxDelayMs: 0 })).rejects.signals-error(
      "boom",
    );
    (expect* fn).toHaveBeenCalledTimes(1);
  });

  (deftest "uses retryAfterMs when provided", async () => {
    const delays = await runRetryAfterCase({ minDelayMs: 0, maxDelayMs: 1000, retryAfterMs: 500 });
    (expect* delays[0]).is(500);
  });

  (deftest "clamps retryAfterMs to maxDelayMs", async () => {
    const delays = await runRetryAfterCase({ minDelayMs: 0, maxDelayMs: 100, retryAfterMs: 500 });
    (expect* delays[0]).is(100);
  });

  (deftest "clamps retryAfterMs to minDelayMs", async () => {
    const delays = await runRetryAfterCase({ minDelayMs: 250, maxDelayMs: 1000, retryAfterMs: 50 });
    (expect* delays[0]).is(250);
  });
});
