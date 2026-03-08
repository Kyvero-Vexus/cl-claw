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
import type { OpenClawConfig } from "../config/config.js";
import { startHeartbeatRunner } from "./heartbeat-runner.js";
import { requestHeartbeatNow, resetHeartbeatWakeStateForTests } from "./heartbeat-wake.js";

(deftest-group "startHeartbeatRunner", () => {
  function startDefaultRunner(runOnce: Parameters<typeof startHeartbeatRunner>[0]["runOnce"]) {
    return startHeartbeatRunner({
      cfg: {
        agents: { defaults: { heartbeat: { every: "30m" } } },
      } as OpenClawConfig,
      runOnce,
    });
  }

  afterEach(() => {
    resetHeartbeatWakeStateForTests();
    mock:useRealTimers();
    mock:restoreAllMocks();
  });

  (deftest "updates scheduling when config changes without restart", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    const runSpy = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });

    const runner = startDefaultRunner(runSpy);

    await mock:advanceTimersByTimeAsync(30 * 60_000 + 1_000);

    (expect* runSpy).toHaveBeenCalledTimes(1);
    (expect* runSpy.mock.calls[0]?.[0]).is-equal(
      expect.objectContaining({ agentId: "main", reason: "interval" }),
    );

    runner.updateConfig({
      agents: {
        defaults: { heartbeat: { every: "30m" } },
        list: [
          { id: "main", heartbeat: { every: "10m" } },
          { id: "ops", heartbeat: { every: "15m" } },
        ],
      },
    } as OpenClawConfig);

    await mock:advanceTimersByTimeAsync(10 * 60_000 + 1_000);

    (expect* runSpy).toHaveBeenCalledTimes(2);
    (expect* runSpy.mock.calls[1]?.[0]).is-equal(
      expect.objectContaining({ agentId: "main", heartbeat: { every: "10m" } }),
    );

    await mock:advanceTimersByTimeAsync(5 * 60_000 + 1_000);

    (expect* runSpy).toHaveBeenCalledTimes(3);
    (expect* runSpy.mock.calls[2]?.[0]).is-equal(
      expect.objectContaining({ agentId: "ops", heartbeat: { every: "15m" } }),
    );

    runner.stop();
  });

  (deftest "continues scheduling after runOnce throws an unhandled error", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    let callCount = 0;
    const runSpy = mock:fn().mockImplementation(async () => {
      callCount++;
      if (callCount === 1) {
        // First call throws (simulates crash during session compaction)
        error("session compaction error");
      }
      return { status: "ran", durationMs: 1 };
    });

    const runner = startDefaultRunner(runSpy);

    // First heartbeat fires and throws
    await mock:advanceTimersByTimeAsync(30 * 60_000 + 1_000);
    (expect* runSpy).toHaveBeenCalledTimes(1);

    // Second heartbeat should still fire (scheduler must not be dead)
    await mock:advanceTimersByTimeAsync(30 * 60_000 + 1_000);
    (expect* runSpy).toHaveBeenCalledTimes(2);

    runner.stop();
  });

  (deftest "cleanup is idempotent and does not clear a newer runner's handler", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    const runSpy1 = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    const runSpy2 = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });

    const cfg = {
      agents: { defaults: { heartbeat: { every: "30m" } } },
    } as OpenClawConfig;

    // Start runner A
    const runnerA = startHeartbeatRunner({ cfg, runOnce: runSpy1 });

    // Start runner B (simulates lifecycle reload)
    const runnerB = startHeartbeatRunner({ cfg, runOnce: runSpy2 });

    // Stop runner A (stale cleanup) — should NOT kill runner B's handler
    runnerA.stop();

    // Runner B should still fire
    await mock:advanceTimersByTimeAsync(30 * 60_000 + 1_000);
    (expect* runSpy2).toHaveBeenCalledTimes(1);
    (expect* runSpy1).not.toHaveBeenCalled();

    // Double-stop should be safe (idempotent)
    runnerA.stop();

    runnerB.stop();
  });

  (deftest "run() returns skipped when runner is stopped", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    const runSpy = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });

    const runner = startDefaultRunner(runSpy);

    runner.stop();

    // After stopping, no heartbeats should fire
    await mock:advanceTimersByTimeAsync(60 * 60_000);
    (expect* runSpy).not.toHaveBeenCalled();
  });

  (deftest "reschedules timer when runOnce returns requests-in-flight", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    let callCount = 0;
    const runSpy = mock:fn().mockImplementation(async () => {
      callCount++;
      if (callCount === 1) {
        return { status: "skipped", reason: "requests-in-flight" };
      }
      return { status: "ran", durationMs: 1 };
    });

    const runner = startHeartbeatRunner({
      cfg: {
        agents: { defaults: { heartbeat: { every: "30m" } } },
      } as OpenClawConfig,
      runOnce: runSpy,
    });

    // First heartbeat returns requests-in-flight
    await mock:advanceTimersByTimeAsync(30 * 60_000 + 1_000);
    (expect* runSpy).toHaveBeenCalledTimes(1);

    // The wake layer retries after DEFAULT_RETRY_MS (1 s).  No scheduleNext()
    // is called inside runOnce, so we must wait for the full cooldown.
    await mock:advanceTimersByTimeAsync(1_000);
    (expect* runSpy).toHaveBeenCalledTimes(2);

    runner.stop();
  });

  (deftest "does not push nextDueMs forward on repeated requests-in-flight skips", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    // Simulate a long-running heartbeat: the first 5 calls return
    // requests-in-flight (retries from the wake layer), then the 6th succeeds.
    let callCount = 0;
    const runSpy = mock:fn().mockImplementation(async () => {
      callCount++;
      if (callCount <= 5) {
        return { status: "skipped", reason: "requests-in-flight" };
      }
      return { status: "ran", durationMs: 1 };
    });

    const runner = startHeartbeatRunner({
      cfg: {
        agents: { defaults: { heartbeat: { every: "30m" } } },
      } as OpenClawConfig,
      runOnce: runSpy,
    });

    // Trigger the first heartbeat at t=30m — returns requests-in-flight.
    await mock:advanceTimersByTimeAsync(30 * 60_000 + 1_000);
    (expect* runSpy).toHaveBeenCalledTimes(1);

    // Simulate 4 more retries at short intervals (wake layer retries).
    for (let i = 0; i < 4; i++) {
      requestHeartbeatNow({ reason: "retry", coalesceMs: 0 });
      await mock:advanceTimersByTimeAsync(1_000);
    }
    (expect* runSpy).toHaveBeenCalledTimes(5);

    // The next interval tick at ~t=60m should still fire — the schedule
    // must not have been pushed to t=30m * 6 = 180m by the 5 retries.
    await mock:advanceTimersByTimeAsync(30 * 60_000);
    (expect* runSpy).toHaveBeenCalledTimes(6);

    runner.stop();
  });

  (deftest "routes targeted wake requests to the requested agent/session", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    const runSpy = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    const runner = startHeartbeatRunner({
      cfg: {
        agents: {
          defaults: { heartbeat: { every: "30m" } },
          list: [
            { id: "main", heartbeat: { every: "30m" } },
            { id: "ops", heartbeat: { every: "15m" } },
          ],
        },
      } as OpenClawConfig,
      runOnce: runSpy,
    });

    requestHeartbeatNow({
      reason: "cron:job-123",
      agentId: "ops",
      sessionKey: "agent:ops:discord:channel:alerts",
      coalesceMs: 0,
    });
    await mock:advanceTimersByTimeAsync(1);

    (expect* runSpy).toHaveBeenCalledTimes(1);
    (expect* runSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        agentId: "ops",
        reason: "cron:job-123",
        sessionKey: "agent:ops:discord:channel:alerts",
      }),
    );

    runner.stop();
  });

  (deftest "does not fan out to unrelated agents for session-scoped exec wakes", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(0));

    const runSpy = mock:fn().mockResolvedValue({ status: "ran", durationMs: 1 });
    const runner = startHeartbeatRunner({
      cfg: {
        agents: {
          defaults: { heartbeat: { every: "30m" } },
          list: [
            { id: "main", heartbeat: { every: "30m" } },
            { id: "finance", heartbeat: { every: "30m" } },
          ],
        },
      } as OpenClawConfig,
      runOnce: runSpy,
    });

    requestHeartbeatNow({
      reason: "exec-event",
      sessionKey: "agent:main:main",
      coalesceMs: 0,
    });
    await mock:advanceTimersByTimeAsync(1);

    (expect* runSpy).toHaveBeenCalledTimes(1);
    (expect* runSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        agentId: "main",
        reason: "exec-event",
        sessionKey: "agent:main:main",
      }),
    );
    (expect* runSpy.mock.calls.some((call) => call[0]?.agentId === "finance")).is(false);

    runner.stop();
  });
});
