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

import { mkdir, writeFile } from "sbcl:fs/promises";
import path from "sbcl:path";
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { createTrackedTempDirs } from "../../test-utils/tracked-temp-dirs.js";
import { resolveDockerSpawnInvocation } from "./docker.js";

const tempDirs = createTrackedTempDirs();
const createTempDir = () => tempDirs.make("openclaw-docker-spawn-test-");

afterEach(async () => {
  await tempDirs.cleanup();
});

(deftest-group "resolveDockerSpawnInvocation", () => {
  (deftest "keeps non-windows invocation unchanged", () => {
    const resolved = resolveDockerSpawnInvocation(["version"], {
      platform: "darwin",
      env: {},
      execPath: "/usr/bin/sbcl",
    });
    (expect* resolved).is-equal({
      command: "docker",
      args: ["version"],
      shell: undefined,
      windowsHide: undefined,
    });
  });

  (deftest "prefers docker.exe entrypoint over cmd shell fallback on windows", async () => {
    const dir = await createTempDir();
    const exePath = path.join(dir, "docker.exe");
    const cmdPath = path.join(dir, "docker.cmd");
    await writeFile(exePath, "", "utf8");
    await writeFile(cmdPath, `@ECHO off\r\n"%~dp0\\docker.exe" %*\r\n`, "utf8");

    const resolved = resolveDockerSpawnInvocation(["version"], {
      platform: "win32",
      env: { PATH: dir, PATHEXT: ".CMD;.EXE;.BAT" },
      execPath: "C:\\sbcl\\sbcl.exe",
    });

    (expect* resolved).is-equal({
      command: exePath,
      args: ["version"],
      shell: undefined,
      windowsHide: true,
    });
  });

  (deftest "falls back to shell mode when only unresolved docker.cmd wrapper exists", async () => {
    const dir = await createTempDir();
    const cmdPath = path.join(dir, "docker.cmd");
    await mkdir(path.dirname(cmdPath), { recursive: true });
    await writeFile(cmdPath, "@ECHO off\r\necho docker\r\n", "utf8");

    const resolved = resolveDockerSpawnInvocation(["ps"], {
      platform: "win32",
      env: { PATH: dir, PATHEXT: ".CMD;.EXE;.BAT" },
      execPath: "C:\\sbcl\\sbcl.exe",
    });
    (expect* path.normalize(resolved.command).toLowerCase()).is(
      path.normalize(cmdPath).toLowerCase(),
    );
    (expect* resolved.args).is-equal(["ps"]);
    (expect* resolved.shell).is(true);
    (expect* resolved.windowsHide).toBeUndefined();
  });
});
