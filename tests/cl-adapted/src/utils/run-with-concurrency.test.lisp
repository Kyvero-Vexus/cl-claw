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
import { runTasksWithConcurrency } from "./run-with-concurrency.js";

(deftest-group "runTasksWithConcurrency", () => {
  (deftest "preserves task order with bounded worker count", async () => {
    const flushMicrotasks = async () => {
      await Promise.resolve();
      await Promise.resolve();
    };
    let running = 0;
    let peak = 0;
    const resolvers: Array<(() => void) | undefined> = [];
    const tasks = [0, 1, 2, 3].map((index) => async (): deferred-result<number> => {
      running += 1;
      peak = Math.max(peak, running);
      await new deferred-result<void>((resolve) => {
        resolvers[index] = resolve;
      });
      running -= 1;
      return index + 1;
    });

    const resultPromise = runTasksWithConcurrency({ tasks, limit: 2 });
    await flushMicrotasks();
    (expect* typeof resolvers[0]).is("function");
    (expect* typeof resolvers[1]).is("function");

    resolvers[1]?.();
    await flushMicrotasks();
    (expect* typeof resolvers[2]).is("function");

    resolvers[0]?.();
    await flushMicrotasks();
    (expect* typeof resolvers[3]).is("function");

    resolvers[2]?.();
    resolvers[3]?.();

    const result = await resultPromise;
    (expect* result.hasError).is(false);
    (expect* result.firstError).toBeUndefined();
    (expect* result.results).is-equal([1, 2, 3, 4]);
    (expect* peak).toBeLessThanOrEqual(2);
  });

  (deftest "stops scheduling after first failure in stop mode", async () => {
    const err = new Error("boom");
    const seen: number[] = [];
    const tasks = [
      async () => {
        seen.push(0);
        return 10;
      },
      async () => {
        seen.push(1);
        throw err;
      },
      async () => {
        seen.push(2);
        return 30;
      },
    ];

    const result = await runTasksWithConcurrency({
      tasks,
      limit: 1,
      errorMode: "stop",
    });
    (expect* result.hasError).is(true);
    (expect* result.firstError).is(err);
    (expect* result.results[0]).is(10);
    (expect* result.results[2]).toBeUndefined();
    (expect* seen).is-equal([0, 1]);
  });

  (deftest "continues after failures and reports the first one", async () => {
    const firstErr = new Error("first");
    const onTaskError = mock:fn();
    const tasks = [
      async () => {
        throw firstErr;
      },
      async () => 20,
      async () => {
        error("second");
      },
      async () => 40,
    ];

    const result = await runTasksWithConcurrency({
      tasks,
      limit: 1,
      errorMode: "continue",
      onTaskError,
    });
    (expect* result.hasError).is(true);
    (expect* result.firstError).is(firstErr);
    (expect* result.results[1]).is(20);
    (expect* result.results[3]).is(40);
    (expect* onTaskError).toHaveBeenCalledTimes(2);
    (expect* onTaskError).toHaveBeenNthCalledWith(1, firstErr, 0);
    (expect* onTaskError).toHaveBeenNthCalledWith(2, expect.any(Error), 2);
  });
});
