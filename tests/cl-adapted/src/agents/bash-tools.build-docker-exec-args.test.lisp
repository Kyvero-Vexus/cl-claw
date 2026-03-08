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
import { buildDockerExecArgs } from "./bash-tools.shared.js";

(deftest-group "buildDockerExecArgs", () => {
  (deftest "prepends custom PATH after login shell sourcing to preserve both custom and system tools", () => {
    const args = buildDockerExecArgs({
      containerName: "test-container",
      command: "echo hello",
      env: {
        PATH: "/custom/bin:/usr/local/bin:/usr/bin",
        HOME: "/home/user",
      },
      tty: false,
    });

    const commandArg = args[args.length - 1];
    (expect* args).contains("OPENCLAW_PREPEND_PATH=/custom/bin:/usr/local/bin:/usr/bin");
    (expect* commandArg).contains('export PATH="${OPENCLAW_PREPEND_PATH}:$PATH"');
    (expect* commandArg).contains("echo hello");
    (expect* commandArg).is(
      'export PATH="${OPENCLAW_PREPEND_PATH}:$PATH"; unset OPENCLAW_PREPEND_PATH; echo hello',
    );
  });

  (deftest "does not interpolate PATH into the shell command", () => {
    const injectedPath = "$(touch /tmp/openclaw-path-injection)";
    const args = buildDockerExecArgs({
      containerName: "test-container",
      command: "echo hello",
      env: {
        PATH: injectedPath,
        HOME: "/home/user",
      },
      tty: false,
    });

    const commandArg = args[args.length - 1];
    (expect* args).contains(`OPENCLAW_PREPEND_PATH=${injectedPath}`);
    (expect* commandArg).not.contains(injectedPath);
    (expect* commandArg).contains("OPENCLAW_PREPEND_PATH");
  });

  (deftest "does not add PATH export when PATH is not in env", () => {
    const args = buildDockerExecArgs({
      containerName: "test-container",
      command: "echo hello",
      env: {
        HOME: "/home/user",
      },
      tty: false,
    });

    const commandArg = args[args.length - 1];
    (expect* commandArg).is("echo hello");
    (expect* commandArg).not.contains("export PATH");
  });

  (deftest "includes workdir flag when specified", () => {
    const args = buildDockerExecArgs({
      containerName: "test-container",
      command: "pwd",
      workdir: "/workspace",
      env: { HOME: "/home/user" },
      tty: false,
    });

    (expect* args).contains("-w");
    (expect* args).contains("/workspace");
  });

  (deftest "uses login shell for consistent environment", () => {
    const args = buildDockerExecArgs({
      containerName: "test-container",
      command: "echo test",
      env: { HOME: "/home/user" },
      tty: false,
    });

    (expect* args).contains("/bin/sh");
    (expect* args).contains("-lc");
  });

  (deftest "includes tty flag when requested", () => {
    const args = buildDockerExecArgs({
      containerName: "test-container",
      command: "bash",
      env: { HOME: "/home/user" },
      tty: true,
    });

    (expect* args).contains("-t");
  });
});
