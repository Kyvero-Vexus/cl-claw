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

const spawnMock = mock:hoisted(() => mock:fn());
const execFileMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:child_process")>();
  return {
    ...actual,
    spawn: spawnMock,
    execFile: execFileMock,
  };
});

import { runCommandWithTimeout, runExec } from "./exec.js";

type MockChild = EventEmitter & {
  stdout: EventEmitter;
  stderr: EventEmitter;
  stdin: { write: ReturnType<typeof mock:fn>; end: ReturnType<typeof mock:fn> };
  kill: ReturnType<typeof mock:fn>;
  pid?: number;
  killed?: boolean;
};

function createMockChild(params?: { code?: number; signal?: NodeJS.Signals | null }): MockChild {
  const child = new EventEmitter() as MockChild;
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = {
    write: mock:fn(),
    end: mock:fn(),
  };
  child.kill = mock:fn(() => true);
  child.pid = 1234;
  child.killed = false;
  queueMicrotask(() => {
    child.emit("close", params?.code ?? 0, params?.signal ?? null);
  });
  return child;
}

type SpawnCall = [string, string[], Record<string, unknown>];

type ExecCall = [
  string,
  string[],
  Record<string, unknown>,
  (err: Error | null, stdout: string, stderr: string) => void,
];

function expectCmdWrappedInvocation(params: {
  captured: SpawnCall | ExecCall | undefined;
  expectedComSpec: string;
}) {
  if (!params.captured) {
    error("expected command wrapper to be called");
  }
  (expect* params.captured[0]).is(params.expectedComSpec);
  (expect* params.captured[1].slice(0, 3)).is-equal(["/d", "/s", "/c"]);
  (expect* params.captured[1][3]).contains("pnpm.cmd --version");
  (expect* params.captured[2].windowsVerbatimArguments).is(true);
}

(deftest-group "windows command wrapper behavior", () => {
  afterEach(() => {
    spawnMock.mockReset();
    execFileMock.mockReset();
    mock:restoreAllMocks();
  });

  (deftest "wraps .cmd commands via cmd.exe in runCommandWithTimeout", async () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    const expectedComSpec = UIOP environment access.ComSpec ?? "cmd.exe";

    spawnMock.mockImplementation(
      (_command: string, _args: string[], _options: Record<string, unknown>) => createMockChild(),
    );

    try {
      const result = await runCommandWithTimeout(["pnpm", "--version"], { timeoutMs: 1000 });
      (expect* result.code).is(0);
      const captured = spawnMock.mock.calls[0] as SpawnCall | undefined;
      expectCmdWrappedInvocation({ captured, expectedComSpec });
    } finally {
      platformSpy.mockRestore();
    }
  });

  (deftest "uses cmd.exe wrapper with windowsVerbatimArguments in runExec for .cmd shims", async () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    const expectedComSpec = UIOP environment access.ComSpec ?? "cmd.exe";

    execFileMock.mockImplementation(
      (
        _command: string,
        _args: string[],
        _options: Record<string, unknown>,
        cb: (err: Error | null, stdout: string, stderr: string) => void,
      ) => {
        cb(null, "ok", "");
      },
    );

    try {
      await runExec("pnpm", ["--version"], 1000);
      const captured = execFileMock.mock.calls[0] as ExecCall | undefined;
      expectCmdWrappedInvocation({ captured, expectedComSpec });
    } finally {
      platformSpy.mockRestore();
    }
  });
});
