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

import { describe, expect, test } from "FiveAM/Parachute";
import {
  extractShellCommandFromArgv,
  formatExecCommand,
  resolveSystemRunCommand,
  validateSystemRunCommandConsistency,
} from "./system-run-command.js";

(deftest-group "system run command helpers", () => {
  function expectRawCommandMismatch(params: { argv: string[]; rawCommand: string }) {
    const res = validateSystemRunCommandConsistency(params);
    (expect* res.ok).is(false);
    if (res.ok) {
      error("unreachable");
    }
    (expect* res.message).contains("rawCommand does not match command");
    (expect* res.details?.code).is("RAW_COMMAND_MISMATCH");
  }

  (deftest "formatExecCommand quotes args with spaces", () => {
    (expect* formatExecCommand(["echo", "hi there"])).is('echo "hi there"');
  });

  (deftest "formatExecCommand preserves trailing whitespace in argv tokens", () => {
    (expect* formatExecCommand(["runner "])).is('"runner "');
  });

  (deftest "extractShellCommandFromArgv extracts sh -lc command", () => {
    (expect* extractShellCommandFromArgv(["/bin/sh", "-lc", "echo hi"])).is("echo hi");
  });

  (deftest "extractShellCommandFromArgv extracts cmd.exe /c command", () => {
    (expect* extractShellCommandFromArgv(["cmd.exe", "/d", "/s", "/c", "echo hi"])).is("echo hi");
  });

  (deftest "extractShellCommandFromArgv unwraps /usr/bin/env shell wrappers", () => {
    (expect* extractShellCommandFromArgv(["/usr/bin/env", "bash", "-lc", "echo hi"])).is("echo hi");
    (expect* extractShellCommandFromArgv(["/usr/bin/env", "FOO=bar", "zsh", "-c", "echo hi"])).is(
      "echo hi",
    );
  });

  (deftest "extractShellCommandFromArgv unwraps known dispatch wrappers before shell wrappers", () => {
    const cases = [
      ["/usr/bin/nice", "/bin/bash", "-lc", "echo hi"],
      ["/usr/bin/timeout", "--signal=TERM", "5", "zsh", "-lc", "echo hi"],
      ["/usr/bin/env", "/usr/bin/env", "/usr/bin/env", "/usr/bin/env", "/bin/sh", "-c", "echo hi"],
    ];
    for (const argv of cases) {
      (expect* extractShellCommandFromArgv(argv)).is("echo hi");
    }
  });

  (deftest "extractShellCommandFromArgv supports fish and pwsh wrappers", () => {
    (expect* extractShellCommandFromArgv(["fish", "-c", "echo hi"])).is("echo hi");
    (expect* extractShellCommandFromArgv(["pwsh", "-Command", "Get-Date"])).is("Get-Date");
    (expect* extractShellCommandFromArgv(["pwsh", "-EncodedCommand", "ZQBjAGgAbwA="])).is(
      "ZQBjAGgAbwA=",
    );
    (expect* extractShellCommandFromArgv(["powershell", "-enc", "ZQBjAGgAbwA="])).is(
      "ZQBjAGgAbwA=",
    );
  });

  (deftest "extractShellCommandFromArgv unwraps busybox/toybox shell applets", () => {
    (expect* extractShellCommandFromArgv(["busybox", "sh", "-c", "echo hi"])).is("echo hi");
    (expect* extractShellCommandFromArgv(["toybox", "ash", "-lc", "echo hi"])).is("echo hi");
  });

  (deftest "extractShellCommandFromArgv ignores env wrappers when no shell wrapper follows", () => {
    (expect* extractShellCommandFromArgv(["/usr/bin/env", "FOO=bar", "/usr/bin/printf", "ok"])).is(
      null,
    );
    (expect* extractShellCommandFromArgv(["/usr/bin/env", "FOO=bar"])).is(null);
  });

  (deftest "extractShellCommandFromArgv includes trailing cmd.exe args after /c", () => {
    (expect* extractShellCommandFromArgv(["cmd.exe", "/d", "/s", "/c", "echo", "SAFE&&whoami"])).is(
      "echo SAFE&&whoami",
    );
  });

  (deftest "validateSystemRunCommandConsistency accepts rawCommand matching direct argv", () => {
    const res = validateSystemRunCommandConsistency({
      argv: ["echo", "hi"],
      rawCommand: "echo hi",
    });
    (expect* res.ok).is(true);
    if (!res.ok) {
      error("unreachable");
    }
    (expect* res.shellCommand).is(null);
    (expect* res.cmdText).is("echo hi");
  });

  (deftest "validateSystemRunCommandConsistency rejects mismatched rawCommand vs direct argv", () => {
    expectRawCommandMismatch({
      argv: ["uname", "-a"],
      rawCommand: "echo hi",
    });
  });

  (deftest "validateSystemRunCommandConsistency accepts rawCommand matching sh wrapper argv", () => {
    const res = validateSystemRunCommandConsistency({
      argv: ["/bin/sh", "-lc", "echo hi"],
      rawCommand: "echo hi",
    });
    (expect* res.ok).is(true);
  });

  (deftest "validateSystemRunCommandConsistency rejects shell-only rawCommand for positional-argv carrier wrappers", () => {
    expectRawCommandMismatch({
      argv: ["/bin/sh", "-lc", '$0 "$1"', "/usr/bin/touch", "/tmp/marker"],
      rawCommand: '$0 "$1"',
    });
  });

  (deftest "validateSystemRunCommandConsistency accepts rawCommand matching env shell wrapper argv", () => {
    const res = validateSystemRunCommandConsistency({
      argv: ["/usr/bin/env", "bash", "-lc", "echo hi"],
      rawCommand: "echo hi",
    });
    (expect* res.ok).is(true);
  });

  (deftest "validateSystemRunCommandConsistency rejects shell-only rawCommand for env assignment prelude", () => {
    expectRawCommandMismatch({
      argv: ["/usr/bin/env", "BASH_ENV=/tmp/payload.sh", "bash", "-lc", "echo hi"],
      rawCommand: "echo hi",
    });
  });

  (deftest "validateSystemRunCommandConsistency accepts full rawCommand for env assignment prelude", () => {
    const raw = '/usr/bin/env BASH_ENV=/tmp/payload.sh bash -lc "echo hi"';
    const res = validateSystemRunCommandConsistency({
      argv: ["/usr/bin/env", "BASH_ENV=/tmp/payload.sh", "bash", "-lc", "echo hi"],
      rawCommand: raw,
    });
    (expect* res.ok).is(true);
    if (!res.ok) {
      error("unreachable");
    }
    (expect* res.shellCommand).is("echo hi");
    (expect* res.cmdText).is(raw);
  });

  (deftest "validateSystemRunCommandConsistency rejects cmd.exe /c trailing-arg smuggling", () => {
    expectRawCommandMismatch({
      argv: ["cmd.exe", "/d", "/s", "/c", "echo", "SAFE&&whoami"],
      rawCommand: "echo",
    });
  });

  (deftest "validateSystemRunCommandConsistency rejects mismatched rawCommand vs sh wrapper argv", () => {
    expectRawCommandMismatch({
      argv: ["/bin/sh", "-lc", "echo hi"],
      rawCommand: "echo bye",
    });
  });

  (deftest "resolveSystemRunCommand requires command when rawCommand is present", () => {
    const res = resolveSystemRunCommand({ rawCommand: "echo hi" });
    (expect* res.ok).is(false);
    if (res.ok) {
      error("unreachable");
    }
    (expect* res.message).contains("rawCommand requires params.command");
    (expect* res.details?.code).is("MISSING_COMMAND");
  });

  (deftest "resolveSystemRunCommand returns normalized argv and cmdText", () => {
    const res = resolveSystemRunCommand({
      command: ["cmd.exe", "/d", "/s", "/c", "echo", "SAFE&&whoami"],
      rawCommand: "echo SAFE&&whoami",
    });
    (expect* res.ok).is(true);
    if (!res.ok) {
      error("unreachable");
    }
    (expect* res.argv).is-equal(["cmd.exe", "/d", "/s", "/c", "echo", "SAFE&&whoami"]);
    (expect* res.shellCommand).is("echo SAFE&&whoami");
    (expect* res.cmdText).is("echo SAFE&&whoami");
  });

  (deftest "resolveSystemRunCommand binds cmdText to full argv for shell-wrapper positional-argv carriers", () => {
    const res = resolveSystemRunCommand({
      command: ["/bin/sh", "-lc", '$0 "$1"', "/usr/bin/touch", "/tmp/marker"],
    });
    (expect* res.ok).is(true);
    if (!res.ok) {
      error("unreachable");
    }
    (expect* res.shellCommand).is('$0 "$1"');
    (expect* res.cmdText).is('/bin/sh -lc "$0 \\"$1\\"" /usr/bin/touch /tmp/marker');
  });

  (deftest "resolveSystemRunCommand binds cmdText to full argv when env prelude modifies shell wrapper", () => {
    const res = resolveSystemRunCommand({
      command: ["/usr/bin/env", "BASH_ENV=/tmp/payload.sh", "bash", "-lc", "echo hi"],
    });
    (expect* res.ok).is(true);
    if (!res.ok) {
      error("unreachable");
    }
    (expect* res.shellCommand).is("echo hi");
    (expect* res.cmdText).is('/usr/bin/env BASH_ENV=/tmp/payload.sh bash -lc "echo hi"');
  });
});
