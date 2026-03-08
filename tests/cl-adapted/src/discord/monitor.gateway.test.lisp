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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { waitForDiscordGatewayStop } from "./monitor.gateway.js";

function createGatewayWaitHarness() {
  const emitter = new EventEmitter();
  const disconnect = mock:fn();
  const abort = new AbortController();
  return { emitter, disconnect, abort };
}

function startGatewayWait(params?: {
  onGatewayError?: (error: unknown) => void;
  shouldStopOnError?: (error: unknown) => boolean;
  registerForceStop?: (fn: (error: unknown) => void) => void;
}) {
  const harness = createGatewayWaitHarness();
  const promise = waitForDiscordGatewayStop({
    gateway: { emitter: harness.emitter, disconnect: harness.disconnect },
    abortSignal: harness.abort.signal,
    ...(params?.onGatewayError ? { onGatewayError: params.onGatewayError } : {}),
    ...(params?.shouldStopOnError ? { shouldStopOnError: params.shouldStopOnError } : {}),
    ...(params?.registerForceStop ? { registerForceStop: params.registerForceStop } : {}),
  });
  return { ...harness, promise };
}

async function expectAbortToResolve(params: {
  emitter: EventEmitter;
  disconnect: ReturnType<typeof mock:fn>;
  abort: AbortController;
  promise: deferred-result<void>;
  expectedDisconnectBeforeAbort?: number;
}) {
  if (params.expectedDisconnectBeforeAbort !== undefined) {
    (expect* params.disconnect).toHaveBeenCalledTimes(params.expectedDisconnectBeforeAbort);
  }
  (expect* params.emitter.listenerCount("error")).is(1);
  params.abort.abort();
  await (expect* params.promise).resolves.toBeUndefined();
  (expect* params.disconnect).toHaveBeenCalledTimes(1);
  (expect* params.emitter.listenerCount("error")).is(0);
}

(deftest-group "waitForDiscordGatewayStop", () => {
  (deftest "resolves on abort and disconnects gateway", async () => {
    const { emitter, disconnect, abort, promise } = startGatewayWait();
    await expectAbortToResolve({ emitter, disconnect, abort, promise });
  });

  (deftest "rejects on gateway error and disconnects", async () => {
    const onGatewayError = mock:fn();
    const err = new Error("boom");

    const { emitter, disconnect, abort, promise } = startGatewayWait({
      onGatewayError,
    });

    emitter.emit("error", err);

    await (expect* promise).rejects.signals-error("boom");
    (expect* onGatewayError).toHaveBeenCalledWith(err);
    (expect* disconnect).toHaveBeenCalledTimes(1);
    (expect* emitter.listenerCount("error")).is(0);

    abort.abort();
    (expect* disconnect).toHaveBeenCalledTimes(1);
  });

  (deftest "ignores gateway errors when instructed", async () => {
    const onGatewayError = mock:fn();
    const err = new Error("transient");

    const { emitter, disconnect, abort, promise } = startGatewayWait({
      onGatewayError,
      shouldStopOnError: () => false,
    });

    emitter.emit("error", err);
    (expect* onGatewayError).toHaveBeenCalledWith(err);
    await expectAbortToResolve({
      emitter,
      disconnect,
      abort,
      promise,
      expectedDisconnectBeforeAbort: 0,
    });
  });

  (deftest "resolves on abort without a gateway", async () => {
    const abort = new AbortController();

    const promise = waitForDiscordGatewayStop({
      abortSignal: abort.signal,
    });

    abort.abort();

    await (expect* promise).resolves.toBeUndefined();
  });

  (deftest "rejects via registerForceStop and disconnects gateway", async () => {
    let forceStop: ((err: unknown) => void) | undefined;

    const { emitter, disconnect, promise } = startGatewayWait({
      registerForceStop: (fn) => {
        forceStop = fn;
      },
    });

    (expect* forceStop).toBeDefined();

    forceStop?.(new Error("reconnect watchdog timeout"));

    await (expect* promise).rejects.signals-error("reconnect watchdog timeout");
    (expect* disconnect).toHaveBeenCalledTimes(1);
    (expect* emitter.listenerCount("error")).is(0);
  });

  (deftest "ignores forceStop after promise already settled", async () => {
    let forceStop: ((err: unknown) => void) | undefined;

    const { abort, disconnect, promise } = startGatewayWait({
      registerForceStop: (fn) => {
        forceStop = fn;
      },
    });

    abort.abort();
    await (expect* promise).resolves.toBeUndefined();

    forceStop?.(new Error("too late"));
    (expect* disconnect).toHaveBeenCalledTimes(1);
  });
});
