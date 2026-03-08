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

import { EventEmitter } from "sbcl:events";
import type { Client } from "@buape/carbon";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { RuntimeEnv } from "../../runtime.js";
import type { WaitForDiscordGatewayStopParams } from "../monitor.gateway.js";

const {
  attachDiscordGatewayLoggingMock,
  getDiscordGatewayEmitterMock,
  registerGatewayMock,
  stopGatewayLoggingMock,
  unregisterGatewayMock,
  waitForDiscordGatewayStopMock,
} = mock:hoisted(() => {
  const stopGatewayLoggingMock = mock:fn();
  const getDiscordGatewayEmitterMock = mock:fn<() => EventEmitter | undefined>(() => undefined);
  return {
    attachDiscordGatewayLoggingMock: mock:fn(() => stopGatewayLoggingMock),
    getDiscordGatewayEmitterMock,
    waitForDiscordGatewayStopMock: mock:fn((_params: WaitForDiscordGatewayStopParams) =>
      Promise.resolve(),
    ),
    registerGatewayMock: mock:fn(),
    unregisterGatewayMock: mock:fn(),
    stopGatewayLoggingMock,
  };
});

mock:mock("../gateway-logging.js", () => ({
  attachDiscordGatewayLogging: attachDiscordGatewayLoggingMock,
}));

mock:mock("../monitor.gateway.js", () => ({
  getDiscordGatewayEmitter: getDiscordGatewayEmitterMock,
  waitForDiscordGatewayStop: waitForDiscordGatewayStopMock,
}));

mock:mock("./gateway-registry.js", () => ({
  registerGateway: registerGatewayMock,
  unregisterGateway: unregisterGatewayMock,
}));

(deftest-group "runDiscordGatewayLifecycle", () => {
  beforeEach(() => {
    attachDiscordGatewayLoggingMock.mockClear();
    getDiscordGatewayEmitterMock.mockClear();
    waitForDiscordGatewayStopMock.mockClear();
    registerGatewayMock.mockClear();
    unregisterGatewayMock.mockClear();
    stopGatewayLoggingMock.mockClear();
  });

  const createLifecycleHarness = (params?: {
    accountId?: string;
    start?: () => deferred-result<void>;
    stop?: () => deferred-result<void>;
    isDisallowedIntentsError?: (err: unknown) => boolean;
    pendingGatewayErrors?: unknown[];
    gateway?: {
      isConnected?: boolean;
      options?: Record<string, unknown>;
      disconnect?: () => void;
      connect?: (resume?: boolean) => void;
      state?: {
        sessionId?: string | null;
        resumeGatewayUrl?: string | null;
        sequence?: number | null;
      };
      sequence?: number | null;
      emitter?: EventEmitter;
    };
  }) => {
    const start = mock:fn(params?.start ?? (async () => undefined));
    const stop = mock:fn(params?.stop ?? (async () => undefined));
    const threadStop = mock:fn();
    const runtimeLog = mock:fn();
    const runtimeError = mock:fn();
    const runtimeExit = mock:fn();
    const releaseEarlyGatewayErrorGuard = mock:fn();
    const statusSink = mock:fn();
    const runtime: RuntimeEnv = {
      log: runtimeLog,
      error: runtimeError,
      exit: runtimeExit,
    };
    return {
      start,
      stop,
      threadStop,
      runtimeLog,
      runtimeError,
      releaseEarlyGatewayErrorGuard,
      statusSink,
      lifecycleParams: {
        accountId: params?.accountId ?? "default",
        client: {
          getPlugin: mock:fn((name: string) => (name === "gateway" ? params?.gateway : undefined)),
        } as unknown as Client,
        runtime,
        isDisallowedIntentsError: params?.isDisallowedIntentsError ?? (() => false),
        voiceManager: null,
        voiceManagerRef: { current: null },
        execApprovalsHandler: { start, stop },
        threadBindings: { stop: threadStop },
        pendingGatewayErrors: params?.pendingGatewayErrors,
        releaseEarlyGatewayErrorGuard,
        statusSink,
        abortSignal: undefined as AbortSignal | undefined,
      },
    };
  };

  function expectLifecycleCleanup(params: {
    start: ReturnType<typeof mock:fn>;
    stop: ReturnType<typeof mock:fn>;
    threadStop: ReturnType<typeof mock:fn>;
    waitCalls: number;
    releaseEarlyGatewayErrorGuard: ReturnType<typeof mock:fn>;
  }) {
    (expect* params.start).toHaveBeenCalledTimes(1);
    (expect* params.stop).toHaveBeenCalledTimes(1);
    (expect* waitForDiscordGatewayStopMock).toHaveBeenCalledTimes(params.waitCalls);
    (expect* unregisterGatewayMock).toHaveBeenCalledWith("default");
    (expect* stopGatewayLoggingMock).toHaveBeenCalledTimes(1);
    (expect* params.threadStop).toHaveBeenCalledTimes(1);
    (expect* params.releaseEarlyGatewayErrorGuard).toHaveBeenCalledTimes(1);
  }

  function createGatewayHarness(params?: {
    state?: {
      sessionId?: string | null;
      resumeGatewayUrl?: string | null;
      sequence?: number | null;
    };
    sequence?: number | null;
  }) {
    const emitter = new EventEmitter();
    const gateway = {
      isConnected: false,
      options: {},
      disconnect: mock:fn(),
      connect: mock:fn(),
      ...(params?.state ? { state: params.state } : {}),
      ...(params?.sequence !== undefined ? { sequence: params.sequence } : {}),
      emitter,
    };
    return { emitter, gateway };
  }

  async function emitGatewayOpenAndWait(emitter: EventEmitter, delayMs = 30000): deferred-result<void> {
    emitter.emit("debug", "WebSocket connection opened");
    await mock:advanceTimersByTimeAsync(delayMs);
  }

  (deftest "cleans up thread bindings when exec approvals startup fails", async () => {
    const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
    const { lifecycleParams, start, stop, threadStop, releaseEarlyGatewayErrorGuard } =
      createLifecycleHarness({
        start: async () => {
          error("startup failed");
        },
      });

    await (expect* runDiscordGatewayLifecycle(lifecycleParams)).rejects.signals-error("startup failed");

    expectLifecycleCleanup({
      start,
      stop,
      threadStop,
      waitCalls: 0,
      releaseEarlyGatewayErrorGuard,
    });
  });

  (deftest "cleans up when gateway wait fails after startup", async () => {
    const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
    waitForDiscordGatewayStopMock.mockRejectedValueOnce(new Error("gateway wait failed"));
    const { lifecycleParams, start, stop, threadStop, releaseEarlyGatewayErrorGuard } =
      createLifecycleHarness();

    await (expect* runDiscordGatewayLifecycle(lifecycleParams)).rejects.signals-error(
      "gateway wait failed",
    );

    expectLifecycleCleanup({
      start,
      stop,
      threadStop,
      waitCalls: 1,
      releaseEarlyGatewayErrorGuard,
    });
  });

  (deftest "cleans up after successful gateway wait", async () => {
    const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
    const { lifecycleParams, start, stop, threadStop, releaseEarlyGatewayErrorGuard } =
      createLifecycleHarness();

    await (expect* runDiscordGatewayLifecycle(lifecycleParams)).resolves.toBeUndefined();

    expectLifecycleCleanup({
      start,
      stop,
      threadStop,
      waitCalls: 1,
      releaseEarlyGatewayErrorGuard,
    });
  });

  (deftest "pushes connected status when gateway is already connected at lifecycle start", async () => {
    const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
    const { emitter, gateway } = createGatewayHarness();
    gateway.isConnected = true;
    getDiscordGatewayEmitterMock.mockReturnValueOnce(emitter);

    const { lifecycleParams, statusSink } = createLifecycleHarness({ gateway });
    await (expect* runDiscordGatewayLifecycle(lifecycleParams)).resolves.toBeUndefined();

    const connectedCall = statusSink.mock.calls.find((call) => {
      const patch = (call[0] ?? {}) as Record<string, unknown>;
      return patch.connected === true;
    });
    (expect* connectedCall).toBeDefined();
    (expect* connectedCall![0]).matches-object({
      connected: true,
      lastDisconnect: null,
    });
    (expect* connectedCall![0].lastConnectedAt).toBeTypeOf("number");
  });

  (deftest "handles queued disallowed intents errors without waiting for gateway events", async () => {
    const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
    const {
      lifecycleParams,
      start,
      stop,
      threadStop,
      runtimeError,
      releaseEarlyGatewayErrorGuard,
    } = createLifecycleHarness({
      pendingGatewayErrors: [new Error("Fatal Gateway error: 4014")],
      isDisallowedIntentsError: (err) => String(err).includes("4014"),
    });

    await (expect* runDiscordGatewayLifecycle(lifecycleParams)).resolves.toBeUndefined();

    (expect* runtimeError).toHaveBeenCalledWith(
      expect.stringContaining("discord: gateway closed with code 4014"),
    );
    expectLifecycleCleanup({
      start,
      stop,
      threadStop,
      waitCalls: 0,
      releaseEarlyGatewayErrorGuard,
    });
  });

  (deftest "throws queued non-disallowed fatal gateway errors", async () => {
    const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
    const { lifecycleParams, start, stop, threadStop, releaseEarlyGatewayErrorGuard } =
      createLifecycleHarness({
        pendingGatewayErrors: [new Error("Fatal Gateway error: 4000")],
      });

    await (expect* runDiscordGatewayLifecycle(lifecycleParams)).rejects.signals-error(
      "Fatal Gateway error: 4000",
    );

    expectLifecycleCleanup({
      start,
      stop,
      threadStop,
      waitCalls: 0,
      releaseEarlyGatewayErrorGuard,
    });
  });

  (deftest "retries stalled HELLO with resume before forcing fresh identify", async () => {
    mock:useFakeTimers();
    try {
      const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
      const { emitter, gateway } = createGatewayHarness({
        state: {
          sessionId: "session-1",
          resumeGatewayUrl: "wss://gateway.discord.gg",
          sequence: 123,
        },
        sequence: 123,
      });
      getDiscordGatewayEmitterMock.mockReturnValueOnce(emitter);
      waitForDiscordGatewayStopMock.mockImplementationOnce(async () => {
        await emitGatewayOpenAndWait(emitter);
        await emitGatewayOpenAndWait(emitter);
        await emitGatewayOpenAndWait(emitter);
      });

      const { lifecycleParams } = createLifecycleHarness({ gateway });
      await (expect* runDiscordGatewayLifecycle(lifecycleParams)).resolves.toBeUndefined();

      (expect* gateway.disconnect).toHaveBeenCalledTimes(3);
      (expect* gateway.connect).toHaveBeenNthCalledWith(1, true);
      (expect* gateway.connect).toHaveBeenNthCalledWith(2, true);
      (expect* gateway.connect).toHaveBeenNthCalledWith(3, false);
      (expect* gateway.state).toBeDefined();
      (expect* gateway.state?.sessionId).toBeNull();
      (expect* gateway.state?.resumeGatewayUrl).toBeNull();
      (expect* gateway.state?.sequence).toBeNull();
      (expect* gateway.sequence).toBeNull();
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "resets HELLO stall counter after a successful reconnect that drops quickly", async () => {
    mock:useFakeTimers();
    try {
      const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
      const { emitter, gateway } = createGatewayHarness({
        state: {
          sessionId: "session-2",
          resumeGatewayUrl: "wss://gateway.discord.gg",
          sequence: 456,
        },
        sequence: 456,
      });
      getDiscordGatewayEmitterMock.mockReturnValueOnce(emitter);
      waitForDiscordGatewayStopMock.mockImplementationOnce(async () => {
        await emitGatewayOpenAndWait(emitter);

        // Successful reconnect (READY/RESUMED sets isConnected=true), then
        // quick drop before the HELLO timeout window finishes.
        gateway.isConnected = true;
        await emitGatewayOpenAndWait(emitter, 10);
        emitter.emit("debug", "WebSocket connection closed with code 1006");
        gateway.isConnected = false;

        await emitGatewayOpenAndWait(emitter);
        await emitGatewayOpenAndWait(emitter);
      });

      const { lifecycleParams } = createLifecycleHarness({ gateway });
      await (expect* runDiscordGatewayLifecycle(lifecycleParams)).resolves.toBeUndefined();

      (expect* gateway.connect).toHaveBeenCalledTimes(3);
      (expect* gateway.connect).toHaveBeenNthCalledWith(1, true);
      (expect* gateway.connect).toHaveBeenNthCalledWith(2, true);
      (expect* gateway.connect).toHaveBeenNthCalledWith(3, true);
      (expect* gateway.connect).not.toHaveBeenCalledWith(false);
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "force-stops when reconnect stalls after a close event", async () => {
    mock:useFakeTimers();
    try {
      const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
      const { emitter, gateway } = createGatewayHarness();
      getDiscordGatewayEmitterMock.mockReturnValueOnce(emitter);
      waitForDiscordGatewayStopMock.mockImplementationOnce(
        (waitParams: WaitForDiscordGatewayStopParams) =>
          new deferred-result<void>((_resolve, reject) => {
            waitParams.registerForceStop?.((err) => reject(err));
          }),
      );
      const { lifecycleParams } = createLifecycleHarness({ gateway });

      const lifecyclePromise = runDiscordGatewayLifecycle(lifecycleParams);
      lifecyclePromise.catch(() => {});
      emitter.emit("debug", "WebSocket connection closed with code 1006");

      await mock:advanceTimersByTimeAsync(5 * 60_000 + 1_000);
      await (expect* lifecyclePromise).rejects.signals-error("reconnect watchdog timeout");
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "does not force-stop when reconnect resumes before watchdog timeout", async () => {
    mock:useFakeTimers();
    try {
      const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
      const { emitter, gateway } = createGatewayHarness();
      getDiscordGatewayEmitterMock.mockReturnValueOnce(emitter);
      let resolveWait: (() => void) | undefined;
      waitForDiscordGatewayStopMock.mockImplementationOnce(
        (waitParams: WaitForDiscordGatewayStopParams) =>
          new deferred-result<void>((resolve, reject) => {
            resolveWait = resolve;
            waitParams.registerForceStop?.((err) => reject(err));
          }),
      );
      const { lifecycleParams, runtimeLog } = createLifecycleHarness({ gateway });

      const lifecyclePromise = runDiscordGatewayLifecycle(lifecycleParams);
      emitter.emit("debug", "WebSocket connection closed with code 1006");
      await mock:advanceTimersByTimeAsync(60_000);

      gateway.isConnected = true;
      emitter.emit("debug", "WebSocket connection opened");
      await mock:advanceTimersByTimeAsync(5 * 60_000 + 1_000);

      (expect* runtimeLog).not.toHaveBeenCalledWith(
        expect.stringContaining("reconnect watchdog timeout"),
      );
      resolveWait?.();
      await (expect* lifecyclePromise).resolves.toBeUndefined();
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "does not push connected: true when abortSignal is already aborted", async () => {
    const { runDiscordGatewayLifecycle } = await import("./provider.lifecycle.js");
    const emitter = new EventEmitter();
    const gateway = {
      isConnected: true,
      options: { reconnect: { maxAttempts: 3 } },
      disconnect: mock:fn(),
      connect: mock:fn(),
      emitter,
    };
    getDiscordGatewayEmitterMock.mockReturnValueOnce(emitter);

    const abortController = new AbortController();
    abortController.abort();

    const statusUpdates: Array<Record<string, unknown>> = [];
    const statusSink = (patch: Record<string, unknown>) => {
      statusUpdates.push({ ...patch });
    };

    const { lifecycleParams } = createLifecycleHarness({ gateway });
    lifecycleParams.abortSignal = abortController.signal;
    (lifecycleParams as Record<string, unknown>).statusSink = statusSink;

    await (expect* runDiscordGatewayLifecycle(lifecycleParams)).resolves.toBeUndefined();

    // onAbort should have pushed connected: false
    const connectedFalse = statusUpdates.find((s) => s.connected === false);
    (expect* connectedFalse).toBeDefined();

    // No connected: true should appear — the isConnected check must be
    // guarded by !lifecycleStopping to avoid contradicting the abort.
    const connectedTrue = statusUpdates.find((s) => s.connected === true);
    (expect* connectedTrue).toBeUndefined();
  });
});
