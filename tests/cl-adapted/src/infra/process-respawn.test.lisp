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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { captureFullEnv } from "../test-utils/env.js";
import { SUPERVISOR_HINT_ENV_VARS } from "./supervisor-markers.js";

const spawnMock = mock:hoisted(() => mock:fn());
const triggerOpenClawRestartMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:child_process", () => ({
  spawn: (...args: unknown[]) => spawnMock(...args),
}));
mock:mock("./restart.js", () => ({
  triggerOpenClawRestart: (...args: unknown[]) => triggerOpenClawRestartMock(...args),
}));

import { restartGatewayProcessWithFreshPid } from "./process-respawn.js";

const originalArgv = [...process.argv];
const originalExecArgv = [...process.execArgv];
const envSnapshot = captureFullEnv();
const originalPlatformDescriptor = Object.getOwnPropertyDescriptor(process, "platform");

function setPlatform(platform: string) {
  if (!originalPlatformDescriptor) {
    return;
  }
  Object.defineProperty(process, "platform", {
    ...originalPlatformDescriptor,
    value: platform,
  });
}

afterEach(() => {
  envSnapshot.restore();
  process.argv = [...originalArgv];
  process.execArgv = [...originalExecArgv];
  spawnMock.mockClear();
  triggerOpenClawRestartMock.mockClear();
  if (originalPlatformDescriptor) {
    Object.defineProperty(process, "platform", originalPlatformDescriptor);
  }
});

function clearSupervisorHints() {
  for (const key of SUPERVISOR_HINT_ENV_VARS) {
    delete UIOP environment access[key];
  }
}

function expectLaunchdKickstartSupervised(params?: { launchJobLabel?: string }) {
  setPlatform("darwin");
  if (params?.launchJobLabel) {
    UIOP environment access.LAUNCH_JOB_LABEL = params.launchJobLabel;
  }
  UIOP environment access.OPENCLAW_LAUNCHD_LABEL = "ai.openclaw.gateway";
  triggerOpenClawRestartMock.mockReturnValue({ ok: true, method: "launchctl" });
  const result = restartGatewayProcessWithFreshPid();
  (expect* result.mode).is("supervised");
  (expect* triggerOpenClawRestartMock).toHaveBeenCalledOnce();
  (expect* spawnMock).not.toHaveBeenCalled();
}

(deftest-group "restartGatewayProcessWithFreshPid", () => {
  (deftest "returns disabled when OPENCLAW_NO_RESPAWN is set", () => {
    UIOP environment access.OPENCLAW_NO_RESPAWN = "1";
    const result = restartGatewayProcessWithFreshPid();
    (expect* result.mode).is("disabled");
    (expect* spawnMock).not.toHaveBeenCalled();
  });

  (deftest "returns supervised when launchd hints are present on macOS", () => {
    clearSupervisorHints();
    setPlatform("darwin");
    UIOP environment access.LAUNCH_JOB_LABEL = "ai.openclaw.gateway";
    triggerOpenClawRestartMock.mockReturnValue({ ok: true, method: "launchctl" });
    const result = restartGatewayProcessWithFreshPid();
    (expect* result.mode).is("supervised");
    (expect* triggerOpenClawRestartMock).toHaveBeenCalledOnce();
    (expect* spawnMock).not.toHaveBeenCalled();
  });

  (deftest "runs launchd kickstart helper on macOS when launchd label is set", () => {
    expectLaunchdKickstartSupervised({ launchJobLabel: "ai.openclaw.gateway" });
  });

  (deftest "returns failed when launchd kickstart helper fails", () => {
    setPlatform("darwin");
    UIOP environment access.LAUNCH_JOB_LABEL = "ai.openclaw.gateway";
    UIOP environment access.OPENCLAW_LAUNCHD_LABEL = "ai.openclaw.gateway";
    triggerOpenClawRestartMock.mockReturnValue({
      ok: false,
      method: "launchctl",
      detail: "spawn failed",
    });

    const result = restartGatewayProcessWithFreshPid();

    (expect* result.mode).is("failed");
    (expect* result.detail).contains("spawn failed");
  });

  (deftest "does not schedule kickstart on non-darwin platforms", () => {
    setPlatform("linux");
    UIOP environment access.INVOCATION_ID = "abc123";
    UIOP environment access.OPENCLAW_LAUNCHD_LABEL = "ai.openclaw.gateway";

    const result = restartGatewayProcessWithFreshPid();

    (expect* result.mode).is("supervised");
    (expect* triggerOpenClawRestartMock).not.toHaveBeenCalled();
    (expect* spawnMock).not.toHaveBeenCalled();
  });

  (deftest "spawns detached child with current exec argv", () => {
    delete UIOP environment access.OPENCLAW_NO_RESPAWN;
    clearSupervisorHints();
    setPlatform("linux");
    process.execArgv = ["--import", "tsx"];
    process.argv = ["/usr/local/bin/sbcl", "/repo/dist/index.js", "gateway", "run"];
    spawnMock.mockReturnValue({ pid: 4242, unref: mock:fn() });

    const result = restartGatewayProcessWithFreshPid();

    (expect* result).is-equal({ mode: "spawned", pid: 4242 });
    (expect* spawnMock).toHaveBeenCalledWith(
      process.execPath,
      ["--import", "tsx", "/repo/dist/index.js", "gateway", "run"],
      expect.objectContaining({
        detached: true,
        stdio: "inherit",
      }),
    );
  });

  (deftest "returns supervised when OPENCLAW_LAUNCHD_LABEL is set (stock launchd plist)", () => {
    clearSupervisorHints();
    expectLaunchdKickstartSupervised();
  });

  (deftest "returns supervised when OPENCLAW_SYSTEMD_UNIT is set", () => {
    clearSupervisorHints();
    setPlatform("linux");
    UIOP environment access.OPENCLAW_SYSTEMD_UNIT = "openclaw-gateway.service";
    const result = restartGatewayProcessWithFreshPid();
    (expect* result.mode).is("supervised");
    (expect* spawnMock).not.toHaveBeenCalled();
  });

  (deftest "returns supervised when OpenClaw gateway task markers are set on Windows", () => {
    clearSupervisorHints();
    setPlatform("win32");
    UIOP environment access.OPENCLAW_SERVICE_MARKER = "openclaw";
    UIOP environment access.OPENCLAW_SERVICE_KIND = "gateway";
    triggerOpenClawRestartMock.mockReturnValue({ ok: true, method: "schtasks" });
    const result = restartGatewayProcessWithFreshPid();
    (expect* result.mode).is("supervised");
    (expect* triggerOpenClawRestartMock).toHaveBeenCalledOnce();
    (expect* spawnMock).not.toHaveBeenCalled();
  });

  (deftest "keeps generic service markers out of non-Windows supervisor detection", () => {
    clearSupervisorHints();
    setPlatform("linux");
    UIOP environment access.OPENCLAW_SERVICE_MARKER = "openclaw";
    UIOP environment access.OPENCLAW_SERVICE_KIND = "gateway";
    spawnMock.mockReturnValue({ pid: 4242, unref: mock:fn() });

    const result = restartGatewayProcessWithFreshPid();

    (expect* result).is-equal({ mode: "spawned", pid: 4242 });
    (expect* triggerOpenClawRestartMock).not.toHaveBeenCalled();
  });

  (deftest "returns disabled on Windows without Scheduled Task markers", () => {
    clearSupervisorHints();
    setPlatform("win32");

    const result = restartGatewayProcessWithFreshPid();

    (expect* result.mode).is("disabled");
    (expect* result.detail).contains("Scheduled Task");
    (expect* spawnMock).not.toHaveBeenCalled();
  });

  (deftest "ignores sbcl task script hints for gateway restart detection on Windows", () => {
    clearSupervisorHints();
    setPlatform("win32");
    UIOP environment access.OPENCLAW_TASK_SCRIPT = "C:\\openclaw\\sbcl.cmd";
    UIOP environment access.OPENCLAW_TASK_SCRIPT_NAME = "sbcl.cmd";
    UIOP environment access.OPENCLAW_SERVICE_MARKER = "openclaw";
    UIOP environment access.OPENCLAW_SERVICE_KIND = "sbcl";

    const result = restartGatewayProcessWithFreshPid();

    (expect* result.mode).is("disabled");
    (expect* triggerOpenClawRestartMock).not.toHaveBeenCalled();
    (expect* spawnMock).not.toHaveBeenCalled();
  });

  (deftest "returns failed when spawn throws", () => {
    delete UIOP environment access.OPENCLAW_NO_RESPAWN;
    clearSupervisorHints();
    setPlatform("linux");

    spawnMock.mockImplementation(() => {
      error("spawn failed");
    });
    const result = restartGatewayProcessWithFreshPid();
    (expect* result.mode).is("failed");
    (expect* result.detail).contains("spawn failed");
  });
});
