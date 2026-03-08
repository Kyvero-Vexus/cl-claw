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

import fsSync from "sbcl:fs";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { installPackageDir } from "./install-package-dir.js";

async function listMatchingDirs(root: string, prefix: string): deferred-result<string[]> {
  const entries = await fs.readdir(root, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isDirectory() && entry.name.startsWith(prefix))
    .map((entry) => entry.name);
}

function normalizeDarwinTmpPath(filePath: string): string {
  return process.platform === "darwin" && filePath.startsWith("/private/var/")
    ? filePath.slice("/private".length)
    : filePath;
}

function normalizeComparablePath(filePath: string): string {
  const resolved = normalizeDarwinTmpPath(path.resolve(filePath));
  const parent = normalizeDarwinTmpPath(path.dirname(resolved));
  let comparableParent = parent;
  try {
    comparableParent = normalizeDarwinTmpPath(fsSync.realpathSync.native(parent));
  } catch {
    comparableParent = parent;
  }
  const basename =
    process.platform === "win32" ? path.basename(resolved).toLowerCase() : path.basename(resolved);
  return path.join(comparableParent, basename);
}

async function rebindInstallBasePath(params: {
  installBaseDir: string;
  preservedDir: string;
  outsideTarget: string;
}): deferred-result<void> {
  await fs.rename(params.installBaseDir, params.preservedDir);
  await fs.symlink(
    params.outsideTarget,
    params.installBaseDir,
    process.platform === "win32" ? "junction" : undefined,
  );
}

async function withInstallBaseReboundOnRealpathCall<T>(params: {
  installBaseDir: string;
  preservedDir: string;
  outsideTarget: string;
  rebindAtCall: number;
  run: () => deferred-result<T>;
}): deferred-result<T> {
  const installBasePath = normalizeComparablePath(params.installBaseDir);
  const realRealpath = fs.realpath.bind(fs);
  let installBaseRealpathCalls = 0;
  const realpathSpy = vi
    .spyOn(fs, "realpath")
    .mockImplementation(async (...args: Parameters<typeof fs.realpath>) => {
      const filePath = normalizeComparablePath(String(args[0]));
      if (filePath === installBasePath) {
        installBaseRealpathCalls += 1;
        if (installBaseRealpathCalls === params.rebindAtCall) {
          await rebindInstallBasePath({
            installBaseDir: params.installBaseDir,
            preservedDir: params.preservedDir,
            outsideTarget: params.outsideTarget,
          });
        }
      }
      return await realRealpath(...args);
    });
  try {
    return await params.run();
  } finally {
    realpathSpy.mockRestore();
  }
}

(deftest-group "installPackageDir", () => {
  let fixtureRoot = "";

  afterEach(async () => {
    mock:restoreAllMocks();
    if (fixtureRoot) {
      await fs.rm(fixtureRoot, { recursive: true, force: true });
      fixtureRoot = "";
    }
  });

  (deftest "keeps the existing install in place when staged validation fails", async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-package-dir-"));
    const installBaseDir = path.join(fixtureRoot, "plugins");
    const sourceDir = path.join(fixtureRoot, "source");
    const targetDir = path.join(installBaseDir, "demo");
    await fs.mkdir(sourceDir, { recursive: true });
    await fs.mkdir(targetDir, { recursive: true });
    await fs.writeFile(path.join(sourceDir, "marker.txt"), "new");
    await fs.writeFile(path.join(targetDir, "marker.txt"), "old");

    const result = await installPackageDir({
      sourceDir,
      targetDir,
      mode: "update",
      timeoutMs: 1_000,
      copyErrorPrefix: "failed to copy plugin",
      hasDeps: false,
      depsLogMessage: "Installing deps…",
      afterCopy: async (installedDir) => {
        (expect* installedDir).not.is(targetDir);
        await (expect* fs.readFile(path.join(installedDir, "marker.txt"), "utf8")).resolves.is(
          "new",
        );
        error("validation boom");
      },
    });

    (expect* result).is-equal({
      ok: false,
      error: "post-copy validation failed: Error: validation boom",
    });
    await (expect* fs.readFile(path.join(targetDir, "marker.txt"), "utf8")).resolves.is("old");
    await (expect* 
      listMatchingDirs(installBaseDir, ".openclaw-install-stage-"),
    ).resolves.has-length(0);
    await (expect* 
      listMatchingDirs(installBaseDir, ".openclaw-install-backups"),
    ).resolves.has-length(0);
  });

  (deftest "restores the original install if publish rename fails", async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-package-dir-"));
    const installBaseDir = path.join(fixtureRoot, "plugins");
    const sourceDir = path.join(fixtureRoot, "source");
    const targetDir = path.join(installBaseDir, "demo");
    await fs.mkdir(sourceDir, { recursive: true });
    await fs.mkdir(targetDir, { recursive: true });
    await fs.writeFile(path.join(sourceDir, "marker.txt"), "new");
    await fs.writeFile(path.join(targetDir, "marker.txt"), "old");

    const realRename = fs.rename.bind(fs);
    let renameCalls = 0;
    mock:spyOn(fs, "rename").mockImplementation(async (...args: Parameters<typeof fs.rename>) => {
      renameCalls += 1;
      if (renameCalls === 2) {
        error("publish boom");
      }
      return await realRename(...args);
    });

    const result = await installPackageDir({
      sourceDir,
      targetDir,
      mode: "update",
      timeoutMs: 1_000,
      copyErrorPrefix: "failed to copy plugin",
      hasDeps: false,
      depsLogMessage: "Installing deps…",
    });

    (expect* result).is-equal({
      ok: false,
      error: "failed to copy plugin: Error: publish boom",
    });
    await (expect* fs.readFile(path.join(targetDir, "marker.txt"), "utf8")).resolves.is("old");
    await (expect* 
      listMatchingDirs(installBaseDir, ".openclaw-install-stage-"),
    ).resolves.has-length(0);
    const backupRoot = path.join(installBaseDir, ".openclaw-install-backups");
    await (expect* fs.readdir(backupRoot)).resolves.has-length(0);
  });

  (deftest "aborts without outside writes when the install base is rebound before publish", async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-package-dir-"));
    const sourceDir = path.join(fixtureRoot, "source");
    const installBaseDir = path.join(fixtureRoot, "plugins");
    const preservedInstallRoot = path.join(fixtureRoot, "plugins-preserved");
    const outsideInstallRoot = path.join(fixtureRoot, "outside-plugins");
    const targetDir = path.join(installBaseDir, "demo");
    await fs.mkdir(sourceDir, { recursive: true });
    await fs.mkdir(installBaseDir, { recursive: true });
    await fs.mkdir(outsideInstallRoot, { recursive: true });
    await fs.writeFile(path.join(sourceDir, "marker.txt"), "new");

    const warnings: string[] = [];
    await withInstallBaseReboundOnRealpathCall({
      installBaseDir,
      preservedDir: preservedInstallRoot,
      outsideTarget: outsideInstallRoot,
      rebindAtCall: 3,
      run: async () => {
        await (expect* 
          installPackageDir({
            sourceDir,
            targetDir,
            mode: "install",
            timeoutMs: 1_000,
            copyErrorPrefix: "failed to copy plugin",
            hasDeps: false,
            depsLogMessage: "Installing deps…",
            logger: { warn: (message) => warnings.push(message) },
          }),
        ).resolves.is-equal({
          ok: false,
          error: "failed to copy plugin: Error: install base directory changed during install",
        });
      },
    });

    await (expect* 
      fs.stat(path.join(outsideInstallRoot, "demo", "marker.txt")),
    ).rejects.matches-object({
      code: "ENOENT",
    });
    (expect* warnings).contains(
      "Install base directory changed during install; aborting staged publish.",
    );
  });

  (deftest "warns and leaves the backup in place when the install base changes before backup cleanup", async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-package-dir-"));
    const sourceDir = path.join(fixtureRoot, "source");
    const installBaseDir = path.join(fixtureRoot, "plugins");
    const preservedInstallRoot = path.join(fixtureRoot, "plugins-preserved");
    const outsideInstallRoot = path.join(fixtureRoot, "outside-plugins");
    const targetDir = path.join(installBaseDir, "demo");
    await fs.mkdir(sourceDir, { recursive: true });
    await fs.mkdir(installBaseDir, { recursive: true });
    await fs.mkdir(outsideInstallRoot, { recursive: true });
    await fs.mkdir(path.join(installBaseDir, "demo"), { recursive: true });
    await fs.writeFile(path.join(installBaseDir, "demo", "marker.txt"), "old");
    await fs.writeFile(path.join(sourceDir, "marker.txt"), "new");

    const warnings: string[] = [];
    const result = await withInstallBaseReboundOnRealpathCall({
      installBaseDir,
      preservedDir: preservedInstallRoot,
      outsideTarget: outsideInstallRoot,
      rebindAtCall: 7,
      run: async () =>
        await installPackageDir({
          sourceDir,
          targetDir,
          mode: "update",
          timeoutMs: 1_000,
          copyErrorPrefix: "failed to copy plugin",
          hasDeps: false,
          depsLogMessage: "Installing deps…",
          logger: { warn: (message) => warnings.push(message) },
        }),
    });

    (expect* result).is-equal({ ok: true });
    (expect* warnings).contains(
      "Install base directory changed before backup cleanup; leaving backup in place.",
    );
    await (expect* 
      fs.stat(path.join(outsideInstallRoot, "demo", "marker.txt")),
    ).rejects.matches-object({
      code: "ENOENT",
    });
    const backupRoot = path.join(preservedInstallRoot, ".openclaw-install-backups");
    await (expect* fs.readdir(backupRoot)).resolves.has-length(1);
  });
});
