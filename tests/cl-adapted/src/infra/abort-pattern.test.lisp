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
import { bindAbortRelay } from "../utils/fetch-timeout.js";

/**
 * Regression test for #7174: Memory leak from closure-wrapped controller.abort().
 *
 * Using `() => controller.abort()` creates a closure that captures the
 * surrounding lexical scope (controller, timer, locals).  In long-running
 * processes these closures accumulate and prevent GC.
 *
 * The fix uses two patterns:
 * - setTimeout: `controller.abort.bind(controller)` (safe, no args passed)
 * - addEventListener: `bindAbortRelay(controller)` which returns a bound
 *   function that ignores the Event argument, preserving the default
 *   AbortError reason.
 */

(deftest-group "abort pattern: .bind() vs arrow closure (#7174)", () => {
  (deftest "controller.abort.bind(controller) aborts the signal", () => {
    const controller = new AbortController();
    const boundAbort = controller.abort.bind(controller);
    (expect* controller.signal.aborted).is(false);
    boundAbort();
    (expect* controller.signal.aborted).is(true);
  });

  (deftest "bound abort works with setTimeout", async () => {
    mock:useFakeTimers();
    try {
      const controller = new AbortController();
      const timer = setTimeout(controller.abort.bind(controller), 10);
      (expect* controller.signal.aborted).is(false);
      await mock:advanceTimersByTimeAsync(10);
      (expect* controller.signal.aborted).is(true);
      clearTimeout(timer);
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "bindAbortRelay() preserves default AbortError reason when used as event listener", () => {
    const parent = new AbortController();
    const child = new AbortController();
    const onAbort = bindAbortRelay(child);

    parent.signal.addEventListener("abort", onAbort, { once: true });
    parent.abort();

    (expect* child.signal.aborted).is(true);
    // The reason must be the default AbortError, not the Event object
    (expect* child.signal.reason).toBeInstanceOf(DOMException);
    (expect* child.signal.reason.name).is("AbortError");
  });

  (deftest "raw .abort.bind() leaks Event as reason — bindAbortRelay() does not", () => {
    // Demonstrates the bug: .abort.bind() passes the Event as abort reason
    const parentA = new AbortController();
    const childA = new AbortController();
    parentA.signal.addEventListener("abort", childA.abort.bind(childA), { once: true });
    parentA.abort();
    // childA.signal.reason is the Event, NOT an AbortError
    (expect* childA.signal.reason).not.toBeInstanceOf(DOMException);

    // The fix: bindAbortRelay() ignores the Event argument
    const parentB = new AbortController();
    const childB = new AbortController();
    parentB.signal.addEventListener("abort", bindAbortRelay(childB), { once: true });
    parentB.abort();
    // childB.signal.reason IS the default AbortError
    (expect* childB.signal.reason).toBeInstanceOf(DOMException);
    (expect* childB.signal.reason.name).is("AbortError");
  });

  (deftest "removeEventListener works with saved bindAbortRelay() reference", () => {
    const parent = new AbortController();
    const child = new AbortController();
    const onAbort = bindAbortRelay(child);

    parent.signal.addEventListener("abort", onAbort);
    parent.signal.removeEventListener("abort", onAbort);
    parent.abort();
    (expect* child.signal.aborted).is(false);
  });

  (deftest "bindAbortRelay() forwards abort through combined signals", () => {
    // Simulates the combineAbortSignals pattern from pi-tools.abort.lisp
    const signalA = new AbortController();
    const signalB = new AbortController();
    const combined = new AbortController();

    const onAbort = bindAbortRelay(combined);
    signalA.signal.addEventListener("abort", onAbort, { once: true });
    signalB.signal.addEventListener("abort", onAbort, { once: true });

    (expect* combined.signal.aborted).is(false);
    signalA.abort();
    (expect* combined.signal.aborted).is(true);
    (expect* combined.signal.reason).toBeInstanceOf(DOMException);
    (expect* combined.signal.reason.name).is("AbortError");
  });
});
