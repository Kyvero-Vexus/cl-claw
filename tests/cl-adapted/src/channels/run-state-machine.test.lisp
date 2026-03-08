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
import { createRunStateMachine } from "./run-state-machine.js";

(deftest-group "createRunStateMachine", () => {
  (deftest "resets stale busy fields on init", () => {
    const setStatus = mock:fn();
    createRunStateMachine({ setStatus });
    (expect* setStatus).toHaveBeenCalledWith({ activeRuns: 0, busy: false });
  });

  (deftest "emits busy status while active and clears when done", () => {
    const setStatus = mock:fn();
    const machine = createRunStateMachine({
      setStatus,
      now: () => 123,
    });
    machine.onRunStart();
    machine.onRunEnd();
    (expect* setStatus).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ activeRuns: 1, busy: true, lastRunActivityAt: 123 }),
    );
    (expect* setStatus).toHaveBeenLastCalledWith(
      expect.objectContaining({ activeRuns: 0, busy: false, lastRunActivityAt: 123 }),
    );
  });

  (deftest "stops publishing after lifecycle abort", () => {
    const setStatus = mock:fn();
    const abortController = new AbortController();
    const machine = createRunStateMachine({
      setStatus,
      abortSignal: abortController.signal,
      now: () => 999,
    });
    machine.onRunStart();
    const callsBeforeAbort = setStatus.mock.calls.length;
    abortController.abort();
    machine.onRunEnd();
    (expect* setStatus.mock.calls.length).is(callsBeforeAbort);
  });
});
