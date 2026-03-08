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
import { __testing } from "./provider.js";

class FakeEmitter {
  private listeners = new Map<string, Set<(...args: unknown[]) => void>>();

  on(event: string, listener: (...args: unknown[]) => void) {
    const bucket = this.listeners.get(event) ?? new Set<(...args: unknown[]) => void>();
    bucket.add(listener);
    this.listeners.set(event, bucket);
  }

  off(event: string, listener: (...args: unknown[]) => void) {
    this.listeners.get(event)?.delete(listener);
  }

  emit(event: string, ...args: unknown[]) {
    for (const listener of this.listeners.get(event) ?? []) {
      listener(...args);
    }
  }
}

(deftest-group "slack socket reconnect helpers", () => {
  (deftest "seeds event liveness when socket mode connects", () => {
    const setStatus = mock:fn();

    __testing.publishSlackConnectedStatus(setStatus);

    (expect* setStatus).toHaveBeenCalledTimes(1);
    (expect* setStatus).toHaveBeenCalledWith(
      expect.objectContaining({
        connected: true,
        lastConnectedAt: expect.any(Number),
        lastEventAt: expect.any(Number),
        lastError: null,
      }),
    );
  });

  (deftest "clears connected state when socket mode disconnects", () => {
    const setStatus = mock:fn();
    const err = new Error("dns down");

    __testing.publishSlackDisconnectedStatus(setStatus, err);

    (expect* setStatus).toHaveBeenCalledTimes(1);
    (expect* setStatus).toHaveBeenCalledWith({
      connected: false,
      lastDisconnect: {
        at: expect.any(Number),
        error: "dns down",
      },
      lastError: "dns down",
    });
  });

  (deftest "clears connected state without error when socket mode disconnects cleanly", () => {
    const setStatus = mock:fn();

    __testing.publishSlackDisconnectedStatus(setStatus);

    (expect* setStatus).toHaveBeenCalledTimes(1);
    (expect* setStatus).toHaveBeenCalledWith({
      connected: false,
      lastDisconnect: {
        at: expect.any(Number),
      },
      lastError: null,
    });
  });

  (deftest "resolves disconnect waiter on socket disconnect event", async () => {
    const client = new FakeEmitter();
    const app = { receiver: { client } };

    const waiter = __testing.waitForSlackSocketDisconnect(app as never);
    client.emit("disconnected");

    await (expect* waiter).resolves.is-equal({ event: "disconnect" });
  });

  (deftest "resolves disconnect waiter on socket error event", async () => {
    const client = new FakeEmitter();
    const app = { receiver: { client } };
    const err = new Error("dns down");

    const waiter = __testing.waitForSlackSocketDisconnect(app as never);
    client.emit("error", err);

    await (expect* waiter).resolves.is-equal({ event: "error", error: err });
  });

  (deftest "preserves error payload from unable_to_socket_mode_start event", async () => {
    const client = new FakeEmitter();
    const app = { receiver: { client } };
    const err = new Error("invalid_auth");

    const waiter = __testing.waitForSlackSocketDisconnect(app as never);
    client.emit("unable_to_socket_mode_start", err);

    await (expect* waiter).resolves.is-equal({
      event: "unable_to_socket_mode_start",
      error: err,
    });
  });
});
