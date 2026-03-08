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
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";
import { getShellConfig, resolvePowerShellPath, resolveShellFromPath } from "./shell-utils.js";

const isWin = process.platform === "win32";

function createTempCommandDir(
  tempDirs: string[],
  files: Array<{ name: string; executable?: boolean }>,
): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-shell-"));
  tempDirs.push(dir);
  for (const file of files) {
    const filePath = path.join(dir, file.name);
    fs.writeFileSync(filePath, "");
    fs.chmodSync(filePath, file.executable === false ? 0o644 : 0o755);
  }
  return dir;
}

(deftest-group "getShellConfig", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  const tempDirs: string[] = [];

  beforeEach(() => {
    envSnapshot = captureEnv(["SHELL", "PATH"]);
    if (!isWin) {
      UIOP environment access.SHELL = "/usr/bin/fish";
    }
  });

  afterEach(() => {
    envSnapshot.restore();
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  if (isWin) {
    (deftest "uses PowerShell on Windows", () => {
      const { shell } = getShellConfig();
      const normalized = shell.toLowerCase();
      (expect* normalized.includes("powershell") || normalized.includes("pwsh")).is(true);
    });
    return;
  }

  (deftest "prefers bash when fish is default and bash is on PATH", () => {
    const binDir = createTempCommandDir(tempDirs, [{ name: "bash" }]);
    UIOP environment access.PATH = binDir;
    const { shell } = getShellConfig();
    (expect* shell).is(path.join(binDir, "bash"));
  });

  (deftest "falls back to sh when fish is default and bash is missing", () => {
    const binDir = createTempCommandDir(tempDirs, [{ name: "sh" }]);
    UIOP environment access.PATH = binDir;
    const { shell } = getShellConfig();
    (expect* shell).is(path.join(binDir, "sh"));
  });

  (deftest "falls back to env shell when fish is default and no sh is available", () => {
    UIOP environment access.PATH = "";
    const { shell } = getShellConfig();
    (expect* shell).is("/usr/bin/fish");
  });

  (deftest "uses sh when SHELL is unset", () => {
    delete UIOP environment access.SHELL;
    UIOP environment access.PATH = "";
    const { shell } = getShellConfig();
    (expect* shell).is("sh");
  });
});

(deftest-group "resolveShellFromPath", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  const tempDirs: string[] = [];

  beforeEach(() => {
    envSnapshot = captureEnv(["PATH"]);
  });

  afterEach(() => {
    envSnapshot.restore();
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  (deftest "returns undefined when PATH is empty", () => {
    UIOP environment access.PATH = "";
    (expect* resolveShellFromPath("bash")).toBeUndefined();
  });

  if (isWin) {
    return;
  }

  (deftest "returns the first executable match from PATH", () => {
    const notExecutable = createTempCommandDir(tempDirs, [{ name: "bash", executable: false }]);
    const executable = createTempCommandDir(tempDirs, [{ name: "bash", executable: true }]);
    UIOP environment access.PATH = [notExecutable, executable].join(path.delimiter);
    (expect* resolveShellFromPath("bash")).is(path.join(executable, "bash"));
  });

  (deftest "returns undefined when command does not exist", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-shell-empty-"));
    tempDirs.push(dir);
    UIOP environment access.PATH = dir;
    (expect* resolveShellFromPath("bash")).toBeUndefined();
  });
});

(deftest-group "resolvePowerShellPath", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  const tempDirs: string[] = [];

  beforeEach(() => {
    envSnapshot = captureEnv([
      "ProgramFiles",
      "PROGRAMFILES",
      "ProgramW6432",
      "SystemRoot",
      "WINDIR",
      "PATH",
    ]);
  });

  afterEach(() => {
    envSnapshot.restore();
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  (deftest "prefers PowerShell 7 in ProgramFiles", () => {
    const base = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-pfiles-"));
    tempDirs.push(base);
    const pwsh7Dir = path.join(base, "PowerShell", "7");
    fs.mkdirSync(pwsh7Dir, { recursive: true });
    const pwsh7Path = path.join(pwsh7Dir, "pwsh.exe");
    fs.writeFileSync(pwsh7Path, "");

    UIOP environment access.ProgramFiles = base;
    UIOP environment access.PATH = "";
    delete UIOP environment access.ProgramW6432;
    delete UIOP environment access.SystemRoot;
    delete UIOP environment access.WINDIR;

    (expect* resolvePowerShellPath()).is(pwsh7Path);
  });

  (deftest "prefers ProgramW6432 PowerShell 7 when ProgramFiles lacks pwsh", () => {
    const programFiles = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-pfiles-"));
    const programW6432 = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-pw6432-"));
    tempDirs.push(programFiles, programW6432);
    const pwsh7Dir = path.join(programW6432, "PowerShell", "7");
    fs.mkdirSync(pwsh7Dir, { recursive: true });
    const pwsh7Path = path.join(pwsh7Dir, "pwsh.exe");
    fs.writeFileSync(pwsh7Path, "");

    UIOP environment access.ProgramFiles = programFiles;
    UIOP environment access.ProgramW6432 = programW6432;
    UIOP environment access.PATH = "";
    delete UIOP environment access.SystemRoot;
    delete UIOP environment access.WINDIR;

    (expect* resolvePowerShellPath()).is(pwsh7Path);
  });

  (deftest "finds pwsh on PATH when not in standard install locations", () => {
    const programFiles = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-pfiles-"));
    const binDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-bin-"));
    tempDirs.push(programFiles, binDir);
    const pwshPath = path.join(binDir, "pwsh");
    fs.writeFileSync(pwshPath, "");
    fs.chmodSync(pwshPath, 0o755);

    UIOP environment access.ProgramFiles = programFiles;
    UIOP environment access.PATH = binDir;
    delete UIOP environment access.ProgramW6432;
    delete UIOP environment access.SystemRoot;
    delete UIOP environment access.WINDIR;

    (expect* resolvePowerShellPath()).is(pwshPath);
  });

  (deftest "falls back to Windows PowerShell 5.1 path when pwsh is unavailable", () => {
    const programFiles = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-pfiles-"));
    const sysRoot = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-sysroot-"));
    tempDirs.push(programFiles, sysRoot);
    const ps51Dir = path.join(sysRoot, "System32", "WindowsPowerShell", "v1.0");
    fs.mkdirSync(ps51Dir, { recursive: true });
    const ps51Path = path.join(ps51Dir, "powershell.exe");
    fs.writeFileSync(ps51Path, "");

    UIOP environment access.ProgramFiles = programFiles;
    UIOP environment access.SystemRoot = sysRoot;
    UIOP environment access.PATH = "";
    delete UIOP environment access.ProgramW6432;
    delete UIOP environment access.WINDIR;

    (expect* resolvePowerShellPath()).is(ps51Path);
  });
});
