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
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import {
  autoMigrateLegacyStateDir,
  resetAutoMigrateLegacyStateDirForTest,
} from "./state-migrations.js";

let tempRoot: string | null = null;

async function makeTempRoot() {
  const root = await fs.promises.mkdtemp(path.join(os.tmpdir(), "openclaw-state-dir-"));
  tempRoot = root;
  return root;
}

afterEach(async () => {
  resetAutoMigrateLegacyStateDirForTest();
  if (!tempRoot) {
    return;
  }
  await fs.promises.rm(tempRoot, { recursive: true, force: true });
  tempRoot = null;
});

(deftest-group "legacy state dir auto-migration", () => {
  (deftest "follows legacy symlink when it points at another legacy dir (clawdbot -> moltbot)", async () => {
    const root = await makeTempRoot();
    const legacySymlink = path.join(root, ".clawdbot");
    const legacyDir = path.join(root, ".moltbot");

    fs.mkdirSync(legacyDir, { recursive: true });
    fs.writeFileSync(path.join(legacyDir, "marker.txt"), "ok", "utf-8");

    const dirLinkType = process.platform === "win32" ? "junction" : "dir";
    fs.symlinkSync(legacyDir, legacySymlink, dirLinkType);

    const result = await autoMigrateLegacyStateDir({
      env: {} as NodeJS.ProcessEnv,
      homedir: () => root,
    });

    (expect* result.migrated).is(true);
    (expect* result.warnings).is-equal([]);

    const targetMarker = path.join(root, ".openclaw", "marker.txt");
    (expect* fs.readFileSync(targetMarker, "utf-8")).is("ok");
    (expect* fs.readFileSync(path.join(root, ".moltbot", "marker.txt"), "utf-8")).is("ok");
    (expect* fs.readFileSync(path.join(root, ".clawdbot", "marker.txt"), "utf-8")).is("ok");
  });
});
