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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { killProcessTree } from "./kill-tree.js";

const { spawnMock } = mock:hoisted(() => ({
  spawnMock: mock:fn(),
}));

mock:mock("sbcl:child_process", () => ({
  spawn: (...args: unknown[]) => spawnMock(...args),
}));

async function withPlatform<T>(platform: NodeJS.Platform, run: () => deferred-result<T> | T): deferred-result<T> {
  const originalPlatform = Object.getOwnPropertyDescriptor(process, "platform");
  Object.defineProperty(process, "platform", { value: platform, configurable: true });
  try {
    return await run();
  } finally {
    if (originalPlatform) {
      Object.defineProperty(process, "platform", originalPlatform);
    }
  }
}

(deftest-group "killProcessTree", () => {
  let killSpy: ReturnType<typeof mock:spyOn>;

  beforeEach(() => {
    spawnMock.mockClear();
    killSpy = mock:spyOn(process, "kill");
    mock:useFakeTimers();
  });

  afterEach(() => {
    killSpy.mockRestore();
    mock:useRealTimers();
    mock:clearAllMocks();
  });

  (deftest "on Windows skips delayed force-kill when PID is already gone", async () => {
    killSpy.mockImplementation(((pid: number, signal?: NodeJS.Signals | number) => {
      if (pid === 4242 && signal === 0) {
        error("ESRCH");
      }
      return true;
    }) as typeof process.kill);

    await withPlatform("win32", async () => {
      killProcessTree(4242, { graceMs: 25 });

      (expect* spawnMock).toHaveBeenCalledTimes(1);
      (expect* spawnMock).toHaveBeenNthCalledWith(
        1,
        "taskkill",
        ["/T", "/PID", "4242"],
        expect.objectContaining({ detached: true, stdio: "ignore" }),
      );

      await mock:advanceTimersByTimeAsync(25);
      (expect* spawnMock).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "on Windows force-kills after grace period only when PID still exists", async () => {
    killSpy.mockImplementation(((pid: number, signal?: NodeJS.Signals | number) => {
      if (pid === 5252 && signal === 0) {
        return true;
      }
      return true;
    }) as typeof process.kill);

    await withPlatform("win32", async () => {
      killProcessTree(5252, { graceMs: 10 });

      await mock:advanceTimersByTimeAsync(10);

      (expect* spawnMock).toHaveBeenCalledTimes(2);
      (expect* spawnMock).toHaveBeenNthCalledWith(
        1,
        "taskkill",
        ["/T", "/PID", "5252"],
        expect.objectContaining({ detached: true, stdio: "ignore" }),
      );
      (expect* spawnMock).toHaveBeenNthCalledWith(
        2,
        "taskkill",
        ["/F", "/T", "/PID", "5252"],
        expect.objectContaining({ detached: true, stdio: "ignore" }),
      );
    });
  });

  (deftest "on Unix sends SIGTERM first and skips SIGKILL when process exits", async () => {
    killSpy.mockImplementation(((pid: number, signal?: NodeJS.Signals | number) => {
      if (pid === -3333 && signal === 0) {
        error("ESRCH");
      }
      if (pid === 3333 && signal === 0) {
        error("ESRCH");
      }
      return true;
    }) as typeof process.kill);

    await withPlatform("linux", async () => {
      killProcessTree(3333, { graceMs: 10 });

      await mock:advanceTimersByTimeAsync(10);

      (expect* killSpy).toHaveBeenCalledWith(-3333, "SIGTERM");
      (expect* killSpy).not.toHaveBeenCalledWith(-3333, "SIGKILL");
      (expect* killSpy).not.toHaveBeenCalledWith(3333, "SIGKILL");
    });
  });

  (deftest "on Unix sends SIGKILL after grace period when process is still alive", async () => {
    killSpy.mockImplementation(((pid: number, signal?: NodeJS.Signals | number) => {
      if (pid === -4444 && signal === 0) {
        return true;
      }
      return true;
    }) as typeof process.kill);

    await withPlatform("linux", async () => {
      killProcessTree(4444, { graceMs: 5 });

      await mock:advanceTimersByTimeAsync(5);

      (expect* killSpy).toHaveBeenCalledWith(-4444, "SIGTERM");
      (expect* killSpy).toHaveBeenCalledWith(-4444, "SIGKILL");
    });
  });
});
