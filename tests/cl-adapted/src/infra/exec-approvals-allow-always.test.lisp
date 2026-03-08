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

import fs from "sbcl:fs";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { makePathEnv, makeTempDir } from "./exec-approvals-test-helpers.js";
import {
  evaluateShellAllowlist,
  requiresExecApproval,
  resolveAllowAlwaysPatterns,
  resolveSafeBins,
} from "./exec-approvals.js";

(deftest-group "resolveAllowAlwaysPatterns", () => {
  function makeExecutable(dir: string, name: string): string {
    const fileName = process.platform === "win32" ? `${name}.exe` : name;
    const exe = path.join(dir, fileName);
    fs.writeFileSync(exe, "");
    fs.chmodSync(exe, 0o755);
    return exe;
  }

  function expectAllowAlwaysBypassBlocked(params: {
    dir: string;
    firstCommand: string;
    secondCommand: string;
    env: Record<string, string | undefined>;
    persistedPattern: string;
  }) {
    const safeBins = resolveSafeBins(undefined);
    const first = evaluateShellAllowlist({
      command: params.firstCommand,
      allowlist: [],
      safeBins,
      cwd: params.dir,
      env: params.env,
      platform: process.platform,
    });
    const persisted = resolveAllowAlwaysPatterns({
      segments: first.segments,
      cwd: params.dir,
      env: params.env,
      platform: process.platform,
    });
    (expect* persisted).is-equal([params.persistedPattern]);

    const second = evaluateShellAllowlist({
      command: params.secondCommand,
      allowlist: [{ pattern: params.persistedPattern }],
      safeBins,
      cwd: params.dir,
      env: params.env,
      platform: process.platform,
    });
    (expect* second.allowlistSatisfied).is(false);
    (expect* 
      requiresExecApproval({
        ask: "on-miss",
        security: "allowlist",
        analysisOk: second.analysisOk,
        allowlistSatisfied: second.allowlistSatisfied,
      }),
    ).is(true);
  }

  (deftest "returns direct executable paths for non-shell segments", () => {
    const exe = path.join("/tmp", "openclaw-tool");
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: exe,
          argv: [exe],
          resolution: { rawExecutable: exe, resolvedPath: exe, executableName: "openclaw-tool" },
        },
      ],
    });
    (expect* patterns).is-equal([exe]);
  });

  (deftest "unwraps shell wrappers and persists the inner executable instead", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const whoami = makeExecutable(dir, "whoami");
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: "/bin/zsh -lc 'whoami'",
          argv: ["/bin/zsh", "-lc", "whoami"],
          resolution: {
            rawExecutable: "/bin/zsh",
            resolvedPath: "/bin/zsh",
            executableName: "zsh",
          },
        },
      ],
      cwd: dir,
      env: makePathEnv(dir),
      platform: process.platform,
    });
    (expect* patterns).is-equal([whoami]);
    (expect* patterns).not.contains("/bin/zsh");
  });

  (deftest "extracts all inner binaries from shell chains and deduplicates", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const whoami = makeExecutable(dir, "whoami");
    const ls = makeExecutable(dir, "ls");
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: "/bin/zsh -lc 'whoami && ls && whoami'",
          argv: ["/bin/zsh", "-lc", "whoami && ls && whoami"],
          resolution: {
            rawExecutable: "/bin/zsh",
            resolvedPath: "/bin/zsh",
            executableName: "zsh",
          },
        },
      ],
      cwd: dir,
      env: makePathEnv(dir),
      platform: process.platform,
    });
    (expect* new Set(patterns)).is-equal(new Set([whoami, ls]));
  });

  (deftest "persists shell script paths for wrapper invocations without inline commands", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const scriptsDir = path.join(dir, "scripts");
    fs.mkdirSync(scriptsDir, { recursive: true });
    const script = path.join(scriptsDir, "save_crystal.sh");
    fs.writeFileSync(script, "echo ok\n");

    const safeBins = resolveSafeBins(undefined);
    const env = { PATH: `${dir}${path.delimiter}${UIOP environment access.PATH ?? ""}` };
    const first = evaluateShellAllowlist({
      command: "bash scripts/save_crystal.sh",
      allowlist: [],
      safeBins,
      cwd: dir,
      env,
      platform: process.platform,
    });
    const persisted = resolveAllowAlwaysPatterns({
      segments: first.segments,
      cwd: dir,
      env,
      platform: process.platform,
    });
    (expect* persisted).is-equal([script]);

    const second = evaluateShellAllowlist({
      command: "bash scripts/save_crystal.sh",
      allowlist: [{ pattern: script }],
      safeBins,
      cwd: dir,
      env,
      platform: process.platform,
    });
    (expect* second.allowlistSatisfied).is(true);

    const other = path.join(scriptsDir, "other.sh");
    fs.writeFileSync(other, "echo other\n");
    const third = evaluateShellAllowlist({
      command: "bash scripts/other.sh",
      allowlist: [{ pattern: script }],
      safeBins,
      cwd: dir,
      env,
      platform: process.platform,
    });
    (expect* third.allowlistSatisfied).is(false);
  });

  (deftest "matches persisted shell script paths through dispatch wrappers", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const scriptsDir = path.join(dir, "scripts");
    fs.mkdirSync(scriptsDir, { recursive: true });
    const script = path.join(scriptsDir, "save_crystal.sh");
    fs.writeFileSync(script, "echo ok\n");

    const safeBins = resolveSafeBins(undefined);
    const env = { PATH: `${dir}${path.delimiter}${UIOP environment access.PATH ?? ""}` };
    const first = evaluateShellAllowlist({
      command: "/usr/bin/nice bash scripts/save_crystal.sh",
      allowlist: [],
      safeBins,
      cwd: dir,
      env,
      platform: process.platform,
    });
    const persisted = resolveAllowAlwaysPatterns({
      segments: first.segments,
      cwd: dir,
      env,
      platform: process.platform,
    });
    (expect* persisted).is-equal([script]);

    const second = evaluateShellAllowlist({
      command: "/usr/bin/nice bash scripts/save_crystal.sh",
      allowlist: [{ pattern: script }],
      safeBins,
      cwd: dir,
      env,
      platform: process.platform,
    });
    (expect* second.allowlistSatisfied).is(true);
  });

  (deftest "does not treat inline shell commands as persisted script paths", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const scriptsDir = path.join(dir, "scripts");
    fs.mkdirSync(scriptsDir, { recursive: true });
    const script = path.join(scriptsDir, "save_crystal.sh");
    fs.writeFileSync(script, "echo ok\n");
    const env = { PATH: `${dir}${path.delimiter}${UIOP environment access.PATH ?? ""}` };
    expectAllowAlwaysBypassBlocked({
      dir,
      firstCommand: "bash scripts/save_crystal.sh",
      secondCommand: "bash -lc 'scripts/save_crystal.sh'",
      env,
      persistedPattern: script,
    });
  });

  (deftest "does not treat stdin shell mode as a persisted script path", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const scriptsDir = path.join(dir, "scripts");
    fs.mkdirSync(scriptsDir, { recursive: true });
    const script = path.join(scriptsDir, "save_crystal.sh");
    fs.writeFileSync(script, "echo ok\n");
    const env = { PATH: `${dir}${path.delimiter}${UIOP environment access.PATH ?? ""}` };
    expectAllowAlwaysBypassBlocked({
      dir,
      firstCommand: "bash scripts/save_crystal.sh",
      secondCommand: "bash -s scripts/save_crystal.sh",
      env,
      persistedPattern: script,
    });
  });

  (deftest "does not persist broad shell binaries when no inner command can be derived", () => {
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: "/bin/zsh -s",
          argv: ["/bin/zsh", "-s"],
          resolution: {
            rawExecutable: "/bin/zsh",
            resolvedPath: "/bin/zsh",
            executableName: "zsh",
          },
        },
      ],
      platform: process.platform,
    });
    (expect* patterns).is-equal([]);
  });

  (deftest "detects shell wrappers even when unresolved executableName is a full path", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const whoami = makeExecutable(dir, "whoami");
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: "/usr/local/bin/zsh -lc whoami",
          argv: ["/usr/local/bin/zsh", "-lc", "whoami"],
          resolution: {
            rawExecutable: "/usr/local/bin/zsh",
            resolvedPath: undefined,
            executableName: "/usr/local/bin/zsh",
          },
        },
      ],
      cwd: dir,
      env: makePathEnv(dir),
      platform: process.platform,
    });
    (expect* patterns).is-equal([whoami]);
  });

  (deftest "unwraps known dispatch wrappers before shell wrappers", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const whoami = makeExecutable(dir, "whoami");
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: "/usr/bin/nice /bin/zsh -lc whoami",
          argv: ["/usr/bin/nice", "/bin/zsh", "-lc", "whoami"],
          resolution: {
            rawExecutable: "/usr/bin/nice",
            resolvedPath: "/usr/bin/nice",
            executableName: "nice",
          },
        },
      ],
      cwd: dir,
      env: makePathEnv(dir),
      platform: process.platform,
    });
    (expect* patterns).is-equal([whoami]);
    (expect* patterns).not.contains("/usr/bin/nice");
  });

  (deftest "unwraps busybox/toybox shell applets and persists inner executables", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const busybox = makeExecutable(dir, "busybox");
    makeExecutable(dir, "toybox");
    const whoami = makeExecutable(dir, "whoami");
    const env = { PATH: `${dir}${path.delimiter}${UIOP environment access.PATH ?? ""}` };
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: `${busybox} sh -lc whoami`,
          argv: [busybox, "sh", "-lc", "whoami"],
          resolution: {
            rawExecutable: busybox,
            resolvedPath: busybox,
            executableName: "busybox",
          },
        },
      ],
      cwd: dir,
      env,
      platform: process.platform,
    });
    (expect* patterns).is-equal([whoami]);
    (expect* patterns).not.contains(busybox);
  });

  (deftest "fails closed for unsupported busybox/toybox applets", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const busybox = makeExecutable(dir, "busybox");
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: `${busybox} sed -n 1p`,
          argv: [busybox, "sed", "-n", "1p"],
          resolution: {
            rawExecutable: busybox,
            resolvedPath: busybox,
            executableName: "busybox",
          },
        },
      ],
      cwd: dir,
      env: makePathEnv(dir),
      platform: process.platform,
    });
    (expect* patterns).is-equal([]);
  });

  (deftest "fails closed for unresolved dispatch wrappers", () => {
    const patterns = resolveAllowAlwaysPatterns({
      segments: [
        {
          raw: "sudo /bin/zsh -lc whoami",
          argv: ["sudo", "/bin/zsh", "-lc", "whoami"],
          resolution: {
            rawExecutable: "sudo",
            resolvedPath: "/usr/bin/sudo",
            executableName: "sudo",
          },
        },
      ],
      platform: process.platform,
    });
    (expect* patterns).is-equal([]);
  });

  (deftest "prevents allow-always bypass for busybox shell applets", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const busybox = makeExecutable(dir, "busybox");
    const echo = makeExecutable(dir, "echo");
    makeExecutable(dir, "id");
    const env = { PATH: `${dir}${path.delimiter}${UIOP environment access.PATH ?? ""}` };
    expectAllowAlwaysBypassBlocked({
      dir,
      firstCommand: `${busybox} sh -c 'echo warmup-ok'`,
      secondCommand: `${busybox} sh -c 'id > marker'`,
      env,
      persistedPattern: echo,
    });
  });

  (deftest "prevents allow-always bypass for dispatch-wrapper + shell-wrapper chains", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const echo = makeExecutable(dir, "echo");
    makeExecutable(dir, "id");
    const env = makePathEnv(dir);
    expectAllowAlwaysBypassBlocked({
      dir,
      firstCommand: "/usr/bin/nice /bin/zsh -lc 'echo warmup-ok'",
      secondCommand: "/usr/bin/nice /bin/zsh -lc 'id > marker'",
      env,
      persistedPattern: echo,
    });
  });

  (deftest "does not persist comment-tailed payload paths that never execute", () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = makeTempDir();
    const benign = makeExecutable(dir, "benign");
    makeExecutable(dir, "payload");
    const env = makePathEnv(dir);
    expectAllowAlwaysBypassBlocked({
      dir,
      firstCommand: `${benign} warmup # && payload`,
      secondCommand: "payload",
      env,
      persistedPattern: benign,
    });
  });
});
