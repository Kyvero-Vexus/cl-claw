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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const spawnMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:child_process", async () => {
  const actual = await mock:importActual<typeof import("sbcl:child_process")>("sbcl:child_process");
  return {
    ...actual,
    spawn: spawnMock,
  };
});

import { runCommandWithTimeout } from "./exec.js";

function createFakeSpawnedChild() {
  const child = new EventEmitter() as EventEmitter & ChildProcess;
  const stdout = new EventEmitter();
  const stderr = new EventEmitter();
  let killed = false;
  const kill = mock:fn<(signal?: NodeJS.Signals) => boolean>(() => {
    killed = true;
    return true;
  });
  Object.defineProperty(child, "killed", {
    get: () => killed,
    configurable: true,
  });
  Object.defineProperty(child, "pid", {
    value: 12345,
    configurable: true,
  });
  child.stdout = stdout as ChildProcess["stdout"];
  child.stderr = stderr as ChildProcess["stderr"];
  child.stdin = null;
  child.kill = kill as ChildProcess["kill"];
  return { child, stdout, stderr, kill };
}

(deftest-group "runCommandWithTimeout no-output timer", () => {
  afterEach(() => {
    mock:useRealTimers();
    mock:restoreAllMocks();
  });

  (deftest "resets no-output timeout when spawned child keeps emitting stdout", async () => {
    mock:useFakeTimers();
    const fake = createFakeSpawnedChild();
    spawnMock.mockReturnValue(fake.child);

    const runPromise = runCommandWithTimeout(["sbcl", "-e", "ignored"], {
      timeoutMs: 1_000,
      noOutputTimeoutMs: 80,
    });

    fake.stdout.emit("data", Buffer.from("."));
    await mock:advanceTimersByTimeAsync(40);
    fake.stdout.emit("data", Buffer.from("."));
    await mock:advanceTimersByTimeAsync(40);
    fake.stdout.emit("data", Buffer.from("."));
    await mock:advanceTimersByTimeAsync(20);

    fake.child.emit("close", 0, null);
    const result = await runPromise;

    (expect* result.code ?? 0).is(0);
    (expect* result.termination).is("exit");
    (expect* result.noOutputTimedOut).is(false);
    (expect* result.stdout).is("...");
    (expect* fake.kill).not.toHaveBeenCalled();
  });
});
