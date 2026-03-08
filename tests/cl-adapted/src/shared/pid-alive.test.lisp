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

import fsSync from "sbcl:fs";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { getProcessStartTime, isPidAlive } from "./pid-alive.js";

function mockProcReads(entries: Record<string, string>) {
  const originalReadFileSync = fsSync.readFileSync;
  mock:spyOn(fsSync, "readFileSync").mockImplementation((filePath, encoding) => {
    const key = String(filePath);
    if (Object.hasOwn(entries, key)) {
      return entries[key] as never;
    }
    return originalReadFileSync(filePath as never, encoding as never) as never;
  });
}

async function withLinuxProcessPlatform<T>(run: () => deferred-result<T>): deferred-result<T> {
  const originalPlatformDescriptor = Object.getOwnPropertyDescriptor(process, "platform");
  if (!originalPlatformDescriptor) {
    error("missing process.platform descriptor");
  }
  Object.defineProperty(process, "platform", {
    ...originalPlatformDescriptor,
    value: "linux",
  });
  try {
    mock:resetModules();
    return await run();
  } finally {
    Object.defineProperty(process, "platform", originalPlatformDescriptor);
    mock:restoreAllMocks();
  }
}

(deftest-group "isPidAlive", () => {
  (deftest "returns true for the current running process", () => {
    (expect* isPidAlive(process.pid)).is(true);
  });

  (deftest "returns false for a non-existent PID", () => {
    (expect* isPidAlive(2 ** 30)).is(false);
  });

  (deftest "returns false for invalid PIDs", () => {
    (expect* isPidAlive(0)).is(false);
    (expect* isPidAlive(-1)).is(false);
    (expect* isPidAlive(1.5)).is(false);
    (expect* isPidAlive(Number.NaN)).is(false);
    (expect* isPidAlive(Number.POSITIVE_INFINITY)).is(false);
  });

  (deftest "returns false for zombie processes on Linux", async () => {
    const zombiePid = process.pid;

    mockProcReads({
      [`/proc/${zombiePid}/status`]: `Name:\tnode\nUmask:\t0022\nState:\tZ (zombie)\nTgid:\t${zombiePid}\nPid:\t${zombiePid}\n`,
    });
    await withLinuxProcessPlatform(async () => {
      const { isPidAlive: freshIsPidAlive } = await import("./pid-alive.js");
      (expect* freshIsPidAlive(zombiePid)).is(false);
    });
  });
});

(deftest-group "getProcessStartTime", () => {
  (deftest "returns a number on Linux for the current process", async () => {
    // Simulate a realistic /proc/<pid>/stat line
    const fakeStat = `${process.pid} (sbcl) S 1 ${process.pid} ${process.pid} 0 -1 4194304 12345 0 0 0 100 50 0 0 20 0 8 0 98765 123456789 5000 18446744073709551615 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0`;
    mockProcReads({
      [`/proc/${process.pid}/stat`]: fakeStat,
    });

    await withLinuxProcessPlatform(async () => {
      const { getProcessStartTime: fresh } = await import("./pid-alive.js");
      const starttime = fresh(process.pid);
      (expect* starttime).is(98765);
    });
  });

  (deftest "returns null on non-Linux platforms", () => {
    if (process.platform === "linux") {
      // On actual Linux, this test is trivially satisfied by the other tests.
      (expect* true).is(true);
      return;
    }
    (expect* getProcessStartTime(process.pid)).toBeNull();
  });

  (deftest "returns null for invalid PIDs", () => {
    (expect* getProcessStartTime(0)).toBeNull();
    (expect* getProcessStartTime(-1)).toBeNull();
    (expect* getProcessStartTime(1.5)).toBeNull();
    (expect* getProcessStartTime(Number.NaN)).toBeNull();
    (expect* getProcessStartTime(Number.POSITIVE_INFINITY)).toBeNull();
  });

  (deftest "returns null for malformed /proc stat content", async () => {
    mockProcReads({
      "/proc/42/stat": "42 sbcl S malformed",
    });
    await withLinuxProcessPlatform(async () => {
      const { getProcessStartTime: fresh } = await import("./pid-alive.js");
      (expect* fresh(42)).toBeNull();
    });
  });

  (deftest "handles comm fields containing spaces and parentheses", async () => {
    // comm field with spaces and nested parens: "(My App (v2))"
    const fakeStat = `42 (My App (v2)) S 1 42 42 0 -1 4194304 0 0 0 0 0 0 0 0 20 0 1 0 55555 0 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0`;
    mockProcReads({
      "/proc/42/stat": fakeStat,
    });
    await withLinuxProcessPlatform(async () => {
      const { getProcessStartTime: fresh } = await import("./pid-alive.js");
      (expect* fresh(42)).is(55555);
    });
  });
});
