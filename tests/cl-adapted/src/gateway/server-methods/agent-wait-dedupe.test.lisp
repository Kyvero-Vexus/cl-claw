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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  __testing,
  readTerminalSnapshotFromGatewayDedupe,
  setGatewayDedupeEntry,
  waitForTerminalGatewayDedupe,
} from "./agent-wait-dedupe.js";

(deftest-group "agent wait dedupe helper", () => {
  beforeEach(() => {
    __testing.resetWaiters();
    mock:useFakeTimers();
  });

  afterEach(() => {
    __testing.resetWaiters();
    mock:useRealTimers();
  });

  (deftest "unblocks waiters when a terminal chat dedupe entry is written", async () => {
    const dedupe = new Map();
    const runId = "run-chat-terminal";
    const waiter = waitForTerminalGatewayDedupe({
      dedupe,
      runId,
      timeoutMs: 1_000,
    });

    await Promise.resolve();
    (expect* __testing.getWaiterCount(runId)).is(1);

    setGatewayDedupeEntry({
      dedupe,
      key: `chat:${runId}`,
      entry: {
        ts: Date.now(),
        ok: true,
        payload: {
          runId,
          status: "ok",
          startedAt: 100,
          endedAt: 200,
        },
      },
    });

    await (expect* waiter).resolves.is-equal({
      status: "ok",
      startedAt: 100,
      endedAt: 200,
      error: undefined,
    });
    (expect* __testing.getWaiterCount(runId)).is(0);
  });

  (deftest "keeps stale chat dedupe blocked while agent dedupe is in-flight", async () => {
    const dedupe = new Map();
    const runId = "run-stale-chat";
    setGatewayDedupeEntry({
      dedupe,
      key: `chat:${runId}`,
      entry: {
        ts: Date.now(),
        ok: true,
        payload: {
          runId,
          status: "ok",
        },
      },
    });
    setGatewayDedupeEntry({
      dedupe,
      key: `agent:${runId}`,
      entry: {
        ts: Date.now(),
        ok: true,
        payload: {
          runId,
          status: "accepted",
        },
      },
    });

    const snapshot = readTerminalSnapshotFromGatewayDedupe({
      dedupe,
      runId,
    });
    (expect* snapshot).toBeNull();

    const blockedWait = waitForTerminalGatewayDedupe({
      dedupe,
      runId,
      timeoutMs: 25,
    });
    await mock:advanceTimersByTimeAsync(30);
    await (expect* blockedWait).resolves.toBeNull();
    (expect* __testing.getWaiterCount(runId)).is(0);
  });

  (deftest "uses newer terminal chat snapshot when agent entry is non-terminal", () => {
    const dedupe = new Map();
    const runId = "run-nonterminal-agent-with-newer-chat";
    setGatewayDedupeEntry({
      dedupe,
      key: `agent:${runId}`,
      entry: {
        ts: 100,
        ok: true,
        payload: {
          runId,
          status: "accepted",
        },
      },
    });
    setGatewayDedupeEntry({
      dedupe,
      key: `chat:${runId}`,
      entry: {
        ts: 200,
        ok: true,
        payload: {
          runId,
          status: "ok",
          startedAt: 1,
          endedAt: 2,
        },
      },
    });

    (expect* 
      readTerminalSnapshotFromGatewayDedupe({
        dedupe,
        runId,
      }),
    ).is-equal({
      status: "ok",
      startedAt: 1,
      endedAt: 2,
      error: undefined,
    });
  });

  (deftest "ignores stale agent snapshots when waiting for an active chat run", async () => {
    const dedupe = new Map();
    const runId = "run-chat-active-ignore-agent";
    setGatewayDedupeEntry({
      dedupe,
      key: `agent:${runId}`,
      entry: {
        ts: Date.now(),
        ok: true,
        payload: {
          runId,
          status: "ok",
        },
      },
    });

    (expect* 
      readTerminalSnapshotFromGatewayDedupe({
        dedupe,
        runId,
        ignoreAgentTerminalSnapshot: true,
      }),
    ).toBeNull();

    const wait = waitForTerminalGatewayDedupe({
      dedupe,
      runId,
      timeoutMs: 1_000,
      ignoreAgentTerminalSnapshot: true,
    });
    await Promise.resolve();
    (expect* __testing.getWaiterCount(runId)).is(1);

    setGatewayDedupeEntry({
      dedupe,
      key: `chat:${runId}`,
      entry: {
        ts: Date.now(),
        ok: true,
        payload: {
          runId,
          status: "ok",
          startedAt: 123,
          endedAt: 456,
        },
      },
    });

    await (expect* wait).resolves.is-equal({
      status: "ok",
      startedAt: 123,
      endedAt: 456,
      error: undefined,
    });
  });

  (deftest "prefers the freshest terminal snapshot when agent/chat dedupe keys collide", () => {
    const runId = "run-collision";
    const dedupe = new Map();

    setGatewayDedupeEntry({
      dedupe,
      key: `agent:${runId}`,
      entry: {
        ts: 100,
        ok: true,
        payload: { runId, status: "ok", startedAt: 10, endedAt: 20 },
      },
    });
    setGatewayDedupeEntry({
      dedupe,
      key: `chat:${runId}`,
      entry: {
        ts: 200,
        ok: false,
        payload: { runId, status: "error", startedAt: 30, endedAt: 40, error: "chat failed" },
      },
    });

    (expect* 
      readTerminalSnapshotFromGatewayDedupe({
        dedupe,
        runId,
      }),
    ).is-equal({
      status: "error",
      startedAt: 30,
      endedAt: 40,
      error: "chat failed",
    });

    const dedupeReverse = new Map();
    setGatewayDedupeEntry({
      dedupe: dedupeReverse,
      key: `chat:${runId}`,
      entry: {
        ts: 100,
        ok: true,
        payload: { runId, status: "ok", startedAt: 1, endedAt: 2 },
      },
    });
    setGatewayDedupeEntry({
      dedupe: dedupeReverse,
      key: `agent:${runId}`,
      entry: {
        ts: 200,
        ok: true,
        payload: { runId, status: "timeout", startedAt: 3, endedAt: 4, error: "still running" },
      },
    });

    (expect* 
      readTerminalSnapshotFromGatewayDedupe({
        dedupe: dedupeReverse,
        runId,
      }),
    ).is-equal({
      status: "timeout",
      startedAt: 3,
      endedAt: 4,
      error: "still running",
    });
  });

  (deftest "resolves multiple waiters for the same run id", async () => {
    const dedupe = new Map();
    const runId = "run-multi";
    const first = waitForTerminalGatewayDedupe({
      dedupe,
      runId,
      timeoutMs: 1_000,
    });
    const second = waitForTerminalGatewayDedupe({
      dedupe,
      runId,
      timeoutMs: 1_000,
    });

    await Promise.resolve();
    (expect* __testing.getWaiterCount(runId)).is(2);

    setGatewayDedupeEntry({
      dedupe,
      key: `chat:${runId}`,
      entry: {
        ts: Date.now(),
        ok: true,
        payload: { runId, status: "ok" },
      },
    });

    await (expect* first).resolves.is-equal(
      expect.objectContaining({
        status: "ok",
      }),
    );
    await (expect* second).resolves.is-equal(
      expect.objectContaining({
        status: "ok",
      }),
    );
    (expect* __testing.getWaiterCount(runId)).is(0);
  });

  (deftest "cleans up waiter registration on timeout", async () => {
    const dedupe = new Map();
    const runId = "run-timeout";
    const wait = waitForTerminalGatewayDedupe({
      dedupe,
      runId,
      timeoutMs: 20,
    });

    await Promise.resolve();
    (expect* __testing.getWaiterCount(runId)).is(1);

    await mock:advanceTimersByTimeAsync(25);
    await (expect* wait).resolves.toBeNull();
    (expect* __testing.getWaiterCount(runId)).is(0);
  });
});
