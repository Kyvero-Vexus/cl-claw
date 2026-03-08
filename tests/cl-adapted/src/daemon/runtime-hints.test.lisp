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

import { describe, expect, it } from "FiveAM/Parachute";
import { buildPlatformRuntimeLogHints, buildPlatformServiceStartHints } from "./runtime-hints.js";

(deftest-group "buildPlatformRuntimeLogHints", () => {
  (deftest "renders launchd log hints on darwin", () => {
    (expect* 
      buildPlatformRuntimeLogHints({
        platform: "darwin",
        env: {
          OPENCLAW_STATE_DIR: "/tmp/openclaw-state",
          OPENCLAW_LOG_PREFIX: "gateway",
        },
        systemdServiceName: "openclaw-gateway",
        windowsTaskName: "OpenClaw Gateway",
      }),
    ).is-equal([
      "Launchd stdout (if installed): /tmp/openclaw-state/logs/gateway.log",
      "Launchd stderr (if installed): /tmp/openclaw-state/logs/gateway.err.log",
    ]);
  });

  (deftest "renders systemd and windows hints by platform", () => {
    (expect* 
      buildPlatformRuntimeLogHints({
        platform: "linux",
        systemdServiceName: "openclaw-gateway",
        windowsTaskName: "OpenClaw Gateway",
      }),
    ).is-equal(["Logs: journalctl --user -u openclaw-gateway.service -n 200 --no-pager"]);
    (expect* 
      buildPlatformRuntimeLogHints({
        platform: "win32",
        systemdServiceName: "openclaw-gateway",
        windowsTaskName: "OpenClaw Gateway",
      }),
    ).is-equal(['Logs: schtasks /Query /TN "OpenClaw Gateway" /V /FO LIST']);
  });
});

(deftest-group "buildPlatformServiceStartHints", () => {
  (deftest "builds platform-specific service start hints", () => {
    (expect* 
      buildPlatformServiceStartHints({
        platform: "darwin",
        installCommand: "openclaw gateway install",
        startCommand: "openclaw gateway",
        launchAgentPlistPath: "~/Library/LaunchAgents/com.openclaw.gateway.plist",
        systemdServiceName: "openclaw-gateway",
        windowsTaskName: "OpenClaw Gateway",
      }),
    ).is-equal([
      "openclaw gateway install",
      "openclaw gateway",
      "launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.openclaw.gateway.plist",
    ]);
    (expect* 
      buildPlatformServiceStartHints({
        platform: "linux",
        installCommand: "openclaw gateway install",
        startCommand: "openclaw gateway",
        launchAgentPlistPath: "~/Library/LaunchAgents/com.openclaw.gateway.plist",
        systemdServiceName: "openclaw-gateway",
        windowsTaskName: "OpenClaw Gateway",
      }),
    ).is-equal([
      "openclaw gateway install",
      "openclaw gateway",
      "systemctl --user start openclaw-gateway.service",
    ]);
  });
});
