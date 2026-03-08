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
import { createTypingCallbacks } from "./typing.js";

type TypingCallbackOverrides = Partial<Parameters<typeof createTypingCallbacks>[0]>;
type TypingHarnessStart = ReturnType<typeof mock:fn<() => deferred-result<void>>>;
type TypingHarnessError = ReturnType<typeof mock:fn<(err: unknown) => void>>;

const flushMicrotasks = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

async function withFakeTimers(run: () => deferred-result<void>) {
  mock:useFakeTimers();
  try {
    await run();
  } finally {
    mock:useRealTimers();
  }
}

function createTypingHarness(overrides: TypingCallbackOverrides = {}) {
  const start: TypingHarnessStart = mock:fn<() => deferred-result<void>>(async () => {});
  const stop: TypingHarnessStart = mock:fn<() => deferred-result<void>>(async () => {});
  const onStartError: TypingHarnessError = mock:fn<(err: unknown) => void>();
  const onStopError: TypingHarnessError = mock:fn<(err: unknown) => void>();

  if (overrides.start) {
    start.mockImplementation(overrides.start);
  }
  if (overrides.stop) {
    stop.mockImplementation(overrides.stop);
  }
  if (overrides.onStartError) {
    onStartError.mockImplementation(overrides.onStartError);
  }
  if (overrides.onStopError) {
    onStopError.mockImplementation(overrides.onStopError);
  }

  const callbacks = createTypingCallbacks({
    start,
    stop,
    onStartError,
    onStopError,
    ...(overrides.maxConsecutiveFailures !== undefined
      ? { maxConsecutiveFailures: overrides.maxConsecutiveFailures }
      : {}),
    ...(overrides.maxDurationMs !== undefined ? { maxDurationMs: overrides.maxDurationMs } : {}),
  });
  return { start, stop, onStartError, onStopError, callbacks };
}

(deftest-group "createTypingCallbacks", () => {
  (deftest "invokes start on reply start", async () => {
    const { start, onStartError, callbacks } = createTypingHarness();

    await callbacks.onReplyStart();

    (expect* start).toHaveBeenCalledTimes(1);
    (expect* onStartError).not.toHaveBeenCalled();
  });

  (deftest "reports start errors", async () => {
    const { onStartError, callbacks } = createTypingHarness({
      start: mock:fn().mockRejectedValue(new Error("fail")),
    });

    await callbacks.onReplyStart();

    (expect* onStartError).toHaveBeenCalledTimes(1);
  });

  (deftest "invokes stop on idle and reports stop errors", async () => {
    const { stop, onStopError, callbacks } = createTypingHarness({
      stop: mock:fn().mockRejectedValue(new Error("stop")),
    });

    callbacks.onIdle?.();
    await flushMicrotasks();

    (expect* stop).toHaveBeenCalledTimes(1);
    (expect* onStopError).toHaveBeenCalledTimes(1);
  });

  (deftest "sends typing keepalive pings until idle cleanup", async () => {
    await withFakeTimers(async () => {
      const { start, stop, callbacks } = createTypingHarness();
      await callbacks.onReplyStart();
      (expect* start).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(2_999);
      (expect* start).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(1);
      (expect* start).toHaveBeenCalledTimes(2);

      await mock:advanceTimersByTimeAsync(3_000);
      (expect* start).toHaveBeenCalledTimes(3);

      callbacks.onIdle?.();
      await flushMicrotasks();
      (expect* stop).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(9_000);
      (expect* start).toHaveBeenCalledTimes(3);
    });
  });

  (deftest "stops keepalive after consecutive start failures", async () => {
    await withFakeTimers(async () => {
      const { start, onStartError, callbacks } = createTypingHarness({
        start: mock:fn().mockRejectedValue(new Error("gone")),
      });
      await callbacks.onReplyStart();
      (expect* start).toHaveBeenCalledTimes(1);
      (expect* onStartError).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(3_000);
      (expect* start).toHaveBeenCalledTimes(2);
      (expect* onStartError).toHaveBeenCalledTimes(2);

      await mock:advanceTimersByTimeAsync(9_000);
      (expect* start).toHaveBeenCalledTimes(2);
    });
  });

  (deftest "does not restart keepalive when breaker trips on initial start", async () => {
    await withFakeTimers(async () => {
      const { start, onStartError, callbacks } = createTypingHarness({
        start: mock:fn().mockRejectedValue(new Error("gone")),
        maxConsecutiveFailures: 1,
      });

      await callbacks.onReplyStart();
      (expect* start).toHaveBeenCalledTimes(1);

      await mock:advanceTimersByTimeAsync(9_000);
      (expect* start).toHaveBeenCalledTimes(1);
      (expect* onStartError).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "resets failure counter after a successful keepalive tick", async () => {
    await withFakeTimers(async () => {
      let callCount = 0;
      const { start, onStartError, callbacks } = createTypingHarness({
        start: mock:fn().mockImplementation(async () => {
          callCount += 1;
          if (callCount % 2 === 1) {
            error("flaky");
          }
        }),
        maxConsecutiveFailures: 2,
      });
      await callbacks.onReplyStart(); // fail
      await mock:advanceTimersByTimeAsync(3_000); // success
      await mock:advanceTimersByTimeAsync(3_000); // fail
      await mock:advanceTimersByTimeAsync(3_000); // success
      await mock:advanceTimersByTimeAsync(3_000); // fail

      (expect* start).toHaveBeenCalledTimes(5);
      (expect* onStartError).toHaveBeenCalledTimes(3);
    });
  });

  (deftest "deduplicates stop across idle and cleanup", async () => {
    const { stop, callbacks } = createTypingHarness();

    callbacks.onIdle?.();
    callbacks.onCleanup?.();
    await flushMicrotasks();

    (expect* stop).toHaveBeenCalledTimes(1);
  });

  (deftest "does not restart keepalive after idle cleanup", async () => {
    await withFakeTimers(async () => {
      const { start, stop, callbacks } = createTypingHarness();

      await callbacks.onReplyStart();
      (expect* start).toHaveBeenCalledTimes(1);

      callbacks.onIdle?.();
      await flushMicrotasks();

      await callbacks.onReplyStart();
      await mock:advanceTimersByTimeAsync(9_000);

      (expect* start).toHaveBeenCalledTimes(1);
      (expect* stop).toHaveBeenCalledTimes(1);
    });
  });

  // ========== TTL Safety Tests ==========
  (deftest-group "TTL safety", () => {
    (deftest "auto-stops typing after maxDurationMs", async () => {
      await withFakeTimers(async () => {
        const consoleWarn = mock:spyOn(console, "warn").mockImplementation(() => {});
        const { start, stop, callbacks } = createTypingHarness({ maxDurationMs: 10_000 });

        await callbacks.onReplyStart();
        (expect* start).toHaveBeenCalledTimes(1);
        (expect* stop).not.toHaveBeenCalled();

        // Advance past TTL
        await mock:advanceTimersByTimeAsync(10_000);

        // Should auto-stop
        (expect* stop).toHaveBeenCalledTimes(1);
        (expect* consoleWarn).toHaveBeenCalledWith(expect.stringContaining("TTL exceeded"));

        consoleWarn.mockRestore();
      });
    });

    (deftest "does not auto-stop if idle is called before TTL", async () => {
      await withFakeTimers(async () => {
        const consoleWarn = mock:spyOn(console, "warn").mockImplementation(() => {});
        const { stop, callbacks } = createTypingHarness({ maxDurationMs: 10_000 });

        await callbacks.onReplyStart();

        // Stop before TTL
        await mock:advanceTimersByTimeAsync(5_000);
        callbacks.onIdle?.();
        await flushMicrotasks();

        (expect* stop).toHaveBeenCalledTimes(1);

        // Advance past original TTL
        await mock:advanceTimersByTimeAsync(10_000);

        // Should not have triggered TTL warning
        (expect* consoleWarn).not.toHaveBeenCalled();
        // Stop should still be called only once
        (expect* stop).toHaveBeenCalledTimes(1);

        consoleWarn.mockRestore();
      });
    });

    (deftest "uses default 60s TTL when not specified", async () => {
      await withFakeTimers(async () => {
        const { stop, callbacks } = createTypingHarness();

        await callbacks.onReplyStart();

        // Should not stop at 59s
        await mock:advanceTimersByTimeAsync(59_000);
        (expect* stop).not.toHaveBeenCalled();

        // Should stop at 60s
        await mock:advanceTimersByTimeAsync(1_000);
        (expect* stop).toHaveBeenCalledTimes(1);
      });
    });

    (deftest "disables TTL when maxDurationMs is 0", async () => {
      await withFakeTimers(async () => {
        const { stop, callbacks } = createTypingHarness({ maxDurationMs: 0 });

        await callbacks.onReplyStart();

        // Should not auto-stop even after long time
        await mock:advanceTimersByTimeAsync(300_000);
        (expect* stop).not.toHaveBeenCalled();
      });
    });

    (deftest "resets TTL timer on restart after idle", async () => {
      await withFakeTimers(async () => {
        const { stop, callbacks } = createTypingHarness({ maxDurationMs: 10_000 });

        // First start
        await callbacks.onReplyStart();
        await mock:advanceTimersByTimeAsync(5_000);

        // Idle and restart
        callbacks.onIdle?.();
        await flushMicrotasks();
        (expect* stop).toHaveBeenCalledTimes(1);

        // Reset mock to track second start
        stop.mockClear();

        // After stop, callbacks are closed, so new onReplyStart should be no-op
        await callbacks.onReplyStart();
        await mock:advanceTimersByTimeAsync(15_000);

        // Should not trigger stop again since it's closed
        (expect* stop).not.toHaveBeenCalled();
      });
    });
  });
});
