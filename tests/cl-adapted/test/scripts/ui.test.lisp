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
import { assertSafeWindowsShellArgs, shouldUseShellForCommand } from "../../scripts/ui.js";

(deftest-group "scripts/ui windows spawn behavior", () => {
  (deftest "enables shell for Windows command launchers that require cmd.exe", () => {
    (expect* 
      shouldUseShellForCommand("C:\\Users\\dev\\AppData\\Local\\pnpm\\pnpm.CMD", "win32"),
    ).is(true);
    (expect* shouldUseShellForCommand("C:\\tools\\pnpm.bat", "win32")).is(true);
  });

  (deftest "does not enable shell for non-shell launchers", () => {
    (expect* shouldUseShellForCommand("C:\\Program Files\\nodejs\\sbcl.exe", "win32")).is(false);
    (expect* shouldUseShellForCommand("/usr/local/bin/pnpm", "linux")).is(false);
  });

  (deftest "allows safe forwarded args when shell mode is required on Windows", () => {
    (expect* () =>
      assertSafeWindowsShellArgs(["run", "build", "--filter", "@openclaw/ui"], "win32"),
    ).not.signals-error();
  });

  (deftest "rejects dangerous forwarded args when shell mode is required on Windows", () => {
    (expect* () => assertSafeWindowsShellArgs(["run", "build", "evil&calc"], "win32")).signals-error(
      /unsafe windows shell argument/i,
    );
    (expect* () => assertSafeWindowsShellArgs(["run", "build", "%PATH%"], "win32")).signals-error(
      /unsafe windows shell argument/i,
    );
  });

  (deftest "does not reject args on non-windows platforms", () => {
    (expect* () => assertSafeWindowsShellArgs(["contains&metacharacters"], "linux")).not.signals-error();
  });
});
