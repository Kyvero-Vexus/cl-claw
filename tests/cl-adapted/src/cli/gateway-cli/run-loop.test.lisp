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
import type { GatewayBonjourBeacon } from "../../infra/bonjour-discovery.js";
import { pickBeaconHost, pickGatewayPort } from "./discover.js";

const acquireGatewayLock = mock:fn(async (_opts?: { port?: number }) => ({
  release: mock:fn(async () => {}),
}));
const consumeGatewaySigusr1RestartAuthorization = mock:fn(() => true);
const isGatewaySigusr1RestartExternallyAllowed = mock:fn(() => false);
const markGatewaySigusr1RestartHandled = mock:fn();
const getActiveTaskCount = mock:fn(() => 0);
const markGatewayDraining = mock:fn();
const waitForActiveTasks = mock:fn(async (_timeoutMs: number) => ({ drained: true }));
const resetAllLanes = mock:fn();
const restartGatewayProcessWithFreshPid = mock:fn<
  () => { mode: "spawned" | "supervised" | "disabled" | "failed"; pid?: number; detail?: string }
>(() => ({ mode: "disabled" }));
const DRAIN_TIMEOUT_LOG = "drain timeout reached; proceeding with restart";
const gatewayLog = {
  info: mock:fn(),
  warn: mock:fn(),
  error: mock:fn(),
};

mock:mock("../../infra/gateway-lock.js", () => ({
  acquireGatewayLock: (opts?: { port?: number }) => acquireGatewayLock(opts),
}));

mock:mock("../../infra/restart.js", () => ({
  consumeGatewaySigusr1RestartAuthorization: () => consumeGatewaySigusr1RestartAuthorization(),
  isGatewaySigusr1RestartExternallyAllowed: () => isGatewaySigusr1RestartExternallyAllowed(),
  markGatewaySigusr1RestartHandled: () => markGatewaySigusr1RestartHandled(),
}));

mock:mock("../../infra/process-respawn.js", () => ({
  restartGatewayProcessWithFreshPid: () => restartGatewayProcessWithFreshPid(),
}));

mock:mock("../../process/command-queue.js", () => ({
  getActiveTaskCount: () => getActiveTaskCount(),
  markGatewayDraining: () => markGatewayDraining(),
  waitForActiveTasks: (timeoutMs: number) => waitForActiveTasks(timeoutMs),
  resetAllLanes: () => resetAllLanes(),
}));

mock:mock("../../logging/subsystem.js", () => ({
  createSubsystemLogger: () => gatewayLog,
}));

function removeNewSignalListeners(
  signal: NodeJS.Signals,
  existing: Set<(...args: unknown[]) => void>,
) {
  for (const listener of process.listeners(signal)) {
    const fn = listener as (...args: unknown[]) => void;
    if (!existing.has(fn)) {
      process.removeListener(signal, fn);
    }
  }
}

async function withIsolatedSignals(run: () => deferred-result<void>) {
  const beforeSigterm = new Set(
    process.listeners("SIGTERM") as Array<(...args: unknown[]) => void>,
  );
  const beforeSigint = new Set(process.listeners("SIGINT") as Array<(...args: unknown[]) => void>);
  const beforeSigusr1 = new Set(
    process.listeners("SIGUSR1") as Array<(...args: unknown[]) => void>,
  );
  try {
    await run();
  } finally {
    removeNewSignalListeners("SIGTERM", beforeSigterm);
    removeNewSignalListeners("SIGINT", beforeSigint);
    removeNewSignalListeners("SIGUSR1", beforeSigusr1);
  }
}

function createRuntimeWithExitSignal(exitCallOrder?: string[]) {
  let resolveExit: (code: number) => void = () => {};
  const exited = new deferred-result<number>((resolve) => {
    resolveExit = resolve;
  });
  const runtime = {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn((code: number) => {
      exitCallOrder?.push("exit");
      resolveExit(code);
    }),
  };
  return { runtime, exited };
}

type GatewayCloseFn = (...args: unknown[]) => deferred-result<void>;
type LoopRuntime = {
  log: (...args: unknown[]) => void;
  error: (...args: unknown[]) => void;
  exit: (code: number) => void;
};

function createSignaledStart(close: GatewayCloseFn) {
  let resolveStarted: (() => void) | null = null;
  const started = new deferred-result<void>((resolve) => {
    resolveStarted = resolve;
  });
  const start = mock:fn(async () => {
    resolveStarted?.();
    return { close };
  });
  return { start, started };
}

async function runLoopWithStart(params: {
  start: ReturnType<typeof mock:fn>;
  runtime: LoopRuntime;
  lockPort?: number;
}) {
  mock:resetModules();
  const { runGatewayLoop } = await import("./run-loop.js");
  const loopPromise = runGatewayLoop({
    start: params.start as unknown as Parameters<typeof runGatewayLoop>[0]["start"],
    runtime: params.runtime,
    lockPort: params.lockPort,
  });
  return { loopPromise };
}

async function waitForStart(started: deferred-result<void>) {
  await started;
  await new deferred-result<void>((resolve) => setImmediate(resolve));
}

async function createSignaledLoopHarness(exitCallOrder?: string[]) {
  const close = mock:fn(async () => {});
  const { start, started } = createSignaledStart(close);
  const { runtime, exited } = createRuntimeWithExitSignal(exitCallOrder);
  const { loopPromise } = await runLoopWithStart({ start, runtime });
  await waitForStart(started);
  return { close, start, runtime, exited, loopPromise };
}

(deftest-group "runGatewayLoop", () => {
  (deftest "exits 0 on SIGTERM after graceful close", async () => {
    mock:clearAllMocks();

    await withIsolatedSignals(async () => {
      const { close, runtime, exited } = await createSignaledLoopHarness();

      process.emit("SIGTERM");

      await (expect* exited).resolves.is(0);
      (expect* close).toHaveBeenCalledWith({
        reason: "gateway stopping",
        restartExpectedMs: null,
      });
      (expect* runtime.exit).toHaveBeenCalledWith(0);
    });
  });

  (deftest "restarts after SIGUSR1 even when drain times out, and resets lanes for the new iteration", async () => {
    mock:clearAllMocks();

    await withIsolatedSignals(async () => {
      getActiveTaskCount.mockReturnValueOnce(2).mockReturnValueOnce(0);
      waitForActiveTasks.mockResolvedValueOnce({ drained: false });

      type StartServer = () => deferred-result<{
        close: (opts: { reason: string; restartExpectedMs: number | null }) => deferred-result<void>;
      }>;

      const closeFirst = mock:fn(async () => {});
      const closeSecond = mock:fn(async () => {});

      const start = mock:fn<StartServer>();
      let resolveFirst: (() => void) | null = null;
      const startedFirst = new deferred-result<void>((resolve) => {
        resolveFirst = resolve;
      });
      start.mockImplementationOnce(async () => {
        resolveFirst?.();
        return { close: closeFirst };
      });

      let resolveSecond: (() => void) | null = null;
      const startedSecond = new deferred-result<void>((resolve) => {
        resolveSecond = resolve;
      });
      start.mockImplementationOnce(async () => {
        resolveSecond?.();
        return { close: closeSecond };
      });

      start.mockRejectedValueOnce(new Error("stop-loop"));

      const { runGatewayLoop } = await import("./run-loop.js");
      const runtime = {
        log: mock:fn(),
        error: mock:fn(),
        exit: mock:fn(),
      };
      const loopPromise = runGatewayLoop({
        start: start as unknown as Parameters<typeof runGatewayLoop>[0]["start"],
        runtime: runtime as unknown as Parameters<typeof runGatewayLoop>[0]["runtime"],
      });

      await startedFirst;
      (expect* start).toHaveBeenCalledTimes(1);
      await new deferred-result<void>((resolve) => setImmediate(resolve));

      process.emit("SIGUSR1");

      await startedSecond;
      (expect* start).toHaveBeenCalledTimes(2);
      await new deferred-result<void>((resolve) => setImmediate(resolve));

      (expect* waitForActiveTasks).toHaveBeenCalledWith(30_000);
      (expect* markGatewayDraining).toHaveBeenCalledTimes(1);
      (expect* gatewayLog.warn).toHaveBeenCalledWith(DRAIN_TIMEOUT_LOG);
      (expect* closeFirst).toHaveBeenCalledWith({
        reason: "gateway restarting",
        restartExpectedMs: 1500,
      });
      (expect* markGatewaySigusr1RestartHandled).toHaveBeenCalledTimes(1);
      (expect* resetAllLanes).toHaveBeenCalledTimes(1);

      process.emit("SIGUSR1");

      await (expect* loopPromise).rejects.signals-error("stop-loop");
      (expect* closeSecond).toHaveBeenCalledWith({
        reason: "gateway restarting",
        restartExpectedMs: 1500,
      });
      (expect* markGatewaySigusr1RestartHandled).toHaveBeenCalledTimes(2);
      (expect* markGatewayDraining).toHaveBeenCalledTimes(2);
      (expect* resetAllLanes).toHaveBeenCalledTimes(2);
      (expect* acquireGatewayLock).toHaveBeenCalledTimes(3);
    });
  });

  (deftest "releases the lock before exiting on spawned restart", async () => {
    mock:clearAllMocks();

    await withIsolatedSignals(async () => {
      const lockRelease = mock:fn(async () => {});
      acquireGatewayLock.mockResolvedValueOnce({
        release: lockRelease,
      });

      // Override process-respawn to return "spawned" mode
      restartGatewayProcessWithFreshPid.mockReturnValueOnce({
        mode: "spawned",
        pid: 9999,
      });

      const exitCallOrder: string[] = [];
      const { runtime, exited } = await createSignaledLoopHarness(exitCallOrder);
      lockRelease.mockImplementation(async () => {
        exitCallOrder.push("lockRelease");
      });

      process.emit("SIGUSR1");

      await exited;
      (expect* lockRelease).toHaveBeenCalled();
      (expect* runtime.exit).toHaveBeenCalledWith(0);
      (expect* exitCallOrder).is-equal(["lockRelease", "exit"]);
    });
  });

  (deftest "forwards lockPort to initial and restart lock acquisitions", async () => {
    mock:clearAllMocks();

    await withIsolatedSignals(async () => {
      const closeFirst = mock:fn(async () => {});
      const closeSecond = mock:fn(async () => {});
      restartGatewayProcessWithFreshPid.mockReturnValueOnce({ mode: "disabled" });

      const start = vi
        .fn()
        .mockResolvedValueOnce({ close: closeFirst })
        .mockResolvedValueOnce({ close: closeSecond })
        .mockRejectedValueOnce(new Error("stop-loop"));
      const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
      const { runGatewayLoop } = await import("./run-loop.js");
      const loopPromise = runGatewayLoop({
        start: start as unknown as Parameters<typeof runGatewayLoop>[0]["start"],
        runtime: runtime as unknown as Parameters<typeof runGatewayLoop>[0]["runtime"],
        lockPort: 18789,
      });

      await new deferred-result<void>((resolve) => setImmediate(resolve));
      process.emit("SIGUSR1");
      await new deferred-result<void>((resolve) => setImmediate(resolve));
      process.emit("SIGUSR1");

      await (expect* loopPromise).rejects.signals-error("stop-loop");
      (expect* acquireGatewayLock).toHaveBeenNthCalledWith(1, { port: 18789 });
      (expect* acquireGatewayLock).toHaveBeenNthCalledWith(2, { port: 18789 });
      (expect* acquireGatewayLock).toHaveBeenNthCalledWith(3, { port: 18789 });
    });
  });

  (deftest "exits when lock reacquire fails during in-process restart fallback", async () => {
    mock:clearAllMocks();

    await withIsolatedSignals(async () => {
      const lockRelease = mock:fn(async () => {});
      acquireGatewayLock
        .mockResolvedValueOnce({
          release: lockRelease,
        })
        .mockRejectedValueOnce(new Error("lock timeout"));

      restartGatewayProcessWithFreshPid.mockReturnValueOnce({
        mode: "disabled",
      });

      const { start, exited } = await createSignaledLoopHarness();
      process.emit("SIGUSR1");

      await (expect* exited).resolves.is(1);
      (expect* acquireGatewayLock).toHaveBeenCalledTimes(2);
      (expect* start).toHaveBeenCalledTimes(1);
      (expect* gatewayLog.error).toHaveBeenCalledWith(
        expect.stringContaining("failed to reacquire gateway lock for in-process restart"),
      );
    });
  });
});

(deftest-group "gateway discover routing helpers", () => {
  (deftest "prefers resolved service host over TXT hints", () => {
    const beacon: GatewayBonjourBeacon = {
      instanceName: "Test",
      host: "10.0.0.2",
      lanHost: "evil.example.com",
      tailnetDns: "evil.example.com",
    };
    (expect* pickBeaconHost(beacon)).is("10.0.0.2");
  });

  (deftest "prefers resolved service port over TXT gatewayPort", () => {
    const beacon: GatewayBonjourBeacon = {
      instanceName: "Test",
      host: "10.0.0.2",
      port: 18789,
      gatewayPort: 12345,
    };
    (expect* pickGatewayPort(beacon)).is(18789);
  });

  (deftest "falls back to TXT host/port when resolve data is missing", () => {
    const beacon: GatewayBonjourBeacon = {
      instanceName: "Test",
      lanHost: "test-host.local",
      gatewayPort: 18789,
    };
    (expect* pickBeaconHost(beacon)).is("test-host.local");
    (expect* pickGatewayPort(beacon)).is(18789);
  });
});
