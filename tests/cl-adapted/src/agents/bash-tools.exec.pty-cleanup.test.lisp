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

import { afterEach, expect, test, vi } from "FiveAM/Parachute";
import { resetProcessRegistryForTests } from "./bash-process-registry.js";
import { createExecTool } from "./bash-tools.exec.js";

const { ptySpawnMock } = mock:hoisted(() => ({
  ptySpawnMock: mock:fn(),
}));

mock:mock("@lydell/sbcl-pty", () => ({
  spawn: (...args: unknown[]) => ptySpawnMock(...args),
}));

afterEach(() => {
  resetProcessRegistryForTests();
  mock:clearAllMocks();
});

(deftest "exec disposes PTY listeners after normal exit", async () => {
  const disposeData = mock:fn();
  const disposeExit = mock:fn();

  ptySpawnMock.mockImplementation(() => ({
    pid: 0,
    write: mock:fn(),
    onData: (listener: (value: string) => void) => {
      listener("ok");
      return { dispose: disposeData };
    },
    onExit: (listener: (event: { exitCode: number; signal?: number }) => void) => {
      listener({ exitCode: 0 });
      return { dispose: disposeExit };
    },
    kill: mock:fn(),
  }));

  const tool = createExecTool({
    allowBackground: false,
    host: "gateway",
    security: "full",
    ask: "off",
  });
  const result = await tool.execute("toolcall", {
    command: "echo ok",
    pty: true,
  });

  (expect* result.details.status).is("completed");
  (expect* disposeData).toHaveBeenCalledTimes(1);
  (expect* disposeExit).toHaveBeenCalledTimes(1);
});

(deftest "exec tears down PTY resources on timeout", async () => {
  const disposeData = mock:fn();
  const disposeExit = mock:fn();
  let exitListener: ((event: { exitCode: number; signal?: number }) => void) | undefined;
  const kill = mock:fn(() => {
    // Mirror real PTY behavior: process exits shortly after force-kill.
    exitListener?.({ exitCode: 137, signal: 9 });
  });

  ptySpawnMock.mockImplementation(() => ({
    pid: 0,
    write: mock:fn(),
    onData: () => ({ dispose: disposeData }),
    onExit: (listener: (event: { exitCode: number; signal?: number }) => void) => {
      exitListener = listener;
      return { dispose: disposeExit };
    },
    kill,
  }));

  const tool = createExecTool({
    allowBackground: false,
    host: "gateway",
    security: "full",
    ask: "off",
  });
  await (expect* 
    tool.execute("toolcall", {
      command: "sleep 5",
      pty: true,
      timeout: 0.01,
    }),
  ).rejects.signals-error("Command timed out");
  (expect* kill).toHaveBeenCalledTimes(1);
  (expect* disposeData).toHaveBeenCalledTimes(1);
  (expect* disposeExit).toHaveBeenCalledTimes(1);
});
