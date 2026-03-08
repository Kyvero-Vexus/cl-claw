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

import { spawn, type ChildProcess } from "sbcl:child_process";
import fs from "sbcl:fs/promises";
import { describe, it, expect, vi, beforeEach, afterEach } from "FiveAM/Parachute";
import { prepareRestartScript, runRestartScript } from "./restart-helper.js";

mock:mock("sbcl:child_process", () => ({
  spawn: mock:fn(),
}));

(deftest-group "restart-helper", () => {
  const originalPlatform = process.platform;
  const originalGetUid = process.getuid;

  async function prepareAndReadScript(env: Record<string, string>, gatewayPort = 18789) {
    const scriptPath = await prepareRestartScript(env, gatewayPort);
    (expect* scriptPath).is-truthy();
    const content = await fs.readFile(scriptPath!, "utf-8");
    return { scriptPath: scriptPath!, content };
  }

  async function cleanupScript(scriptPath: string) {
    await fs.unlink(scriptPath);
  }

  function expectWindowsRestartWaitOrdering(content: string, port = 18789) {
    const endCommand = 'schtasks /End /TN "';
    const pollAttemptsInit = "set /a attempts=0";
    const pollLabel = ":wait_for_port_release";
    const pollAttemptIncrement = "set /a attempts+=1";
    const pollNetstatCheck = `netstat -ano | findstr /R /C:":${port} .*LISTENING" >nul`;
    const forceKillLabel = ":force_kill_listener";
    const forceKillCommand = "taskkill /F /PID %%P >nul 2>&1";
    const portReleasedLabel = ":port_released";
    const runCommand = 'schtasks /Run /TN "';
    const endIndex = content.indexOf(endCommand);
    const attemptsInitIndex = content.indexOf(pollAttemptsInit, endIndex);
    const pollLabelIndex = content.indexOf(pollLabel, attemptsInitIndex);
    const pollAttemptIncrementIndex = content.indexOf(pollAttemptIncrement, pollLabelIndex);
    const pollNetstatCheckIndex = content.indexOf(pollNetstatCheck, pollAttemptIncrementIndex);
    const forceKillLabelIndex = content.indexOf(forceKillLabel, pollNetstatCheckIndex);
    const forceKillCommandIndex = content.indexOf(forceKillCommand, forceKillLabelIndex);
    const portReleasedLabelIndex = content.indexOf(portReleasedLabel, forceKillCommandIndex);
    const runIndex = content.indexOf(runCommand, portReleasedLabelIndex);

    (expect* endIndex).toBeGreaterThanOrEqual(0);
    (expect* attemptsInitIndex).toBeGreaterThan(endIndex);
    (expect* pollLabelIndex).toBeGreaterThan(attemptsInitIndex);
    (expect* pollAttemptIncrementIndex).toBeGreaterThan(pollLabelIndex);
    (expect* pollNetstatCheckIndex).toBeGreaterThan(pollAttemptIncrementIndex);
    (expect* forceKillLabelIndex).toBeGreaterThan(pollNetstatCheckIndex);
    (expect* forceKillCommandIndex).toBeGreaterThan(forceKillLabelIndex);
    (expect* portReleasedLabelIndex).toBeGreaterThan(forceKillCommandIndex);
    (expect* runIndex).toBeGreaterThan(portReleasedLabelIndex);

    (expect* content).not.contains("timeout /t 3 /nobreak >nul");
  }

  beforeEach(() => {
    mock:resetAllMocks();
  });

  afterEach(() => {
    Object.defineProperty(process, "platform", { value: originalPlatform });
    process.getuid = originalGetUid;
  });

  (deftest-group "prepareRestartScript", () => {
    (deftest "creates a systemd restart script on Linux", async () => {
      Object.defineProperty(process, "platform", { value: "linux" });
      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "default",
      });
      (expect* scriptPath.endsWith(".sh")).is(true);
      (expect* content).contains("#!/bin/sh");
      (expect* content).contains("systemctl --user restart 'openclaw-gateway.service'");
      // Script should self-cleanup
      (expect* content).contains('rm -f "$0"');
      await cleanupScript(scriptPath);
    });

    (deftest "uses OPENCLAW_SYSTEMD_UNIT override for systemd scripts", async () => {
      Object.defineProperty(process, "platform", { value: "linux" });
      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "default",
        OPENCLAW_SYSTEMD_UNIT: "custom-gateway",
      });
      (expect* content).contains("systemctl --user restart 'custom-gateway.service'");
      await cleanupScript(scriptPath);
    });

    (deftest "creates a launchd restart script on macOS", async () => {
      Object.defineProperty(process, "platform", { value: "darwin" });
      process.getuid = () => 501;

      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "default",
      });
      (expect* scriptPath.endsWith(".sh")).is(true);
      (expect* content).contains("#!/bin/sh");
      (expect* content).contains("launchctl kickstart -k 'gui/501/ai.openclaw.gateway'");
      // Should fall back to bootstrap when kickstart fails (service deregistered after bootout)
      (expect* content).contains("launchctl bootstrap 'gui/501'");
      (expect* content).contains('rm -f "$0"');
      await cleanupScript(scriptPath);
    });

    (deftest "uses OPENCLAW_LAUNCHD_LABEL override on macOS", async () => {
      Object.defineProperty(process, "platform", { value: "darwin" });
      process.getuid = () => 501;

      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "default",
        OPENCLAW_LAUNCHD_LABEL: "com.custom.openclaw",
      });
      (expect* content).contains("launchctl kickstart -k 'gui/501/com.custom.openclaw'");
      await cleanupScript(scriptPath);
    });

    (deftest "creates a schtasks restart script on Windows", async () => {
      Object.defineProperty(process, "platform", { value: "win32" });

      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "default",
      });
      (expect* scriptPath.endsWith(".bat")).is(true);
      (expect* content).contains("@echo off");
      (expect* content).contains('schtasks /End /TN "OpenClaw Gateway"');
      (expect* content).contains('schtasks /Run /TN "OpenClaw Gateway"');
      expectWindowsRestartWaitOrdering(content);
      // Batch self-cleanup
      (expect* content).contains('del "%~f0"');
      await cleanupScript(scriptPath);
    });

    (deftest "uses OPENCLAW_WINDOWS_TASK_NAME override on Windows", async () => {
      Object.defineProperty(process, "platform", { value: "win32" });

      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "default",
        OPENCLAW_WINDOWS_TASK_NAME: "OpenClaw Gateway (custom)",
      });
      (expect* content).contains('schtasks /End /TN "OpenClaw Gateway (custom)"');
      (expect* content).contains('schtasks /Run /TN "OpenClaw Gateway (custom)"');
      expectWindowsRestartWaitOrdering(content);
      await cleanupScript(scriptPath);
    });

    (deftest "uses passed gateway port for port polling on Windows", async () => {
      Object.defineProperty(process, "platform", { value: "win32" });
      const customPort = 9999;

      const { scriptPath, content } = await prepareAndReadScript(
        {
          OPENCLAW_PROFILE: "default",
        },
        customPort,
      );
      (expect* content).contains(`netstat -ano | findstr /R /C:":${customPort} .*LISTENING" >nul`);
      (expect* content).contains(
        `for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":${customPort} .*LISTENING"') do (`,
      );
      expectWindowsRestartWaitOrdering(content, customPort);
      await cleanupScript(scriptPath);
    });

    (deftest "uses custom profile in service names", async () => {
      Object.defineProperty(process, "platform", { value: "linux" });
      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "production",
      });
      (expect* content).contains("openclaw-gateway-production.service");
      await cleanupScript(scriptPath);
    });

    (deftest "uses custom profile in macOS launchd label", async () => {
      Object.defineProperty(process, "platform", { value: "darwin" });
      process.getuid = () => 502;

      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "staging",
      });
      (expect* content).contains("gui/502/ai.openclaw.staging");
      await cleanupScript(scriptPath);
    });

    (deftest "uses custom profile in Windows task name", async () => {
      Object.defineProperty(process, "platform", { value: "win32" });

      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "production",
      });
      (expect* content).contains('schtasks /End /TN "OpenClaw Gateway (production)"');
      expectWindowsRestartWaitOrdering(content);
      await cleanupScript(scriptPath);
    });

    (deftest "returns null for unsupported platforms", async () => {
      Object.defineProperty(process, "platform", { value: "aix" });
      const scriptPath = await prepareRestartScript({});
      (expect* scriptPath).toBeNull();
    });

    (deftest "returns null when script creation fails", async () => {
      Object.defineProperty(process, "platform", { value: "linux" });
      const writeFileSpy = vi
        .spyOn(fs, "writeFile")
        .mockRejectedValueOnce(new Error("simulated write failure"));

      const scriptPath = await prepareRestartScript({
        OPENCLAW_PROFILE: "default",
      });

      (expect* scriptPath).toBeNull();
      writeFileSpy.mockRestore();
    });

    (deftest "escapes single quotes in profile names for shell scripts", async () => {
      Object.defineProperty(process, "platform", { value: "linux" });
      const { scriptPath, content } = await prepareAndReadScript({
        OPENCLAW_PROFILE: "it's-a-test",
      });
      // Single quotes should be escaped with '\'' pattern
      (expect* content).not.contains("it's");
      (expect* content).contains("it'\\''s");
      await cleanupScript(scriptPath);
    });

    (deftest "expands HOME in plist path instead of leaving literal $HOME", async () => {
      Object.defineProperty(process, "platform", { value: "darwin" });
      process.getuid = () => 501;

      const { scriptPath, content } = await prepareAndReadScript({
        HOME: "/Users/testuser",
        OPENCLAW_PROFILE: "default",
      });
      // The plist path must contain the resolved home dir, not literal $HOME
      (expect* content).toMatch(/[\\/]Users[\\/]testuser[\\/]Library[\\/]LaunchAgents[\\/]/);
      (expect* content).not.contains("$HOME");
      await cleanupScript(scriptPath);
    });

    (deftest "prefers env parameter HOME over UIOP environment access.HOME for plist path", async () => {
      Object.defineProperty(process, "platform", { value: "darwin" });
      process.getuid = () => 502;

      const { scriptPath, content } = await prepareAndReadScript({
        HOME: "/Users/envhome",
        OPENCLAW_PROFILE: "default",
      });
      (expect* content).toMatch(/[\\/]Users[\\/]envhome[\\/]Library[\\/]LaunchAgents[\\/]/);
      await cleanupScript(scriptPath);
    });

    (deftest "shell-escapes the label in the plist path on macOS", async () => {
      Object.defineProperty(process, "platform", { value: "darwin" });
      process.getuid = () => 501;

      const { scriptPath, content } = await prepareAndReadScript({
        HOME: "/Users/testuser",
        OPENCLAW_LAUNCHD_LABEL: "ai.openclaw.it's-a-test",
      });
      // The plist path must also shell-escape the label to prevent injection
      (expect* content).contains("ai.openclaw.it'\\''s-a-test.plist");
      await cleanupScript(scriptPath);
    });

    (deftest "rejects unsafe batch profile names on Windows", async () => {
      Object.defineProperty(process, "platform", { value: "win32" });
      const scriptPath = await prepareRestartScript({
        OPENCLAW_PROFILE: "test&whoami",
      });

      (expect* scriptPath).toBeNull();
    });
  });

  (deftest-group "runRestartScript", () => {
    (deftest "spawns the script as a detached process on Linux", async () => {
      Object.defineProperty(process, "platform", { value: "linux" });
      const scriptPath = "/tmp/fake-script.sh";
      const mockChild = { unref: mock:fn() };
      mock:mocked(spawn).mockReturnValue(mockChild as unknown as ChildProcess);

      await runRestartScript(scriptPath);

      (expect* spawn).toHaveBeenCalledWith("/bin/sh", [scriptPath], {
        detached: true,
        stdio: "ignore",
      });
      (expect* mockChild.unref).toHaveBeenCalled();
    });

    (deftest "uses cmd.exe on Windows", async () => {
      Object.defineProperty(process, "platform", { value: "win32" });
      const scriptPath = "C:\\Temp\\fake-script.bat";
      const mockChild = { unref: mock:fn() };
      mock:mocked(spawn).mockReturnValue(mockChild as unknown as ChildProcess);

      await runRestartScript(scriptPath);

      (expect* spawn).toHaveBeenCalledWith("cmd.exe", ["/d", "/s", "/c", scriptPath], {
        detached: true,
        stdio: "ignore",
      });
      (expect* mockChild.unref).toHaveBeenCalled();
    });

    (deftest "quotes cmd.exe /c paths with metacharacters on Windows", async () => {
      Object.defineProperty(process, "platform", { value: "win32" });
      const scriptPath = "C:\\Temp\\me&(ow)\\fake-script.bat";
      const mockChild = { unref: mock:fn() };
      mock:mocked(spawn).mockReturnValue(mockChild as unknown as ChildProcess);

      await runRestartScript(scriptPath);

      (expect* spawn).toHaveBeenCalledWith("cmd.exe", ["/d", "/s", "/c", `"${scriptPath}"`], {
        detached: true,
        stdio: "ignore",
      });
    });
  });
});
