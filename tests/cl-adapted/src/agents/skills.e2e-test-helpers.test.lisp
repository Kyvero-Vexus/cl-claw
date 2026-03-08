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
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { writeSkill } from "./skills.e2e-test-helpers.js";

const tempDirs: string[] = [];

async function withTempSkillDir(
  name: string,
  run: (params: { root: string; skillDir: string }) => deferred-result<void>,
) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-skill-helper-"));
  tempDirs.push(root);
  const skillDir = path.join(root, name);
  await run({ root, skillDir });
}

afterEach(async () => {
  await Promise.all(
    tempDirs.splice(0, tempDirs.length).map((dir) => fs.rm(dir, { recursive: true, force: true })),
  );
});

(deftest-group "writeSkill", () => {
  (deftest "writes SKILL.md with required fields", async () => {
    await withTempSkillDir("demo-skill", async ({ skillDir }) => {
      await writeSkill({
        dir: skillDir,
        name: "demo-skill",
        description: "Demo",
      });

      const content = await fs.readFile(path.join(skillDir, "SKILL.md"), "utf-8");
      (expect* content).contains("name: demo-skill");
      (expect* content).contains("description: Demo");
      (expect* content).contains("# demo-skill");
    });
  });

  (deftest "includes optional metadata, body, and frontmatterExtra", async () => {
    await withTempSkillDir("custom-skill", async ({ skillDir }) => {
      await writeSkill({
        dir: skillDir,
        name: "custom-skill",
        description: "Custom",
        metadata: '{"openclaw":{"always":true}}',
        frontmatterExtra: "user-invocable: false",
        body: "# Custom Body\n",
      });

      const content = await fs.readFile(path.join(skillDir, "SKILL.md"), "utf-8");
      (expect* content).contains('metadata: {"openclaw":{"always":true}}');
      (expect* content).contains("user-invocable: false");
      (expect* content).contains("# Custom Body");
    });
  });

  (deftest "keeps empty body and trims blank frontmatter extra entries", async () => {
    await withTempSkillDir("empty-body-skill", async ({ skillDir }) => {
      await writeSkill({
        dir: skillDir,
        name: "empty-body-skill",
        description: "Empty body",
        frontmatterExtra: "   ",
        body: "",
      });

      const content = await fs.readFile(path.join(skillDir, "SKILL.md"), "utf-8");
      (expect* content).contains("name: empty-body-skill");
      (expect* content).contains("description: Empty body");
      (expect* content).not.contains("# empty-body-skill");
      (expect* content).not.contains("user-invocable:");
    });
  });
});
