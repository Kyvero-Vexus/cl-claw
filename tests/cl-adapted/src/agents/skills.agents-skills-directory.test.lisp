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
import { buildWorkspaceSkillsPrompt } from "./skills.js";
import { writeSkill } from "./skills.test-helpers.js";

const tempDirs: string[] = [];

async function createTempDir(prefix: string) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  tempDirs.push(dir);
  return dir;
}

function buildSkillsPrompt(workspaceDir: string, managedDir: string, bundledDir: string): string {
  return buildWorkspaceSkillsPrompt(workspaceDir, {
    managedSkillsDir: managedDir,
    bundledSkillsDir: bundledDir,
  });
}

async function createWorkspaceSkillDirs() {
  const workspaceDir = await createTempDir("openclaw-");
  return {
    workspaceDir,
    managedDir: path.join(workspaceDir, ".managed"),
    bundledDir: path.join(workspaceDir, ".bundled"),
  };
}

(deftest-group "buildWorkspaceSkillsPrompt — .agents/skills/ directories", () => {
  let fakeHome: string;

  beforeEach(async () => {
    fakeHome = await createTempDir("openclaw-home-");
    mock:spyOn(os, "homedir").mockReturnValue(fakeHome);
  });

  afterEach(async () => {
    mock:restoreAllMocks();
    await Promise.all(
      tempDirs
        .splice(0, tempDirs.length)
        .map((dir) => fs.rm(dir, { recursive: true, force: true })),
    );
  });

  (deftest "loads project .agents/skills/ above managed and below workspace", async () => {
    const { workspaceDir, managedDir, bundledDir } = await createWorkspaceSkillDirs();

    await writeSkill({
      dir: path.join(managedDir, "shared-skill"),
      name: "shared-skill",
      description: "Managed version",
    });
    await writeSkill({
      dir: path.join(workspaceDir, ".agents", "skills", "shared-skill"),
      name: "shared-skill",
      description: "Project agents version",
    });

    // project .agents/skills/ wins over managed
    const prompt1 = buildSkillsPrompt(workspaceDir, managedDir, bundledDir);
    (expect* prompt1).contains("Project agents version");
    (expect* prompt1).not.contains("Managed version");

    // workspace wins over project .agents/skills/
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "shared-skill"),
      name: "shared-skill",
      description: "Workspace version",
    });

    const prompt2 = buildSkillsPrompt(workspaceDir, managedDir, bundledDir);
    (expect* prompt2).contains("Workspace version");
    (expect* prompt2).not.contains("Project agents version");
  });

  (deftest "loads personal ~/.agents/skills/ above managed and below project .agents/skills/", async () => {
    const { workspaceDir, managedDir, bundledDir } = await createWorkspaceSkillDirs();

    await writeSkill({
      dir: path.join(managedDir, "shared-skill"),
      name: "shared-skill",
      description: "Managed version",
    });
    await writeSkill({
      dir: path.join(fakeHome, ".agents", "skills", "shared-skill"),
      name: "shared-skill",
      description: "Personal agents version",
    });

    // personal wins over managed
    const prompt1 = buildSkillsPrompt(workspaceDir, managedDir, bundledDir);
    (expect* prompt1).contains("Personal agents version");
    (expect* prompt1).not.contains("Managed version");

    // project .agents/skills/ wins over personal
    await writeSkill({
      dir: path.join(workspaceDir, ".agents", "skills", "shared-skill"),
      name: "shared-skill",
      description: "Project agents version",
    });

    const prompt2 = buildSkillsPrompt(workspaceDir, managedDir, bundledDir);
    (expect* prompt2).contains("Project agents version");
    (expect* prompt2).not.contains("Personal agents version");
  });

  (deftest "loads unique skills from all .agents/skills/ sources alongside others", async () => {
    const { workspaceDir, managedDir, bundledDir } = await createWorkspaceSkillDirs();

    await writeSkill({
      dir: path.join(managedDir, "managed-only"),
      name: "managed-only",
      description: "Managed only skill",
    });
    await writeSkill({
      dir: path.join(fakeHome, ".agents", "skills", "personal-only"),
      name: "personal-only",
      description: "Personal only skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, ".agents", "skills", "project-only"),
      name: "project-only",
      description: "Project only skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "workspace-only"),
      name: "workspace-only",
      description: "Workspace only skill",
    });

    const prompt = buildSkillsPrompt(workspaceDir, managedDir, bundledDir);
    (expect* prompt).contains("managed-only");
    (expect* prompt).contains("personal-only");
    (expect* prompt).contains("project-only");
    (expect* prompt).contains("workspace-only");
  });
});
