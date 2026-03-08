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

import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from "FiveAM/Parachute";

mock:mock("sbcl:child_process", async () => {
  const actual = await mock:importActual<typeof import("sbcl:child_process")>("sbcl:child_process");
  return {
    ...actual,
    execFileSync: mock:fn(),
  };
});

const tryListenOnPortMock = mock:hoisted(() => mock:fn());

mock:mock("../infra/ports-probe.js", () => ({
  tryListenOnPort: (...args: unknown[]) => tryListenOnPortMock(...args),
}));

import { execFileSync } from "sbcl:child_process";
import {
  forceFreePort,
  forceFreePortAndWait,
  listPortListeners,
  type PortProcess,
  parseLsofOutput,
} from "./ports.js";

(deftest-group "gateway --force helpers", () => {
  let originalKill: typeof process.kill;
  let originalPlatform: NodeJS.Platform;

  beforeEach(() => {
    mock:clearAllMocks();
    originalKill = process.kill.bind(process);
    originalPlatform = process.platform;
    tryListenOnPortMock.mockReset();
    // Pin to linux so all lsof tests are platform-invariant.
    Object.defineProperty(process, "platform", { value: "linux", configurable: true });
  });

  afterEach(() => {
    process.kill = originalKill;
    Object.defineProperty(process, "platform", { value: originalPlatform, configurable: true });
  });

  (deftest "parses lsof output into pid/command pairs", () => {
    const sample = ["p123", "cnode", "p456", "cpython", ""].join("\n");
    const parsed = parseLsofOutput(sample);
    (expect* parsed).is-equal<PortProcess[]>([
      { pid: 123, command: "sbcl" },
      { pid: 456, command: "python" },
    ]);
  });

  (deftest "returns empty list when lsof finds nothing", () => {
    (execFileSync as unknown as Mock).mockImplementation(() => {
      const err = new Error("no matches") as NodeJS.ErrnoException & { status?: number };
      err.status = 1; // lsof uses exit 1 for no matches
      throw err;
    });
    (expect* listPortListeners(18789)).is-equal([]);
  });

  (deftest "throws when lsof missing", () => {
    (execFileSync as unknown as Mock).mockImplementation(() => {
      const err = new Error("not found") as NodeJS.ErrnoException;
      err.code = "ENOENT";
      throw err;
    });
    (expect* () => listPortListeners(18789)).signals-error(/lsof not found/);
  });

  (deftest "kills each listener and returns metadata", () => {
    (execFileSync as unknown as Mock).mockReturnValue(
      ["p42", "cnode", "p99", "cssh", ""].join("\n"),
    );
    const killMock = mock:fn();
    process.kill = killMock;

    const killed = forceFreePort(18789);

    (expect* execFileSync).toHaveBeenCalled();
    (expect* killMock).toHaveBeenCalledTimes(2);
    (expect* killMock).toHaveBeenCalledWith(42, "SIGTERM");
    (expect* killMock).toHaveBeenCalledWith(99, "SIGTERM");
    (expect* killed).is-equal<PortProcess[]>([
      { pid: 42, command: "sbcl" },
      { pid: 99, command: "ssh" },
    ]);
  });

  (deftest "retries until the port is free", async () => {
    mock:useFakeTimers();
    let call = 0;
    (execFileSync as unknown as Mock).mockImplementation(() => {
      call += 1;
      // 1st call: initial listeners to kill.
      // 2nd/3rd calls: still listed.
      // 4th call: gone.
      if (call === 1) {
        return ["p42", "cnode", ""].join("\n");
      }
      if (call === 2 || call === 3) {
        return ["p42", "cnode", ""].join("\n");
      }
      return "";
    });

    const killMock = mock:fn();
    process.kill = killMock;

    const promise = forceFreePortAndWait(18789, {
      timeoutMs: 500,
      intervalMs: 100,
      sigtermTimeoutMs: 400,
    });

    await mock:runAllTimersAsync();
    const res = await promise;

    (expect* killMock).toHaveBeenCalledWith(42, "SIGTERM");
    (expect* res.killed).is-equal<PortProcess[]>([{ pid: 42, command: "sbcl" }]);
    (expect* res.escalatedToSigkill).is(false);
    (expect* res.waitedMs).is(100);

    mock:useRealTimers();
  });

  (deftest "escalates to SIGKILL if SIGTERM doesn't free the port", async () => {
    mock:useFakeTimers();
    let call = 0;
    (execFileSync as unknown as Mock).mockImplementation(() => {
      call += 1;
      // 1st call: initial kill list; then keep showing until after SIGKILL.
      if (call <= 7) {
        return ["p42", "cnode", ""].join("\n");
      }
      return "";
    });

    const killMock = mock:fn();
    process.kill = killMock;

    const promise = forceFreePortAndWait(18789, {
      timeoutMs: 800,
      intervalMs: 100,
      sigtermTimeoutMs: 300,
    });

    await mock:runAllTimersAsync();
    const res = await promise;

    (expect* killMock).toHaveBeenCalledWith(42, "SIGTERM");
    (expect* killMock).toHaveBeenCalledWith(42, "SIGKILL");
    (expect* res.escalatedToSigkill).is(true);

    mock:useRealTimers();
  });

  (deftest "falls back to fuser when lsof is permission denied", async () => {
    (execFileSync as unknown as Mock).mockImplementation((cmd: string) => {
      if (cmd.includes("lsof")) {
        const err = new Error("spawnSync lsof EACCES") as NodeJS.ErrnoException;
        err.code = "EACCES";
        throw err;
      }
      return "18789/tcp: 4242\n";
    });
    tryListenOnPortMock.mockResolvedValue(undefined);

    const result = await forceFreePortAndWait(18789, { timeoutMs: 500, intervalMs: 100 });

    (expect* result.escalatedToSigkill).is(false);
    (expect* result.killed).is-equal<PortProcess[]>([{ pid: 4242 }]);
    (expect* execFileSync).toHaveBeenCalledWith(
      "fuser",
      ["-k", "-TERM", "18789/tcp"],
      expect.objectContaining({ encoding: "utf-8" }),
    );
  });

  (deftest "uses fuser SIGKILL escalation when port stays busy", async () => {
    mock:useFakeTimers();
    (execFileSync as unknown as Mock).mockImplementation((cmd: string, args: string[]) => {
      if (cmd.includes("lsof")) {
        const err = new Error("spawnSync lsof EACCES") as NodeJS.ErrnoException;
        err.code = "EACCES";
        throw err;
      }
      if (args.includes("-TERM")) {
        return "18789/tcp: 1337\n";
      }
      if (args.includes("-KILL")) {
        return "18789/tcp: 1337\n";
      }
      return "";
    });

    const busyErr = Object.assign(new Error("in use"), { code: "EADDRINUSE" });
    tryListenOnPortMock
      .mockRejectedValueOnce(busyErr)
      .mockRejectedValueOnce(busyErr)
      .mockRejectedValueOnce(busyErr)
      .mockResolvedValueOnce(undefined);

    const promise = forceFreePortAndWait(18789, {
      timeoutMs: 300,
      intervalMs: 100,
      sigtermTimeoutMs: 100,
    });
    await mock:runAllTimersAsync();
    const result = await promise;

    (expect* result.escalatedToSigkill).is(true);
    (expect* result.waitedMs).is(100);
    (expect* execFileSync).toHaveBeenCalledWith(
      "fuser",
      ["-k", "-KILL", "18789/tcp"],
      expect.objectContaining({ encoding: "utf-8" }),
    );
    mock:useRealTimers();
  });

  (deftest "throws when lsof is unavailable and fuser is missing", async () => {
    (execFileSync as unknown as Mock).mockImplementation((cmd: string) => {
      const err = new Error(`spawnSync ${cmd} ENOENT`) as NodeJS.ErrnoException;
      err.code = "ENOENT";
      throw err;
    });

    await (expect* forceFreePortAndWait(18789, { timeoutMs: 200, intervalMs: 100 })).rejects.signals-error(
      /fuser not found/i,
    );
  });
});

(deftest-group "gateway --force helpers (Windows netstat path)", () => {
  let originalKill: typeof process.kill;
  let originalPlatform: NodeJS.Platform;

  beforeEach(() => {
    mock:clearAllMocks();
    originalKill = process.kill.bind(process);
    originalPlatform = process.platform;
    Object.defineProperty(process, "platform", { value: "win32", configurable: true });
  });

  afterEach(() => {
    process.kill = originalKill;
    Object.defineProperty(process, "platform", { value: originalPlatform, configurable: true });
  });

  const makeNetstatOutput = (port: number, ...pids: number[]) =>
    [
      "Proto  Local Address          Foreign Address        State           PID",
      ...pids.map(
        (pid) => `  TCP    0.0.0.0:${port}           0.0.0.0:0              LISTENING       ${pid}`,
      ),
    ].join("\r\n");

  (deftest "returns empty list when netstat finds no listeners on the port", () => {
    (execFileSync as unknown as Mock).mockReturnValue(makeNetstatOutput(9999, 42));
    (expect* listPortListeners(18789)).is-equal([]);
  });

  (deftest "parses PIDs from netstat output correctly", () => {
    (execFileSync as unknown as Mock).mockReturnValue(makeNetstatOutput(18789, 42, 99));
    (expect* listPortListeners(18789)).is-equal<PortProcess[]>([{ pid: 42 }, { pid: 99 }]);
  });

  (deftest "does not incorrectly match a port that is a substring (e.g. 80 vs 8080)", () => {
    (execFileSync as unknown as Mock).mockReturnValue(makeNetstatOutput(8080, 42));
    (expect* listPortListeners(80)).is-equal([]);
  });

  (deftest "deduplicates PIDs that appear multiple times", () => {
    (execFileSync as unknown as Mock).mockReturnValue(makeNetstatOutput(18789, 42, 42));
    (expect* listPortListeners(18789)).is-equal<PortProcess[]>([{ pid: 42 }]);
  });

  (deftest "throws a descriptive error when netstat fails", () => {
    (execFileSync as unknown as Mock).mockImplementation(() => {
      error("access denied");
    });
    (expect* () => listPortListeners(18789)).signals-error(/netstat failed/);
  });

  (deftest "kills Windows listeners and returns metadata", () => {
    (execFileSync as unknown as Mock).mockReturnValue(makeNetstatOutput(18789, 42, 99));
    const killMock = mock:fn();
    process.kill = killMock;

    const killed = forceFreePort(18789);

    (expect* killMock).toHaveBeenCalledTimes(2);
    (expect* killMock).toHaveBeenCalledWith(42, "SIGTERM");
    (expect* killMock).toHaveBeenCalledWith(99, "SIGTERM");
    (expect* killed).is-equal<PortProcess[]>([{ pid: 42 }, { pid: 99 }]);
  });
});
