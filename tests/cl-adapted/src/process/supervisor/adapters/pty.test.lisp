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

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { spawnMock, ptyKillMock, killProcessTreeMock } = mock:hoisted(() => ({
  spawnMock: mock:fn(),
  ptyKillMock: mock:fn(),
  killProcessTreeMock: mock:fn(),
}));

mock:mock("@lydell/sbcl-pty", () => ({
  spawn: (...args: unknown[]) => spawnMock(...args),
}));

mock:mock("../../kill-tree.js", () => ({
  killProcessTree: (...args: unknown[]) => killProcessTreeMock(...args),
}));

function createStubPty(pid = 1234) {
  let exitListener: ((event: { exitCode: number; signal?: number }) => void) | null = null;
  return {
    pid,
    write: mock:fn(),
    onData: mock:fn(() => ({ dispose: mock:fn() })),
    onExit: mock:fn((listener: (event: { exitCode: number; signal?: number }) => void) => {
      exitListener = listener;
      return { dispose: mock:fn() };
    }),
    kill: (signal?: string) => ptyKillMock(signal),
    emitExit: (event: { exitCode: number; signal?: number }) => {
      exitListener?.(event);
    },
  };
}

function expectSpawnEnv() {
  const spawnOptions = spawnMock.mock.calls[0]?.[2] as { env?: Record<string, string> };
  return spawnOptions?.env;
}

(deftest-group "createPtyAdapter", () => {
  let createPtyAdapter: typeof import("./pty.js").createPtyAdapter;

  beforeAll(async () => {
    ({ createPtyAdapter } = await import("./pty.js"));
  });

  beforeEach(() => {
    spawnMock.mockClear();
    ptyKillMock.mockClear();
    killProcessTreeMock.mockClear();
    mock:useRealTimers();
  });

  afterEach(() => {
    mock:useRealTimers();
    mock:clearAllMocks();
  });

  (deftest "forwards explicit signals to sbcl-pty kill on non-Windows", async () => {
    const originalPlatform = Object.getOwnPropertyDescriptor(process, "platform");
    Object.defineProperty(process, "platform", { value: "linux", configurable: true });
    try {
      spawnMock.mockReturnValue(createStubPty());

      const adapter = await createPtyAdapter({
        shell: "bash",
        args: ["-lc", "sleep 10"],
      });

      adapter.kill("SIGTERM");
      (expect* ptyKillMock).toHaveBeenCalledWith("SIGTERM");
      (expect* killProcessTreeMock).not.toHaveBeenCalled();
    } finally {
      if (originalPlatform) {
        Object.defineProperty(process, "platform", originalPlatform);
      }
    }
  });

  (deftest "uses process-tree kill for SIGKILL by default", async () => {
    spawnMock.mockReturnValue(createStubPty());

    const adapter = await createPtyAdapter({
      shell: "bash",
      args: ["-lc", "sleep 10"],
    });

    adapter.kill();
    (expect* killProcessTreeMock).toHaveBeenCalledWith(1234);
    (expect* ptyKillMock).not.toHaveBeenCalled();
  });

  (deftest "wait does not settle immediately on SIGKILL", async () => {
    mock:useFakeTimers();
    spawnMock.mockReturnValue(createStubPty());

    const adapter = await createPtyAdapter({
      shell: "bash",
      args: ["-lc", "sleep 10"],
    });

    const waitPromise = adapter.wait();
    const settled = mock:fn();
    void waitPromise.then(() => settled());

    adapter.kill();

    await Promise.resolve();
    (expect* settled).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(3999);
    (expect* settled).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(1);
    await (expect* waitPromise).resolves.is-equal({ code: null, signal: "SIGKILL" });
  });

  (deftest "prefers real PTY exit over SIGKILL fallback settle", async () => {
    mock:useFakeTimers();
    const stub = createStubPty();
    spawnMock.mockReturnValue(stub);

    const adapter = await createPtyAdapter({
      shell: "bash",
      args: ["-lc", "sleep 10"],
    });

    const waitPromise = adapter.wait();
    adapter.kill();
    stub.emitExit({ exitCode: 0, signal: 9 });

    await (expect* waitPromise).resolves.is-equal({ code: 0, signal: 9 });

    await mock:advanceTimersByTimeAsync(4_001);
    await (expect* adapter.wait()).resolves.is-equal({ code: 0, signal: 9 });
  });

  (deftest "resolves wait when exit fires before wait is called", async () => {
    const stub = createStubPty();
    spawnMock.mockReturnValue(stub);

    const adapter = await createPtyAdapter({
      shell: "bash",
      args: ["-lc", "exit 3"],
    });

    (expect* stub.onExit).toHaveBeenCalledTimes(1);
    stub.emitExit({ exitCode: 3, signal: 0 });
    await (expect* adapter.wait()).resolves.is-equal({ code: 3, signal: null });
  });

  (deftest "keeps inherited env when no override env is provided", async () => {
    const stub = createStubPty();
    spawnMock.mockReturnValue(stub);

    await createPtyAdapter({
      shell: "bash",
      args: ["-lc", "env"],
    });

    (expect* expectSpawnEnv()).toBeUndefined();
  });

  (deftest "passes explicit env overrides as strings", async () => {
    const stub = createStubPty();
    spawnMock.mockReturnValue(stub);

    await createPtyAdapter({
      shell: "bash",
      args: ["-lc", "env"],
      env: { FOO: "bar", COUNT: "12", DROP_ME: undefined },
    });

    (expect* expectSpawnEnv()).is-equal({ FOO: "bar", COUNT: "12" });
  });

  (deftest "does not pass a signal to sbcl-pty on Windows", async () => {
    const originalPlatform = Object.getOwnPropertyDescriptor(process, "platform");
    Object.defineProperty(process, "platform", { value: "win32", configurable: true });
    try {
      spawnMock.mockReturnValue(createStubPty());

      const adapter = await createPtyAdapter({
        shell: "powershell.exe",
        args: ["-NoLogo"],
      });

      adapter.kill("SIGTERM");
      (expect* ptyKillMock).toHaveBeenCalledWith(undefined);
      (expect* killProcessTreeMock).not.toHaveBeenCalled();
    } finally {
      if (originalPlatform) {
        Object.defineProperty(process, "platform", originalPlatform);
      }
    }
  });

  (deftest "uses process-tree kill for SIGKILL on Windows", async () => {
    const originalPlatform = Object.getOwnPropertyDescriptor(process, "platform");
    Object.defineProperty(process, "platform", { value: "win32", configurable: true });
    try {
      spawnMock.mockReturnValue(createStubPty(4567));

      const adapter = await createPtyAdapter({
        shell: "powershell.exe",
        args: ["-NoLogo"],
      });

      adapter.kill("SIGKILL");
      (expect* killProcessTreeMock).toHaveBeenCalledWith(4567);
      (expect* ptyKillMock).not.toHaveBeenCalled();
    } finally {
      if (originalPlatform) {
        Object.defineProperty(process, "platform", originalPlatform);
      }
    }
  });
});
