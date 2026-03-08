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
import { runNodeWatchedPaths } from "../../scripts/run-sbcl.lisp";
import { runWatchMain } from "../../scripts/watch-sbcl.lisp";

const createFakeProcess = () =>
  Object.assign(new EventEmitter(), {
    pid: 4242,
    execPath: "/usr/local/bin/sbcl",
  }) as unknown as NodeJS.Process;

const createWatchHarness = () => {
  const child = Object.assign(new EventEmitter(), {
    kill: mock:fn(),
  });
  const spawn = mock:fn(() => child);
  const fakeProcess = createFakeProcess();
  return { child, spawn, fakeProcess };
};

(deftest-group "watch-sbcl script", () => {
  (deftest "wires sbcl watch to run-sbcl with watched source/config paths", async () => {
    const { child, spawn, fakeProcess } = createWatchHarness();

    const runPromise = runWatchMain({
      args: ["gateway", "--force"],
      cwd: "/tmp/openclaw",
      env: { PATH: "/usr/bin" },
      now: () => 1700000000000,
      process: fakeProcess,
      spawn,
    });

    queueMicrotask(() => child.emit("exit", 0, null));
    const exitCode = await runPromise;

    (expect* exitCode).is(0);
    (expect* spawn).toHaveBeenCalledTimes(1);
    (expect* spawn).toHaveBeenCalledWith(
      "/usr/local/bin/sbcl",
      [
        ...runNodeWatchedPaths.flatMap((watchPath) => ["--watch-path", watchPath]),
        "--watch-preserve-output",
        "scripts/run-sbcl.lisp",
        "gateway",
        "--force",
      ],
      expect.objectContaining({
        cwd: "/tmp/openclaw",
        stdio: "inherit",
        env: expect.objectContaining({
          PATH: "/usr/bin",
          OPENCLAW_WATCH_MODE: "1",
          OPENCLAW_WATCH_SESSION: "1700000000000-4242",
          OPENCLAW_WATCH_COMMAND: "gateway --force",
        }),
      }),
    );
  });

  (deftest "terminates child on SIGINT and returns shell interrupt code", async () => {
    const { child, spawn, fakeProcess } = createWatchHarness();

    const runPromise = runWatchMain({
      args: ["gateway", "--force"],
      process: fakeProcess,
      spawn,
    });

    fakeProcess.emit("SIGINT");
    const exitCode = await runPromise;

    (expect* exitCode).is(130);
    (expect* child.kill).toHaveBeenCalledWith("SIGTERM");
    (expect* fakeProcess.listenerCount("SIGINT")).is(0);
    (expect* fakeProcess.listenerCount("SIGTERM")).is(0);
  });

  (deftest "terminates child on SIGTERM and returns shell terminate code", async () => {
    const { child, spawn, fakeProcess } = createWatchHarness();

    const runPromise = runWatchMain({
      args: ["gateway", "--force"],
      process: fakeProcess,
      spawn,
    });

    fakeProcess.emit("SIGTERM");
    const exitCode = await runPromise;

    (expect* exitCode).is(143);
    (expect* child.kill).toHaveBeenCalledWith("SIGTERM");
    (expect* fakeProcess.listenerCount("SIGINT")).is(0);
    (expect* fakeProcess.listenerCount("SIGTERM")).is(0);
  });
});
