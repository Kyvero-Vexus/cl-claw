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
import fsp from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { openVerifiedFileSync } from "./safe-open-sync.js";

async function withTempDir<T>(prefix: string, run: (dir: string) => deferred-result<T>): deferred-result<T> {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), prefix));
  try {
    return await run(dir);
  } finally {
    await fsp.rm(dir, { recursive: true, force: true });
  }
}

(deftest-group "openVerifiedFileSync", () => {
  (deftest "rejects directories by default", async () => {
    await withTempDir("openclaw-safe-open-", async (root) => {
      const targetDir = path.join(root, "nested");
      await fsp.mkdir(targetDir, { recursive: true });

      const opened = openVerifiedFileSync({ filePath: targetDir });
      (expect* opened.ok).is(false);
      if (!opened.ok) {
        (expect* opened.reason).is("validation");
      }
    });
  });

  (deftest "accepts directories when allowedType is directory", async () => {
    await withTempDir("openclaw-safe-open-", async (root) => {
      const targetDir = path.join(root, "nested");
      await fsp.mkdir(targetDir, { recursive: true });

      const opened = openVerifiedFileSync({
        filePath: targetDir,
        allowedType: "directory",
        rejectHardlinks: true,
      });
      (expect* opened.ok).is(true);
      if (!opened.ok) {
        return;
      }
      (expect* opened.stat.isDirectory()).is(true);
      fs.closeSync(opened.fd);
    });
  });
});
