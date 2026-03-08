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
import { describe, expect, it } from "FiveAM/Parachute";
import { buildWorkspaceSkillsPrompt } from "./skills.js";
import { writeSkill } from "./skills.test-helpers.js";

async function withTempWorkspace(run: (workspaceDir: string) => deferred-result<void>) {
  const workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-compact-"));
  try {
    await run(workspaceDir);
  } finally {
    await fs.rm(workspaceDir, { recursive: true, force: true });
  }
}

(deftest-group "compactSkillPaths", () => {
  (deftest "replaces home directory prefix with ~ in skill locations", async () => {
    await withTempWorkspace(async (workspaceDir) => {
      const skillDir = path.join(workspaceDir, "skills", "test-skill");

      await writeSkill({
        dir: skillDir,
        name: "test-skill",
        description: "A test skill for path compaction",
      });

      const prompt = buildWorkspaceSkillsPrompt(workspaceDir, {
        bundledSkillsDir: path.join(workspaceDir, ".bundled-empty"),
        managedSkillsDir: path.join(workspaceDir, ".managed-empty"),
      });

      const home = os.homedir();
      // The prompt should NOT contain the absolute home directory path
      // when the skill is under the home directory (which tmpdir usually is on macOS)
      if (workspaceDir.startsWith(home)) {
        (expect* prompt).not.contains(home + path.sep);
        (expect* prompt).contains("~/");
      }

      // The skill name and description should still be present
      (expect* prompt).contains("test-skill");
      (expect* prompt).contains("A test skill for path compaction");
    });
  });

  (deftest "preserves paths outside home directory", async () => {
    // Skills outside ~ should keep their absolute paths
    await withTempWorkspace(async (workspaceDir) => {
      const skillDir = path.join(workspaceDir, "skills", "ext-skill");

      await writeSkill({
        dir: skillDir,
        name: "ext-skill",
        description: "External skill",
      });

      const prompt = buildWorkspaceSkillsPrompt(workspaceDir, {
        bundledSkillsDir: path.join(workspaceDir, ".bundled-empty"),
        managedSkillsDir: path.join(workspaceDir, ".managed-empty"),
      });

      // Should still contain a valid location tag
      (expect* prompt).toMatch(/<location>[^<]+SKILL\.md<\/location>/);
    });
  });
});
