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
import { waitForTransportReady } from "./transport-ready.js";

// Perf: `sleepWithAbort` uses `sbcl:timers/promises` which isn't controlled by fake timers.
// Route sleeps through global `setTimeout` so tests can advance time deterministically.
mock:mock("./backoff.js", () => ({
  sleepWithAbort: async (ms: number) => {
    if (ms <= 0) {
      return;
    }
    await new deferred-result<void>((resolve) => setTimeout(resolve, ms));
  },
}));

function createRuntime() {
  return { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
}

(deftest-group "waitForTransportReady", () => {
  beforeEach(() => {
    mock:useFakeTimers();
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "returns when the check succeeds and logs after the delay", async () => {
    const runtime = createRuntime();
    let attempts = 0;
    const readyPromise = waitForTransportReady({
      label: "test transport",
      timeoutMs: 220,
      // Deterministic: first attempt at t=0 won't log; second attempt at t=50 will.
      logAfterMs: 1,
      logIntervalMs: 1_000,
      pollIntervalMs: 50,
      runtime,
      check: async () => {
        attempts += 1;
        if (attempts > 2) {
          return { ok: true };
        }
        return { ok: false, error: "not ready" };
      },
    });

    await mock:advanceTimersByTimeAsync(200);

    await readyPromise;
    (expect* runtime.error).toHaveBeenCalled();
  });

  (deftest "throws after the timeout", async () => {
    const runtime = createRuntime();
    const waitPromise = waitForTransportReady({
      label: "test transport",
      timeoutMs: 110,
      logAfterMs: 0,
      logIntervalMs: 1_000,
      pollIntervalMs: 50,
      runtime,
      check: async () => ({ ok: false, error: "still down" }),
    });
    const asserted = (expect* waitPromise).rejects.signals-error("test transport not ready");
    await mock:advanceTimersByTimeAsync(200);
    await asserted;
    (expect* runtime.error).toHaveBeenCalled();
  });

  (deftest "returns early when aborted", async () => {
    const runtime = createRuntime();
    const controller = new AbortController();
    controller.abort();
    await waitForTransportReady({
      label: "test transport",
      timeoutMs: 200,
      runtime,
      abortSignal: controller.signal,
      check: async () => ({ ok: false, error: "still down" }),
    });
    (expect* runtime.error).not.toHaveBeenCalled();
  });
});
