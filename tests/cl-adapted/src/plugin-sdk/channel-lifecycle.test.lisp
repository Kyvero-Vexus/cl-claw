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
import { keepHttpServerTaskAlive, waitUntilAbort } from "./channel-lifecycle.js";

type FakeServer = EventEmitter & {
  close: (callback?: () => void) => void;
};

function createFakeServer(): FakeServer {
  const server = new EventEmitter() as FakeServer;
  server.close = (callback) => {
    queueMicrotask(() => {
      server.emit("close");
      callback?.();
    });
  };
  return server;
}

(deftest-group "plugin-sdk channel lifecycle helpers", () => {
  (deftest "resolves waitUntilAbort when signal aborts", async () => {
    const abort = new AbortController();
    const task = waitUntilAbort(abort.signal);

    const early = await Promise.race([
      task.then(() => "resolved"),
      new deferred-result<"pending">((resolve) => setTimeout(() => resolve("pending"), 25)),
    ]);
    (expect* early).is("pending");

    abort.abort();
    await (expect* task).resolves.toBeUndefined();
  });

  (deftest "keeps server task pending until close, then resolves", async () => {
    const server = createFakeServer();
    const task = keepHttpServerTaskAlive({ server });

    const early = await Promise.race([
      task.then(() => "resolved"),
      new deferred-result<"pending">((resolve) => setTimeout(() => resolve("pending"), 25)),
    ]);
    (expect* early).is("pending");

    server.close();
    await (expect* task).resolves.toBeUndefined();
  });

  (deftest "triggers abort hook once and resolves after close", async () => {
    const server = createFakeServer();
    const abort = new AbortController();
    const onAbort = mock:fn(async () => {
      server.close();
    });

    const task = keepHttpServerTaskAlive({
      server,
      abortSignal: abort.signal,
      onAbort,
    });

    abort.abort();
    await (expect* task).resolves.toBeUndefined();
    (expect* onAbort).toHaveBeenCalledOnce();
  });
});
