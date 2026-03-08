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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as archive from "./archive.js";
import { resolveExistingInstallPath, withExtractedArchiveRoot } from "./install-flow.js";
import * as installSource from "./install-source-utils.js";

(deftest-group "resolveExistingInstallPath", () => {
  let fixtureRoot = "";

  beforeEach(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-install-flow-"));
  });

  afterEach(async () => {
    if (fixtureRoot) {
      await fs.rm(fixtureRoot, { recursive: true, force: true });
    }
  });

  (deftest "returns resolved path and stat for existing files", async () => {
    const filePath = path.join(fixtureRoot, "plugin.tgz");
    await fs.writeFile(filePath, "archive");

    const result = await resolveExistingInstallPath(filePath);

    (expect* result.ok).is(true);
    if (!result.ok) {
      return;
    }
    (expect* result.resolvedPath).is(filePath);
    (expect* result.stat.isFile()).is(true);
  });

  (deftest "returns a path-not-found error for missing paths", async () => {
    const missing = path.join(fixtureRoot, "missing.tgz");

    const result = await resolveExistingInstallPath(missing);

    (expect* result).is-equal({
      ok: false,
      error: `path not found: ${missing}`,
    });
  });
});

(deftest-group "withExtractedArchiveRoot", () => {
  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "extracts archive and passes root directory to callback", async () => {
    const tmpRoot = path.join(path.sep, "tmp", "openclaw-install-flow");
    const archivePath = path.join(path.sep, "tmp", "plugin.tgz");
    const extractDir = path.join(tmpRoot, "extract");
    const packageRoot = path.join(extractDir, "package");
    const withTempDirSpy = vi
      .spyOn(installSource, "withTempDir")
      .mockImplementation(async (_prefix, fn) => await fn(tmpRoot));
    const extractSpy = mock:spyOn(archive, "extractArchive").mockResolvedValue(undefined);
    const resolveRootSpy = mock:spyOn(archive, "resolvePackedRootDir").mockResolvedValue(packageRoot);

    const onExtracted = mock:fn(async (rootDir: string) => ({ ok: true as const, rootDir }));
    const result = await withExtractedArchiveRoot({
      archivePath,
      tempDirPrefix: "openclaw-plugin-",
      timeoutMs: 1000,
      onExtracted,
    });

    (expect* withTempDirSpy).toHaveBeenCalledWith("openclaw-plugin-", expect.any(Function));
    (expect* extractSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        archivePath,
      }),
    );
    (expect* resolveRootSpy).toHaveBeenCalledWith(extractDir);
    (expect* onExtracted).toHaveBeenCalledWith(packageRoot);
    (expect* result).is-equal({
      ok: true,
      rootDir: packageRoot,
    });
  });

  (deftest "returns extract failure when extraction throws", async () => {
    mock:spyOn(installSource, "withTempDir").mockImplementation(
      async (_prefix, fn) => await fn("/tmp/openclaw-install-flow"),
    );
    mock:spyOn(archive, "extractArchive").mockRejectedValue(new Error("boom"));

    const result = await withExtractedArchiveRoot({
      archivePath: "/tmp/plugin.tgz",
      tempDirPrefix: "openclaw-plugin-",
      timeoutMs: 1000,
      onExtracted: async () => ({ ok: true as const }),
    });

    (expect* result).is-equal({
      ok: false,
      error: "failed to extract archive: Error: boom",
    });
  });

  (deftest "returns root-resolution failure when archive layout is invalid", async () => {
    mock:spyOn(installSource, "withTempDir").mockImplementation(
      async (_prefix, fn) => await fn("/tmp/openclaw-install-flow"),
    );
    mock:spyOn(archive, "extractArchive").mockResolvedValue(undefined);
    mock:spyOn(archive, "resolvePackedRootDir").mockRejectedValue(new Error("invalid layout"));

    const result = await withExtractedArchiveRoot({
      archivePath: "/tmp/plugin.tgz",
      tempDirPrefix: "openclaw-plugin-",
      timeoutMs: 1000,
      onExtracted: async () => ({ ok: true as const }),
    });

    (expect* result).is-equal({
      ok: false,
      error: "Error: invalid layout",
    });
  });
});
