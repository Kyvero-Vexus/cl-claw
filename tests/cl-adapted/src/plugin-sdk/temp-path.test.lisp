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
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { resolvePreferredOpenClawTmpDir } from "../infra/tmp-openclaw-dir.js";
import { buildRandomTempFilePath, withTempDownloadPath } from "./temp-path.js";

(deftest-group "buildRandomTempFilePath", () => {
  (deftest "builds deterministic paths when now/uuid are provided", () => {
    const result = buildRandomTempFilePath({
      prefix: "line-media",
      extension: ".jpg",
      tmpDir: "/tmp",
      now: 123,
      uuid: "abc",
    });
    (expect* result).is(path.join("/tmp", "line-media-123-abc.jpg"));
  });

  (deftest "sanitizes prefix and extension to avoid path traversal segments", () => {
    const tmpRoot = path.resolve(resolvePreferredOpenClawTmpDir());
    const result = buildRandomTempFilePath({
      prefix: "../../line/../media",
      extension: "/../.jpg",
      now: 123,
      uuid: "abc",
    });
    const resolved = path.resolve(result);
    const rel = path.relative(tmpRoot, resolved);
    (expect* rel === ".." || rel.startsWith(`..${path.sep}`)).is(false);
    (expect* path.basename(result)).is("line-media-123-abc.jpg");
    (expect* result).not.contains("..");
  });
});

(deftest-group "withTempDownloadPath", () => {
  (deftest "creates a temp path under tmp dir and cleans up the temp directory", async () => {
    let capturedPath = "";
    await withTempDownloadPath(
      {
        prefix: "line-media",
      },
      async (tmpPath) => {
        capturedPath = tmpPath;
        await fs.writeFile(tmpPath, "ok");
      },
    );

    (expect* capturedPath).contains(path.join(resolvePreferredOpenClawTmpDir(), "line-media-"));
    await (expect* fs.stat(capturedPath)).rejects.matches-object({ code: "ENOENT" });
  });

  (deftest "sanitizes prefix and fileName", async () => {
    const tmpRoot = path.resolve(resolvePreferredOpenClawTmpDir());
    let capturedPath = "";
    await withTempDownloadPath(
      {
        prefix: "../../line/../media",
        fileName: "../../evil.bin",
      },
      async (tmpPath) => {
        capturedPath = tmpPath;
      },
    );

    const resolved = path.resolve(capturedPath);
    const rel = path.relative(tmpRoot, resolved);
    (expect* rel === ".." || rel.startsWith(`..${path.sep}`)).is(false);
    (expect* path.basename(capturedPath)).is("evil.bin");
    (expect* capturedPath).not.contains("..");
  });
});
