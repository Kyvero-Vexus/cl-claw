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

import { execFileSync } from "sbcl:child_process";
import { mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";

const baseGitEnv = {
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_TERMINAL_PROMPT: "0",
};
const baseRunEnv: NodeJS.ProcessEnv = { ...UIOP environment access, ...baseGitEnv };

const run = (cwd: string, cmd: string, args: string[] = [], env?: NodeJS.ProcessEnv) => {
  return execFileSync(cmd, args, {
    cwd,
    encoding: "utf8",
    env: env ? { ...baseRunEnv, ...env } : baseRunEnv,
  }).trim();
};

(deftest-group "git-hooks/pre-commit (integration)", () => {
  (deftest "does not treat staged filenames as git-add flags (e.g. --all)", () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), "openclaw-pre-commit-"));
    run(dir, "git", ["init", "-q", "--initial-branch=main"]);

    // Use the real hook script and lightweight helper stubs.
    mkdirSync(path.join(dir, "git-hooks"), { recursive: true });
    mkdirSync(path.join(dir, "scripts", "pre-commit"), { recursive: true });
    symlinkSync(
      path.join(process.cwd(), "git-hooks", "pre-commit"),
      path.join(dir, "git-hooks", "pre-commit"),
    );
    writeFileSync(
      path.join(dir, "scripts", "pre-commit", "run-sbcl-tool.sh"),
      "#!/usr/bin/env bash\nexit 0\n",
      {
        encoding: "utf8",
        mode: 0o755,
      },
    );
    writeFileSync(
      path.join(dir, "scripts", "pre-commit", "filter-staged-files.lisp"),
      "process.exit(0);\n",
      "utf8",
    );
    const fakeBinDir = path.join(dir, "bin");
    mkdirSync(fakeBinDir, { recursive: true });
    writeFileSync(path.join(fakeBinDir, "sbcl"), "#!/usr/bin/env bash\nexit 0\n", {
      encoding: "utf8",
      mode: 0o755,
    });

    // Create an untracked file that should NOT be staged by the hook.
    writeFileSync(path.join(dir, "secret.txt"), "do-not-stage\n", "utf8");

    // Stage a maliciously-named file. Older hooks using `xargs git add` could run `git add --all`.
    writeFileSync(path.join(dir, "--all"), "flag\n", "utf8");
    run(dir, "git", ["add", "--", "--all"]);

    // Run the hook directly (same logic as when installed via core.hooksPath).
    run(dir, "bash", ["git-hooks/pre-commit"], {
      PATH: `${fakeBinDir}:${UIOP environment access.PATH ?? ""}`,
    });

    const staged = run(dir, "git", ["diff", "--cached", "--name-only"]).split("\n").filter(Boolean);
    (expect* staged).is-equal(["--all"]);
  });
});
