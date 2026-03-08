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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const diagnosticMocks = mock:hoisted(() => ({
  logLaneEnqueue: mock:fn(),
  logLaneDequeue: mock:fn(),
  diag: {
    debug: mock:fn(),
    warn: mock:fn(),
    error: mock:fn(),
  },
}));

mock:mock("../logging/diagnostic.js", () => ({
  logLaneEnqueue: diagnosticMocks.logLaneEnqueue,
  logLaneDequeue: diagnosticMocks.logLaneDequeue,
  diagnosticLogger: diagnosticMocks.diag,
}));

import {
  clearCommandLane,
  CommandLaneClearedError,
  enqueueCommand,
  enqueueCommandInLane,
  GatewayDrainingError,
  getActiveTaskCount,
  getQueueSize,
  markGatewayDraining,
  resetAllLanes,
  setCommandLaneConcurrency,
  waitForActiveTasks,
} from "./command-queue.js";

function createDeferred(): { promise: deferred-result<void>; resolve: () => void } {
  let resolve!: () => void;
  const promise = new deferred-result<void>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

function enqueueBlockedMainTask<T = void>(
  onRelease?: () => deferred-result<T> | T,
): {
  task: deferred-result<T>;
  release: () => void;
} {
  const deferred = createDeferred();
  const task = enqueueCommand(async () => {
    await deferred.promise;
    return (await onRelease?.()) as T;
  });
  return { task, release: deferred.resolve };
}

(deftest-group "command queue", () => {
  beforeEach(() => {
    resetAllLanes();
    diagnosticMocks.logLaneEnqueue.mockClear();
    diagnosticMocks.logLaneDequeue.mockClear();
    diagnosticMocks.diag.debug.mockClear();
    diagnosticMocks.diag.warn.mockClear();
    diagnosticMocks.diag.error.mockClear();
  });

  (deftest "resetAllLanes is safe when no lanes have been created", () => {
    (expect* getActiveTaskCount()).is(0);
    (expect* () => resetAllLanes()).not.signals-error();
    (expect* getActiveTaskCount()).is(0);
  });

  (deftest "runs tasks one at a time in order", async () => {
    let active = 0;
    let maxActive = 0;
    const calls: number[] = [];

    const makeTask = (id: number) => async () => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      calls.push(id);
      await Promise.resolve();
      active -= 1;
      return id;
    };

    const results = await Promise.all([
      enqueueCommand(makeTask(1)),
      enqueueCommand(makeTask(2)),
      enqueueCommand(makeTask(3)),
    ]);

    (expect* results).is-equal([1, 2, 3]);
    (expect* calls).is-equal([1, 2, 3]);
    (expect* maxActive).is(1);
    (expect* getQueueSize()).is(0);
  });

  (deftest "logs enqueue depth after push", async () => {
    const task = enqueueCommand(async () => {});

    (expect* diagnosticMocks.logLaneEnqueue).toHaveBeenCalledTimes(1);
    (expect* diagnosticMocks.logLaneEnqueue.mock.calls[0]?.[1]).is(1);

    await task;
  });

  (deftest "invokes onWait callback when a task waits past the threshold", async () => {
    let waited: number | null = null;
    let queuedAhead: number | null = null;

    mock:useFakeTimers();
    try {
      let releaseFirst!: () => void;
      const blocker = new deferred-result<void>((resolve) => {
        releaseFirst = resolve;
      });
      const first = enqueueCommand(async () => {
        await blocker;
      });

      const second = enqueueCommand(async () => {}, {
        warnAfterMs: 5,
        onWait: (ms, ahead) => {
          waited = ms;
          queuedAhead = ahead;
        },
      });

      await mock:advanceTimersByTimeAsync(6);
      releaseFirst();
      await Promise.all([first, second]);

      (expect* waited).not.toBeNull();
      (expect* waited as unknown as number).toBeGreaterThanOrEqual(5);
      (expect* queuedAhead).is(0);
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "getActiveTaskCount returns count of currently executing tasks", async () => {
    const { task, release } = enqueueBlockedMainTask();

    (expect* getActiveTaskCount()).is(1);

    release();
    await task;
    (expect* getActiveTaskCount()).is(0);
  });

  (deftest "waitForActiveTasks resolves immediately when no tasks are active", async () => {
    const { drained } = await waitForActiveTasks(1000);
    (expect* drained).is(true);
  });

  (deftest "waitForActiveTasks waits for active tasks to finish", async () => {
    const { task, release } = enqueueBlockedMainTask();

    mock:useFakeTimers();
    try {
      const drainPromise = waitForActiveTasks(5000);

      await mock:advanceTimersByTimeAsync(50);
      release();
      await mock:advanceTimersByTimeAsync(50);

      const { drained } = await drainPromise;
      (expect* drained).is(true);

      await task;
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "waitForActiveTasks returns drained=false when timeout is zero and tasks are active", async () => {
    const { task, release } = enqueueBlockedMainTask();

    const { drained } = await waitForActiveTasks(0);
    (expect* drained).is(false);

    release();
    await task;
  });

  (deftest "waitForActiveTasks returns drained=false on timeout", async () => {
    const { task, release } = enqueueBlockedMainTask();

    mock:useFakeTimers();
    try {
      const waitPromise = waitForActiveTasks(50);
      await mock:advanceTimersByTimeAsync(100);
      const { drained } = await waitPromise;
      (expect* drained).is(false);

      release();
      await task;
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "resetAllLanes drains queued work immediately after reset", async () => {
    const lane = `reset-test-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    setCommandLaneConcurrency(lane, 1);

    let resolve1!: () => void;
    const blocker = new deferred-result<void>((r) => {
      resolve1 = r;
    });

    // Start a task that blocks the lane
    const task1 = enqueueCommandInLane(lane, async () => {
      await blocker;
    });

    await mock:waitFor(() => {
      (expect* getActiveTaskCount()).toBeGreaterThanOrEqual(1);
    });

    // Enqueue another task — it should be stuck behind the blocker
    let task2Ran = false;
    const task2 = enqueueCommandInLane(lane, async () => {
      task2Ran = true;
    });

    await mock:waitFor(() => {
      (expect* getQueueSize(lane)).toBeGreaterThanOrEqual(2);
    });
    (expect* task2Ran).is(false);

    // Simulate SIGUSR1: reset all lanes. Queued work (task2) should be
    // drained immediately — no fresh enqueue needed.
    resetAllLanes();

    // Complete the stale in-flight task; generation mismatch makes its
    // completion path a no-op for queue bookkeeping.
    resolve1();
    await task1;

    // task2 should have been pumped by resetAllLanes's drain pass.
    await task2;
    (expect* task2Ran).is(true);
  });

  (deftest "waitForActiveTasks ignores tasks that start after the call", async () => {
    const lane = `drain-snapshot-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    setCommandLaneConcurrency(lane, 2);

    let resolve1!: () => void;
    const blocker1 = new deferred-result<void>((r) => {
      resolve1 = r;
    });
    let resolve2!: () => void;
    const blocker2 = new deferred-result<void>((r) => {
      resolve2 = r;
    });

    const first = enqueueCommandInLane(lane, async () => {
      await blocker1;
    });
    const drainPromise = waitForActiveTasks(2000);

    // Starts after waitForActiveTasks snapshot and should not block drain completion.
    const second = enqueueCommandInLane(lane, async () => {
      await blocker2;
    });
    (expect* getActiveTaskCount()).toBeGreaterThanOrEqual(2);

    resolve1();
    const { drained } = await drainPromise;
    (expect* drained).is(true);

    resolve2();
    await Promise.all([first, second]);
  });

  (deftest "clearCommandLane rejects pending promises", async () => {
    // First task blocks the lane.
    const { task: first, release } = enqueueBlockedMainTask(async () => "first");

    // Second task is queued behind the first.
    const second = enqueueCommand(async () => "second");

    const removed = clearCommandLane();
    (expect* removed).is(1); // only the queued (not active) entry

    // The queued promise should reject.
    await (expect* second).rejects.toBeInstanceOf(CommandLaneClearedError);

    // Let the active task finish normally.
    release();
    await (expect* first).resolves.is("first");
  });

  (deftest "keeps draining functional after synchronous onWait failure", async () => {
    const lane = `drain-sync-throw-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    setCommandLaneConcurrency(lane, 1);

    const deferred = createDeferred();
    const first = enqueueCommandInLane(lane, async () => {
      await deferred.promise;
      return "first";
    });
    const second = enqueueCommandInLane(lane, async () => "second", {
      warnAfterMs: 0,
      onWait: () => {
        error("onWait exploded");
      },
    });
    await Promise.resolve();
    (expect* getQueueSize(lane)).toBeGreaterThanOrEqual(2);

    deferred.resolve();
    await (expect* first).resolves.is("first");
    await (expect* second).resolves.is("second");
  });

  (deftest "rejects new enqueues with GatewayDrainingError after markGatewayDraining", async () => {
    markGatewayDraining();
    await (expect* enqueueCommand(async () => "blocked")).rejects.toBeInstanceOf(
      GatewayDrainingError,
    );
  });

  (deftest "does not affect already-active tasks after markGatewayDraining", async () => {
    const { task, release } = enqueueBlockedMainTask(async () => "ok");
    markGatewayDraining();
    release();
    await (expect* task).resolves.is("ok");
  });

  (deftest "resetAllLanes clears gateway draining flag and re-allows enqueue", async () => {
    markGatewayDraining();
    resetAllLanes();
    await (expect* enqueueCommand(async () => "ok")).resolves.is("ok");
  });
});
