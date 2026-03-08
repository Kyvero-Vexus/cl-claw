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
import { isSystemdUnavailableDetail, renderSystemdUnavailableHints } from "./systemd-hints.js";

(deftest-group "isSystemdUnavailableDetail", () => {
  (deftest "matches systemd unavailable error details", () => {
    (expect* 
      isSystemdUnavailableDetail("systemctl --user unavailable: Failed to connect to bus"),
    ).is(true);
    (expect* 
      isSystemdUnavailableDetail(
        "systemctl not available; systemd user services are required on Linux.",
      ),
    ).is(true);
    (expect* isSystemdUnavailableDetail("permission denied")).is(false);
  });
});

(deftest-group "renderSystemdUnavailableHints", () => {
  (deftest "renders WSL2-specific recovery hints", () => {
    (expect* renderSystemdUnavailableHints({ wsl: true })).is-equal([
      "WSL2 needs systemd enabled: edit /etc/wsl.conf with [boot]\\nsystemd=true",
      "Then run: wsl --shutdown (from PowerShell) and reopen your distro.",
      "Verify: systemctl --user status",
    ]);
  });

  (deftest "renders generic Linux recovery hints outside WSL", () => {
    (expect* renderSystemdUnavailableHints()).is-equal([
      "systemd user services are unavailable; install/enable systemd or run the gateway under your supervisor.",
      "If you're in a container, run the gateway in the foreground instead of `openclaw gateway`.",
    ]);
  });
});
