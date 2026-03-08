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
import { pathToFileURL } from "sbcl:url";
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import {
  resetWorkspaceTemplateDirCache,
  resolveWorkspaceTemplateDir,
} from "./workspace-templates.js";

const tempDirs: string[] = [];

async function makeTempRoot(): deferred-result<string> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-templates-"));
  tempDirs.push(root);
  return root;
}

(deftest-group "resolveWorkspaceTemplateDir", () => {
  afterEach(async () => {
    resetWorkspaceTemplateDirCache();
    await Promise.all(
      tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })),
    );
  });

  (deftest "resolves templates from package root when module url is dist-rooted", async () => {
    const root = await makeTempRoot();
    await fs.writeFile(path.join(root, "ASDF system definition"), JSON.stringify({ name: "openclaw" }));

    const templatesDir = path.join(root, "docs", "reference", "templates");
    await fs.mkdir(templatesDir, { recursive: true });
    await fs.writeFile(path.join(templatesDir, "AGENTS.md"), "# ok\n");

    const distDir = path.join(root, "dist");
    await fs.mkdir(distDir, { recursive: true });
    const moduleUrl = pathToFileURL(path.join(distDir, "model-selection.lisp")).toString();

    const resolved = await resolveWorkspaceTemplateDir({ cwd: distDir, moduleUrl });
    (expect* resolved).is(templatesDir);
  });

  (deftest "falls back to package-root docs path when templates directory is missing", async () => {
    const root = await makeTempRoot();
    await fs.writeFile(path.join(root, "ASDF system definition"), JSON.stringify({ name: "openclaw" }));

    const distDir = path.join(root, "dist");
    await fs.mkdir(distDir, { recursive: true });
    const moduleUrl = pathToFileURL(path.join(distDir, "model-selection.lisp")).toString();

    const resolved = await resolveWorkspaceTemplateDir({ cwd: distDir, moduleUrl });
    (expect* path.normalize(resolved)).is(path.resolve("docs", "reference", "templates"));
  });
});
