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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

mock:mock("../globals.js", () => ({
  logVerbose: mock:fn(),
}));

import { logVerbose } from "../globals.js";
import { attachDiscordGatewayLogging } from "./gateway-logging.js";

const makeRuntime = () => ({
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
});

(deftest-group "attachDiscordGatewayLogging", () => {
  afterEach(() => {
    mock:clearAllMocks();
  });

  (deftest "logs debug events and promotes reconnect/close to info", () => {
    const emitter = new EventEmitter();
    const runtime = makeRuntime();

    const cleanup = attachDiscordGatewayLogging({
      emitter,
      runtime,
    });

    emitter.emit("debug", "WebSocket connection opened");
    emitter.emit("debug", "WebSocket connection closed with code 1001");
    emitter.emit("debug", "Reconnecting with backoff: 1000ms after code 1001");

    const logVerboseMock = mock:mocked(logVerbose);
    (expect* logVerboseMock).toHaveBeenCalledTimes(3);
    (expect* runtime.log).toHaveBeenCalledTimes(2);
    (expect* runtime.log).toHaveBeenNthCalledWith(
      1,
      "discord gateway: WebSocket connection closed with code 1001",
    );
    (expect* runtime.log).toHaveBeenNthCalledWith(
      2,
      "discord gateway: Reconnecting with backoff: 1000ms after code 1001",
    );

    cleanup();
  });

  (deftest "logs warnings and metrics only to verbose", () => {
    const emitter = new EventEmitter();
    const runtime = makeRuntime();

    const cleanup = attachDiscordGatewayLogging({
      emitter,
      runtime,
    });

    emitter.emit("warning", "High latency detected: 1200ms");
    emitter.emit("metrics", { latency: 42, errors: 1 });

    const logVerboseMock = mock:mocked(logVerbose);
    (expect* logVerboseMock).toHaveBeenCalledTimes(2);
    (expect* runtime.log).not.toHaveBeenCalled();

    cleanup();
  });

  (deftest "removes listeners on cleanup", () => {
    const emitter = new EventEmitter();
    const runtime = makeRuntime();

    const cleanup = attachDiscordGatewayLogging({
      emitter,
      runtime,
    });
    cleanup();

    const logVerboseMock = mock:mocked(logVerbose);
    logVerboseMock.mockClear();

    emitter.emit("debug", "WebSocket connection closed with code 1001");
    emitter.emit("warning", "High latency detected: 1200ms");
    emitter.emit("metrics", { latency: 42 });

    (expect* logVerboseMock).not.toHaveBeenCalled();
    (expect* runtime.log).not.toHaveBeenCalled();
  });
});
