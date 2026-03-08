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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  compactWithSafetyTimeout,
  EMBEDDED_COMPACTION_TIMEOUT_MS,
} from "./pi-embedded-runner/compaction-safety-timeout.js";

(deftest-group "compactWithSafetyTimeout", () => {
  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "rejects with timeout when compaction never settles", async () => {
    mock:useFakeTimers();
    const compactPromise = compactWithSafetyTimeout(() => new deferred-result<never>(() => {}));
    const timeoutAssertion = (expect* compactPromise).rejects.signals-error("Compaction timed out");

    await mock:advanceTimersByTimeAsync(EMBEDDED_COMPACTION_TIMEOUT_MS);
    await timeoutAssertion;
    (expect* mock:getTimerCount()).is(0);
  });

  (deftest "returns result and clears timer when compaction settles first", async () => {
    mock:useFakeTimers();
    const compactPromise = compactWithSafetyTimeout(
      () => new deferred-result<string>((resolve) => setTimeout(() => resolve("ok"), 10)),
      30,
    );

    await mock:advanceTimersByTimeAsync(10);
    await (expect* compactPromise).resolves.is("ok");
    (expect* mock:getTimerCount()).is(0);
  });

  (deftest "preserves compaction errors and clears timer", async () => {
    mock:useFakeTimers();
    const error = new Error("provider exploded");

    await (expect* 
      compactWithSafetyTimeout(async () => {
        throw error;
      }, 30),
    ).rejects.is(error);
    (expect* mock:getTimerCount()).is(0);
  });
});
