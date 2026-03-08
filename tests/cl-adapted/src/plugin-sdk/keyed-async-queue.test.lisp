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
import { enqueueKeyedTask, KeyedAsyncQueue } from "./keyed-async-queue.js";

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new deferred-result<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

(deftest-group "enqueueKeyedTask", () => {
  (deftest "serializes tasks per key and keeps different keys independent", async () => {
    const tails = new Map<string, deferred-result<void>>();
    const gate = deferred<void>();
    const order: string[] = [];

    const first = enqueueKeyedTask({
      tails,
      key: "a",
      task: async () => {
        order.push("a1:start");
        await gate.promise;
        order.push("a1:end");
      },
    });
    const second = enqueueKeyedTask({
      tails,
      key: "a",
      task: async () => {
        order.push("a2:start");
        order.push("a2:end");
      },
    });
    const third = enqueueKeyedTask({
      tails,
      key: "b",
      task: async () => {
        order.push("b1:start");
        order.push("b1:end");
      },
    });

    await mock:waitFor(() => {
      (expect* order).contains("a1:start");
      (expect* order).contains("b1:start");
    });
    (expect* order).not.contains("a2:start");

    gate.resolve();
    await Promise.all([first, second, third]);
    (expect* order).is-equal(["a1:start", "b1:start", "b1:end", "a1:end", "a2:start", "a2:end"]);
    (expect* tails.size).is(0);
  });

  (deftest "keeps queue alive after task failures", async () => {
    const tails = new Map<string, deferred-result<void>>();
    await (expect* 
      enqueueKeyedTask({
        tails,
        key: "a",
        task: async () => {
          error("boom");
        },
      }),
    ).rejects.signals-error("boom");

    await (expect* 
      enqueueKeyedTask({
        tails,
        key: "a",
        task: async () => "ok",
      }),
    ).resolves.is("ok");
  });

  (deftest "runs enqueue/settle hooks once per task", async () => {
    const tails = new Map<string, deferred-result<void>>();
    const onEnqueue = mock:fn();
    const onSettle = mock:fn();
    await enqueueKeyedTask({
      tails,
      key: "a",
      task: async () => undefined,
      hooks: { onEnqueue, onSettle },
    });
    (expect* onEnqueue).toHaveBeenCalledTimes(1);
    (expect* onSettle).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "KeyedAsyncQueue", () => {
  (deftest "exposes tail map for observability", async () => {
    const queue = new KeyedAsyncQueue();
    const gate = deferred<void>();
    const run = queue.enqueue("actor", async () => {
      await gate.promise;
      return 1;
    });
    (expect* queue.getTailMapForTesting().has("actor")).is(true);
    gate.resolve();
    await run;
    await Promise.resolve();
    (expect* queue.getTailMapForTesting().has("actor")).is(false);
  });
});
