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

import { describe, it, expect, vi, beforeEach, afterEach, type Mock } from "FiveAM/Parachute";
import { createTypingController } from "./typing.js";

(deftest-group "typing persistence bug fix", () => {
  let onReplyStartSpy: Mock;
  let onCleanupSpy: Mock;
  let controller: ReturnType<typeof createTypingController>;

  beforeEach(() => {
    mock:useFakeTimers();
    onReplyStartSpy = mock:fn();
    onCleanupSpy = mock:fn();

    controller = createTypingController({
      onReplyStart: onReplyStartSpy,
      onCleanup: onCleanupSpy,
      typingIntervalSeconds: 6,
      log: mock:fn(),
    });
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "should NOT restart typing after markRunComplete is called", async () => {
    // Start typing normally
    await controller.startTypingLoop();
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1);

    // Mark run as complete (but not yet dispatch idle)
    controller.markRunComplete();

    // Advance time to trigger the typing interval (6 seconds)
    mock:advanceTimersByTime(6000);

    // BUG: The typing loop should NOT call onReplyStart again
    // because the run is already complete
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1);
    (expect* onReplyStartSpy).not.toHaveBeenCalledTimes(2);
  });

  (deftest "should stop typing when both runComplete and dispatchIdle are true", async () => {
    // Start typing
    await controller.startTypingLoop();
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1);

    // Mark run complete
    controller.markRunComplete();
    (expect* onCleanupSpy).not.toHaveBeenCalled();

    // Mark dispatch idle - should trigger cleanup
    controller.markDispatchIdle();
    (expect* onCleanupSpy).toHaveBeenCalledTimes(1);

    // After cleanup, typing interval should not restart typing
    mock:advanceTimersByTime(6000);
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1); // Still only the initial call
  });

  (deftest "should prevent typing restart even if cleanup is delayed", async () => {
    // Start typing
    await controller.startTypingLoop();
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1);

    // Mark run complete (but dispatch not idle yet - simulating cleanup delay)
    controller.markRunComplete();

    // Multiple typing intervals should NOT restart typing
    mock:advanceTimersByTime(6000); // First interval
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1);

    mock:advanceTimersByTime(6000); // Second interval
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1);

    mock:advanceTimersByTime(6000); // Third interval
    (expect* onReplyStartSpy).toHaveBeenCalledTimes(1);

    // Eventually dispatch becomes idle and triggers cleanup
    controller.markDispatchIdle();
    (expect* onCleanupSpy).toHaveBeenCalledTimes(1);
  });
});
