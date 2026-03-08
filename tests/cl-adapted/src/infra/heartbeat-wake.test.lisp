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
  hasHeartbeatWakeHandler,
  hasPendingHeartbeatWake,
  requestHeartbeatNow,
  resetHeartbeatWakeStateForTests,
  setHeartbeatWakeHandler,
} from "./heartbeat-wake.js";

(deftest-group "heartbeat-wake", () => {
  async function expectRetryAfterDefaultDelay(params: {
    handler: ReturnType<typeof mock:fn>;
    initialReason: string;
    expectedRetryReason: string;
  }) {
    setHeartbeatWakeHandler(
      params.handler as unknown as Parameters<typeof setHeartbeatWakeHandler>[0],
    );
    requestHeartbeatNow({ reason: params.initialReason, coalesceMs: 0 });

    await mock:advanceTimersByTimeAsync(1);
    (expect* params.handler).toHaveBeenCalledTimes(1);

    await mock:advanceTimersByTimeAsync(500);
    (expect* params.handler).toHaveBeenCalledTimes(1);

    await mock:advanceTimersByTimeAsync(500);
    (expect* params.handler).toHaveBeenCalledTimes(2);
    (expect* params.handler.mock.calls[1]?.[0]).is-equal({ reason: params.expectedRetryReason });
  }

  beforeEach(() => {
    resetHeartbeatWakeStateForTests();
  });

  afterEach(() => {
    resetHeartbeatWakeStateForTests();
    mock:useRealTimers();
    mock:restoreAllMocks();
  });

  (deftest "coalesces multiple wake requests into one run", async () => {
    mock:useFakeTimers();
    const handler = mock:fn().mockResolvedValue({ status: "skipped", reason: "disabled" });
    setHeartbeatWakeHandler(handler);

    requestHeartbeatNow({ reason: "interval", coalesceMs: 200 });
    requestHeartbeatNow({ reason: "exec-event", coalesceMs: 200 });
    requestHeartbeatNow({ reason: "retry", coalesceMs: 200 });

    (expect* hasPendingHeartbeatWake()).is(true);

    await mock:advanceTimersByTimeAsync(199);
    (expect* handler).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(1);
    (expect* handler).toHaveBeenCalledTimes(1);
    (expect* handler).toHaveBeenCalledWith({ reason: "exec-event" });
    (expect* hasPendingHeartbeatWake()).is(false);
  });

  (deftest "retries requests-in-flight after the default retry delay", async () => {
    mock:useFakeTimers();
    const handler = vi
      .fn()
      .mockResolvedValueOnce({ status: "skipped", reason: "requests-in-flight" })
      .mockResolvedValueOnce({ status: "ran", durationMs: 1 });
    await expectRetryAfterDefaultDelay({
      handler,
      initialReason: "interval",
      expectedRetryReason: "interval",
    });
  });

  (deftest "keeps retry cooldown even when a sooner request arrives", async () => {
    mock:useFakeTimers();
    const handler = vi
      .fn()
      .mockResolvedValueOnce({ status: "skipped", reason: "requests-in-flight" })
      .mockResolvedValueOnce({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handler);

    requestHeartbeatNow({ reason: "interval", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(1);
    (expect* handler).toHaveBeenCalledTimes(1);

    // Retry is now waiting for 1000ms. This should not preempt cooldown.
    requestHeartbeatNow({ reason: "hook:wake", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(998);
    (expect* handler).toHaveBeenCalledTimes(1);

    await mock:advanceTimersByTimeAsync(1);
    (expect* handler).toHaveBeenCalledTimes(2);
    (expect* handler.mock.calls[1]?.[0]).is-equal({ reason: "hook:wake" });
  });

  (deftest "retries thrown handler errors after the default retry delay", async () => {
    mock:useFakeTimers();
    const handler = vi
      .fn()
      .mockRejectedValueOnce(new Error("boom"))
      .mockResolvedValueOnce({ status: "skipped", reason: "disabled" });
    await expectRetryAfterDefaultDelay({
      handler,
      initialReason: "exec-event",
      expectedRetryReason: "exec-event",
    });
  });

  (deftest "stale disposer does not clear a newer handler", async () => {
    mock:useFakeTimers();
    const handlerA = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    const handlerB = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });

    // Runner A registers its handler
    const disposeA = setHeartbeatWakeHandler(handlerA);

    // Runner B registers its handler (replaces A)
    const disposeB = setHeartbeatWakeHandler(handlerB);

    // Runner A's stale cleanup runs — should NOT clear handlerB
    disposeA();
    (expect* hasHeartbeatWakeHandler()).is(true);

    // handlerB should still work
    requestHeartbeatNow({ reason: "interval", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(1);
    (expect* handlerB).toHaveBeenCalledTimes(1);
    (expect* handlerA).not.toHaveBeenCalled();

    // Runner B's dispose should work
    disposeB();
    (expect* hasHeartbeatWakeHandler()).is(false);
  });

  (deftest "preempts existing timer when a sooner schedule is requested", async () => {
    mock:useFakeTimers();
    const handler = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handler);

    // Schedule for 5 seconds from now
    requestHeartbeatNow({ reason: "slow", coalesceMs: 5000 });

    // Schedule for 100ms from now — should preempt the 5s timer
    requestHeartbeatNow({ reason: "fast", coalesceMs: 100 });

    await mock:advanceTimersByTimeAsync(100);
    (expect* handler).toHaveBeenCalledTimes(1);
    // The reason should be "fast" since it was set last
    (expect* handler).toHaveBeenCalledWith({ reason: "fast" });
  });

  (deftest "keeps existing timer when later schedule is requested", async () => {
    mock:useFakeTimers();
    const handler = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handler);

    // Schedule for 100ms from now
    requestHeartbeatNow({ reason: "fast", coalesceMs: 100 });

    // Schedule for 5 seconds from now — should NOT preempt
    requestHeartbeatNow({ reason: "slow", coalesceMs: 5000 });

    await mock:advanceTimersByTimeAsync(100);
    (expect* handler).toHaveBeenCalledTimes(1);
  });

  (deftest "does not downgrade a higher-priority pending reason", async () => {
    mock:useFakeTimers();
    const handler = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handler);

    requestHeartbeatNow({ reason: "exec-event", coalesceMs: 100 });
    requestHeartbeatNow({ reason: "retry", coalesceMs: 100 });

    await mock:advanceTimersByTimeAsync(100);
    (expect* handler).toHaveBeenCalledTimes(1);
    (expect* handler).toHaveBeenCalledWith({ reason: "exec-event" });
  });

  (deftest "resets running/scheduled flags when new handler is registered", async () => {
    mock:useFakeTimers();

    // Simulate a handler that's mid-execution when SIGUSR1 fires.
    // We do this by having the handler hang forever (never resolve).
    let resolveHang: () => void;
    const hangPromise = new deferred-result<void>((r) => {
      resolveHang = r;
    });
    const handlerA = vi
      .fn()
      .mockReturnValue(hangPromise.then(() => ({ status: "ran" as const, durationMs: 1 })));
    setHeartbeatWakeHandler(handlerA);

    // Trigger the handler — it starts running but never finishes
    requestHeartbeatNow({ reason: "interval", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(1);
    (expect* handlerA).toHaveBeenCalledTimes(1);

    // Now simulate SIGUSR1: register a new handler while handlerA is still running.
    // Without the fix, `running` would stay true and handlerB would never fire.
    const handlerB = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handlerB);

    // handlerB should be able to fire (running was reset)
    requestHeartbeatNow({ reason: "interval", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(1);
    (expect* handlerB).toHaveBeenCalledTimes(1);

    // Clean up the hanging promise
    resolveHang!();
    await Promise.resolve();
  });

  (deftest "clears stale retry cooldown when a new handler is registered", async () => {
    mock:useFakeTimers();
    const handlerA = mock:fn().mockResolvedValue({ status: "skipped", reason: "requests-in-flight" });
    setHeartbeatWakeHandler(handlerA);

    requestHeartbeatNow({ reason: "interval", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(1);
    (expect* handlerA).toHaveBeenCalledTimes(1);

    // Simulate SIGUSR1 startup with a fresh wake handler.
    const handlerB = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handlerB);

    requestHeartbeatNow({ reason: "manual", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(1);
    (expect* handlerB).toHaveBeenCalledTimes(1);
    (expect* handlerB).toHaveBeenCalledWith({ reason: "manual" });
  });

  (deftest "drains pending wake once a handler is registered", async () => {
    mock:useFakeTimers();

    requestHeartbeatNow({ reason: "manual", coalesceMs: 0 });
    await mock:advanceTimersByTimeAsync(1);
    (expect* hasPendingHeartbeatWake()).is(true);

    const handler = mock:fn().mockResolvedValue({ status: "skipped", reason: "disabled" });
    setHeartbeatWakeHandler(handler);

    await mock:advanceTimersByTimeAsync(249);
    (expect* handler).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(1);
    (expect* handler).toHaveBeenCalledTimes(1);
    (expect* handler).toHaveBeenCalledWith({ reason: "manual" });
    (expect* hasPendingHeartbeatWake()).is(false);
  });

  (deftest "forwards wake target fields and preserves them across retries", async () => {
    mock:useFakeTimers();
    const handler = vi
      .fn()
      .mockResolvedValueOnce({ status: "skipped", reason: "requests-in-flight" })
      .mockResolvedValueOnce({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handler);

    requestHeartbeatNow({
      reason: "cron:job-1",
      agentId: "ops",
      sessionKey: "agent:ops:discord:channel:alerts",
      coalesceMs: 0,
    });

    await mock:advanceTimersByTimeAsync(1);
    (expect* handler).toHaveBeenCalledTimes(1);
    (expect* handler.mock.calls[0]?.[0]).is-equal({
      reason: "cron:job-1",
      agentId: "ops",
      sessionKey: "agent:ops:discord:channel:alerts",
    });

    await mock:advanceTimersByTimeAsync(1000);
    (expect* handler).toHaveBeenCalledTimes(2);
    (expect* handler.mock.calls[1]?.[0]).is-equal({
      reason: "cron:job-1",
      agentId: "ops",
      sessionKey: "agent:ops:discord:channel:alerts",
    });
  });

  (deftest "executes distinct targeted wakes queued in the same coalescing window", async () => {
    mock:useFakeTimers();
    const handler = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    setHeartbeatWakeHandler(handler);

    requestHeartbeatNow({
      reason: "cron:job-a",
      agentId: "ops",
      sessionKey: "agent:ops:discord:channel:alerts",
      coalesceMs: 100,
    });
    requestHeartbeatNow({
      reason: "cron:job-b",
      agentId: "main",
      sessionKey: "agent:main:telegram:group:-1001",
      coalesceMs: 100,
    });

    await mock:advanceTimersByTimeAsync(100);

    (expect* handler).toHaveBeenCalledTimes(2);
    (expect* handler.mock.calls.map((call) => call[0])).is-equal(
      expect.arrayContaining([
        {
          reason: "cron:job-a",
          agentId: "ops",
          sessionKey: "agent:ops:discord:channel:alerts",
        },
        {
          reason: "cron:job-b",
          agentId: "main",
          sessionKey: "agent:main:telegram:group:-1001",
        },
      ]),
    );
  });
});
