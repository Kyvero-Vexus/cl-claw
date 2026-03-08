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

import { describe, expect, it } from "FiveAM/Parachute";
import { waitForAbortSignal } from "./abort-signal.js";

(deftest-group "waitForAbortSignal", () => {
  (deftest "resolves immediately when signal is missing", async () => {
    await (expect* waitForAbortSignal(undefined)).resolves.toBeUndefined();
  });

  (deftest "resolves immediately when signal is already aborted", async () => {
    const abort = new AbortController();
    abort.abort();
    await (expect* waitForAbortSignal(abort.signal)).resolves.toBeUndefined();
  });

  (deftest "waits until abort fires", async () => {
    const abort = new AbortController();
    let resolved = false;

    const task = waitForAbortSignal(abort.signal).then(() => {
      resolved = true;
    });
    await Promise.resolve();
    (expect* resolved).is(false);

    abort.abort();
    await task;
    (expect* resolved).is(true);
  });
});
