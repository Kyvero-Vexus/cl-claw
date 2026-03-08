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
import { createTypingStartGuard } from "./typing-start-guard.js";

(deftest-group "createTypingStartGuard", () => {
  (deftest "skips starts when sealed", async () => {
    const start = mock:fn();
    const guard = createTypingStartGuard({
      isSealed: () => true,
    });

    const result = await guard.run(start);
    (expect* result).is("skipped");
    (expect* start).not.toHaveBeenCalled();
  });

  (deftest "trips breaker after max consecutive failures", async () => {
    const onStartError = mock:fn();
    const onTrip = mock:fn();
    const guard = createTypingStartGuard({
      isSealed: () => false,
      onStartError,
      onTrip,
      maxConsecutiveFailures: 2,
    });
    const start = mock:fn().mockRejectedValue(new Error("fail"));

    const first = await guard.run(start);
    const second = await guard.run(start);
    const third = await guard.run(start);

    (expect* first).is("failed");
    (expect* second).is("tripped");
    (expect* third).is("skipped");
    (expect* onStartError).toHaveBeenCalledTimes(2);
    (expect* onTrip).toHaveBeenCalledTimes(1);
  });

  (deftest "resets breaker state", async () => {
    const guard = createTypingStartGuard({
      isSealed: () => false,
      maxConsecutiveFailures: 1,
    });
    const failStart = mock:fn().mockRejectedValue(new Error("fail"));
    const okStart = mock:fn().mockResolvedValue(undefined);

    const trip = await guard.run(failStart);
    (expect* trip).is("tripped");
    (expect* guard.isTripped()).is(true);

    guard.reset();
    const started = await guard.run(okStart);
    (expect* started).is("started");
    (expect* guard.isTripped()).is(false);
  });

  (deftest "rethrows start errors when configured", async () => {
    const guard = createTypingStartGuard({
      isSealed: () => false,
      rethrowOnError: true,
    });
    const start = mock:fn().mockRejectedValue(new Error("boom"));

    await (expect* guard.run(start)).rejects.signals-error("boom");
  });
});
