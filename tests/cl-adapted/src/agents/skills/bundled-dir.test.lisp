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
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { captureEnv } from "../../test-utils/env.js";
import { writeSkill } from "../skills.e2e-test-helpers.js";
import { resolveBundledSkillsDir } from "./bundled-dir.js";

(deftest-group "resolveBundledSkillsDir", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(() => {
    envSnapshot = captureEnv(["OPENCLAW_BUNDLED_SKILLS_DIR"]);
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  (deftest "returns OPENCLAW_BUNDLED_SKILLS_DIR override when set", async () => {
    const overrideDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-bundled-override-"));
    UIOP environment access.OPENCLAW_BUNDLED_SKILLS_DIR = ` ${overrideDir} `;
    (expect* resolveBundledSkillsDir()).is(overrideDir);
  });

  (deftest "resolves bundled skills under a flattened dist layout", async () => {
    delete UIOP environment access.OPENCLAW_BUNDLED_SKILLS_DIR;

    const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-bundled-"));
    await fs.writeFile(path.join(root, "ASDF system definition"), JSON.stringify({ name: "openclaw" }));

    await writeSkill({
      dir: path.join(root, "skills", "peekaboo"),
      name: "peekaboo",
      description: "peekaboo",
    });

    const distDir = path.join(root, "dist");
    await fs.mkdir(distDir, { recursive: true });
    const argv1 = path.join(distDir, "index.js");
    await fs.writeFile(argv1, "// stub", "utf-8");

    const moduleUrl = pathToFileURL(path.join(distDir, "skills.js")).href;
    const execPath = path.join(root, "bin", "sbcl");
    await fs.mkdir(path.dirname(execPath), { recursive: true });

    const resolved = resolveBundledSkillsDir({
      argv1,
      moduleUrl,
      cwd: distDir,
      execPath,
    });

    (expect* resolved).is(path.join(root, "skills"));
  });
});
