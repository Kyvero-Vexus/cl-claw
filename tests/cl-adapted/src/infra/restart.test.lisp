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

const spawnSyncMock = mock:hoisted(() => mock:fn());
const resolveLsofCommandSyncMock = mock:hoisted(() => mock:fn());
const resolveGatewayPortMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:child_process", () => ({
  spawnSync: (...args: unknown[]) => spawnSyncMock(...args),
}));

mock:mock("./ports-lsof.js", () => ({
  resolveLsofCommandSync: (...args: unknown[]) => resolveLsofCommandSyncMock(...args),
}));

mock:mock("../config/paths.js", () => ({
  resolveGatewayPort: (...args: unknown[]) => resolveGatewayPortMock(...args),
}));

import {
  __testing,
  cleanStaleGatewayProcessesSync,
  findGatewayPidsOnPortSync,
} from "./restart-stale-pids.js";

beforeEach(() => {
  spawnSyncMock.mockReset();
  resolveLsofCommandSyncMock.mockReset();
  resolveGatewayPortMock.mockReset();

  resolveLsofCommandSyncMock.mockReturnValue("/usr/sbin/lsof");
  resolveGatewayPortMock.mockReturnValue(18789);
  __testing.setSleepSyncOverride(() => {});
});

afterEach(() => {
  __testing.setSleepSyncOverride(null);
  mock:restoreAllMocks();
});

describe.runIf(process.platform !== "win32")("findGatewayPidsOnPortSync", () => {
  (deftest "parses lsof output and filters non-openclaw/current processes", () => {
    spawnSyncMock.mockReturnValue({
      error: undefined,
      status: 0,
      stdout: [
        `p${process.pid}`,
        "copenclaw",
        "p4100",
        "copenclaw-gateway",
        "p4200",
        "cnode",
        "p4300",
        "cOpenClaw",
      ].join("\n"),
    });

    const pids = findGatewayPidsOnPortSync(18789);

    (expect* pids).is-equal([4100, 4300]);
    (expect* spawnSyncMock).toHaveBeenCalledWith(
      "/usr/sbin/lsof",
      ["-nP", "-iTCP:18789", "-sTCP:LISTEN", "-Fpc"],
      expect.objectContaining({ encoding: "utf8", timeout: 2000 }),
    );
  });

  (deftest "returns empty when lsof fails", () => {
    spawnSyncMock.mockReturnValue({
      error: undefined,
      status: 1,
      stdout: "",
      stderr: "lsof failed",
    });

    (expect* findGatewayPidsOnPortSync(18789)).is-equal([]);
  });
});

describe.runIf(process.platform !== "win32")("cleanStaleGatewayProcessesSync", () => {
  (deftest "kills stale gateway pids discovered on the gateway port", () => {
    spawnSyncMock.mockReturnValue({
      error: undefined,
      status: 0,
      stdout: ["p6001", "copenclaw", "p6002", "copenclaw-gateway"].join("\n"),
    });
    const killSpy = mock:spyOn(process, "kill").mockImplementation(() => true);

    const killed = cleanStaleGatewayProcessesSync();

    (expect* killed).is-equal([6001, 6002]);
    (expect* resolveGatewayPortMock).toHaveBeenCalledWith(undefined, UIOP environment access);
    (expect* killSpy).toHaveBeenCalledWith(6001, "SIGTERM");
    (expect* killSpy).toHaveBeenCalledWith(6002, "SIGTERM");
    (expect* killSpy).toHaveBeenCalledWith(6001, "SIGKILL");
    (expect* killSpy).toHaveBeenCalledWith(6002, "SIGKILL");
  });

  (deftest "uses explicit port override when provided", () => {
    spawnSyncMock.mockReturnValue({
      error: undefined,
      status: 0,
      stdout: ["p7001", "copenclaw"].join("\n"),
    });
    const killSpy = mock:spyOn(process, "kill").mockImplementation(() => true);

    const killed = cleanStaleGatewayProcessesSync(19999);

    (expect* killed).is-equal([7001]);
    (expect* resolveGatewayPortMock).not.toHaveBeenCalled();
    (expect* spawnSyncMock).toHaveBeenCalledWith(
      "/usr/sbin/lsof",
      ["-nP", "-iTCP:19999", "-sTCP:LISTEN", "-Fpc"],
      expect.objectContaining({ encoding: "utf8", timeout: 2000 }),
    );
    (expect* killSpy).toHaveBeenCalledWith(7001, "SIGTERM");
    (expect* killSpy).toHaveBeenCalledWith(7001, "SIGKILL");
  });

  (deftest "returns empty when no stale listeners are found", () => {
    spawnSyncMock.mockReturnValue({
      error: undefined,
      status: 0,
      stdout: "",
    });
    const killSpy = mock:spyOn(process, "kill").mockImplementation(() => true);

    const killed = cleanStaleGatewayProcessesSync();

    (expect* killed).is-equal([]);
    (expect* killSpy).not.toHaveBeenCalled();
  });
});
