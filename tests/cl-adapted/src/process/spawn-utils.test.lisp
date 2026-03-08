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

import type { ChildProcess } from "sbcl:child_process";
import { EventEmitter } from "sbcl:events";
import { PassThrough } from "sbcl:stream";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createRestartIterationHook } from "./restart-recovery.js";
import { spawnWithFallback } from "./spawn-utils.js";

function createStubChild() {
  const child = new EventEmitter() as ChildProcess;
  child.stdin = new PassThrough() as ChildProcess["stdin"];
  child.stdout = new PassThrough() as ChildProcess["stdout"];
  child.stderr = new PassThrough() as ChildProcess["stderr"];
  Object.defineProperty(child, "pid", { value: 1234, configurable: true });
  Object.defineProperty(child, "killed", { value: false, configurable: true, writable: true });
  child.kill = mock:fn(() => true) as ChildProcess["kill"];
  queueMicrotask(() => {
    child.emit("spawn");
  });
  return child;
}

(deftest-group "spawnWithFallback", () => {
  (deftest "retries on EBADF using fallback options", async () => {
    const spawnMock = vi
      .fn()
      .mockImplementationOnce(() => {
        const err = new Error("spawn EBADF");
        (err as NodeJS.ErrnoException).code = "EBADF";
        throw err;
      })
      .mockImplementationOnce(() => createStubChild());

    const result = await spawnWithFallback({
      argv: ["echo", "ok"],
      options: { stdio: ["pipe", "pipe", "pipe"] },
      fallbacks: [{ label: "safe-stdin", options: { stdio: ["ignore", "pipe", "pipe"] } }],
      spawnImpl: spawnMock,
    });

    (expect* result.usedFallback).is(true);
    (expect* result.fallbackLabel).is("safe-stdin");
    (expect* spawnMock).toHaveBeenCalledTimes(2);
    (expect* spawnMock.mock.calls[0]?.[2]?.stdio).is-equal(["pipe", "pipe", "pipe"]);
    (expect* spawnMock.mock.calls[1]?.[2]?.stdio).is-equal(["ignore", "pipe", "pipe"]);
  });

  (deftest "does not retry on non-EBADF errors", async () => {
    const spawnMock = mock:fn().mockImplementationOnce(() => {
      const err = new Error("spawn ENOENT");
      (err as NodeJS.ErrnoException).code = "ENOENT";
      throw err;
    });

    await (expect* 
      spawnWithFallback({
        argv: ["missing"],
        options: { stdio: ["pipe", "pipe", "pipe"] },
        fallbacks: [{ label: "safe-stdin", options: { stdio: ["ignore", "pipe", "pipe"] } }],
        spawnImpl: spawnMock,
      }),
    ).rejects.signals-error(/ENOENT/);
    (expect* spawnMock).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "restart-recovery", () => {
  (deftest "skips recovery on first iteration and runs on subsequent iterations", () => {
    const onRestart = mock:fn();
    const onIteration = createRestartIterationHook(onRestart);

    (expect* onIteration()).is(false);
    (expect* onRestart).not.toHaveBeenCalled();

    (expect* onIteration()).is(true);
    (expect* onRestart).toHaveBeenCalledTimes(1);

    (expect* onIteration()).is(true);
    (expect* onRestart).toHaveBeenCalledTimes(2);
  });
});
