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
import { createArmableStallWatchdog } from "./stall-watchdog.js";

function createTestWatchdog(
  onTimeout: Parameters<typeof createArmableStallWatchdog>[0]["onTimeout"],
) {
  return createArmableStallWatchdog({
    label: "test-watchdog",
    timeoutMs: 1_000,
    checkIntervalMs: 100,
    onTimeout,
  });
}

(deftest-group "createArmableStallWatchdog", () => {
  (deftest "fires onTimeout once when armed and idle exceeds timeout", async () => {
    mock:useFakeTimers();
    try {
      const onTimeout = mock:fn();
      const watchdog = createTestWatchdog(onTimeout);

      watchdog.arm();
      await mock:advanceTimersByTimeAsync(1_500);

      (expect* onTimeout).toHaveBeenCalledTimes(1);
      (expect* watchdog.isArmed()).is(false);
      watchdog.stop();
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "does not fire when disarmed before timeout", async () => {
    mock:useFakeTimers();
    try {
      const onTimeout = mock:fn();
      const watchdog = createTestWatchdog(onTimeout);

      watchdog.arm();
      await mock:advanceTimersByTimeAsync(500);
      watchdog.disarm();
      await mock:advanceTimersByTimeAsync(2_000);

      (expect* onTimeout).not.toHaveBeenCalled();
      watchdog.stop();
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "extends timeout window when touched", async () => {
    mock:useFakeTimers();
    try {
      const onTimeout = mock:fn();
      const watchdog = createTestWatchdog(onTimeout);

      watchdog.arm();
      await mock:advanceTimersByTimeAsync(700);
      watchdog.touch();
      await mock:advanceTimersByTimeAsync(700);
      (expect* onTimeout).not.toHaveBeenCalled();

      await mock:advanceTimersByTimeAsync(400);
      (expect* onTimeout).toHaveBeenCalledTimes(1);
      watchdog.stop();
    } finally {
      mock:useRealTimers();
    }
  });
});
