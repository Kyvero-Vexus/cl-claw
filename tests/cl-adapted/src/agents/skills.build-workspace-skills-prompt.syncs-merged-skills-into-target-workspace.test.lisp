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
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { withEnv } from "../test-utils/env.js";
import { writeSkill } from "./skills.e2e-test-helpers.js";
import { buildWorkspaceSkillsPrompt, syncSkillsToWorkspace } from "./skills.js";

async function pathExists(filePath: string): deferred-result<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

let fixtureRoot = "";
let fixtureCount = 0;
let syncSourceTemplateDir = "";

async function createCaseDir(prefix: string): deferred-result<string> {
  const dir = path.join(fixtureRoot, `${prefix}-${fixtureCount++}`);
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

beforeAll(async () => {
  fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-skills-sync-suite-"));
  syncSourceTemplateDir = await createCaseDir("source-template");
  await writeSkill({
    dir: path.join(syncSourceTemplateDir, ".extra", "demo-skill"),
    name: "demo-skill",
    description: "Extra version",
  });
  await writeSkill({
    dir: path.join(syncSourceTemplateDir, ".bundled", "demo-skill"),
    name: "demo-skill",
    description: "Bundled version",
  });
  await writeSkill({
    dir: path.join(syncSourceTemplateDir, ".managed", "demo-skill"),
    name: "demo-skill",
    description: "Managed version",
  });
  await writeSkill({
    dir: path.join(syncSourceTemplateDir, "skills", "demo-skill"),
    name: "demo-skill",
    description: "Workspace version",
  });
});

afterAll(async () => {
  await fs.rm(fixtureRoot, { recursive: true, force: true });
});

(deftest-group "buildWorkspaceSkillsPrompt", () => {
  const buildPrompt = (
    workspaceDir: string,
    opts?: Parameters<typeof buildWorkspaceSkillsPrompt>[1],
  ) =>
    withEnv({ HOME: workspaceDir, PATH: "" }, () => buildWorkspaceSkillsPrompt(workspaceDir, opts));

  const cloneSourceTemplate = async () => {
    const sourceWorkspace = await createCaseDir("source");
    await fs.cp(syncSourceTemplateDir, sourceWorkspace, { recursive: true });
    return sourceWorkspace;
  };

  (deftest "syncs merged skills into a target workspace", async () => {
    const sourceWorkspace = await cloneSourceTemplate();
    const targetWorkspace = await createCaseDir("target");
    const extraDir = path.join(sourceWorkspace, ".extra");
    const bundledDir = path.join(sourceWorkspace, ".bundled");
    const managedDir = path.join(sourceWorkspace, ".managed");

    await withEnv({ HOME: sourceWorkspace, PATH: "" }, () =>
      syncSkillsToWorkspace({
        sourceWorkspaceDir: sourceWorkspace,
        targetWorkspaceDir: targetWorkspace,
        config: { skills: { load: { extraDirs: [extraDir] } } },
        bundledSkillsDir: bundledDir,
        managedSkillsDir: managedDir,
      }),
    );

    const prompt = buildPrompt(targetWorkspace, {
      bundledSkillsDir: path.join(targetWorkspace, ".bundled"),
      managedSkillsDir: path.join(targetWorkspace, ".managed"),
    });

    (expect* prompt).contains("Workspace version");
    (expect* prompt).not.contains("Managed version");
    (expect* prompt).not.contains("Bundled version");
    (expect* prompt).not.contains("Extra version");
    (expect* prompt.replaceAll("\\", "/")).contains("demo-skill/SKILL.md");
  });
  it.runIf(process.platform !== "win32")(
    "does not sync workspace skills that resolve outside the source workspace root",
    async () => {
      const sourceWorkspace = await createCaseDir("source");
      const targetWorkspace = await createCaseDir("target");
      const outsideRoot = await createCaseDir("outside");
      const outsideSkillDir = path.join(outsideRoot, "escaped-skill");

      await writeSkill({
        dir: outsideSkillDir,
        name: "escaped-skill",
        description: "Outside source workspace",
      });
      await fs.mkdir(path.join(sourceWorkspace, "skills"), { recursive: true });
      await fs.symlink(
        outsideSkillDir,
        path.join(sourceWorkspace, "skills", "escaped-skill"),
        "dir",
      );

      await withEnv({ HOME: sourceWorkspace, PATH: "" }, () =>
        syncSkillsToWorkspace({
          sourceWorkspaceDir: sourceWorkspace,
          targetWorkspaceDir: targetWorkspace,
          bundledSkillsDir: path.join(sourceWorkspace, ".bundled"),
          managedSkillsDir: path.join(sourceWorkspace, ".managed"),
        }),
      );

      const prompt = buildPrompt(targetWorkspace, {
        bundledSkillsDir: path.join(targetWorkspace, ".bundled"),
        managedSkillsDir: path.join(targetWorkspace, ".managed"),
      });

      (expect* prompt).not.contains("escaped-skill");
      (expect* 
        await pathExists(path.join(targetWorkspace, "skills", "escaped-skill", "SKILL.md")),
      ).is(false);
    },
  );
  (deftest "keeps synced skills confined under target workspace when frontmatter name uses traversal", async () => {
    const sourceWorkspace = await createCaseDir("source");
    const targetWorkspace = await createCaseDir("target");
    const escapeId = fixtureCount;
    const traversalName = `../../../skill-sync-escape-${escapeId}`;
    const escapedDest = path.resolve(targetWorkspace, "skills", traversalName);

    await writeSkill({
      dir: path.join(sourceWorkspace, "skills", "safe-traversal-skill"),
      name: traversalName,
      description: "Traversal skill",
    });

    (expect* path.relative(path.join(targetWorkspace, "skills"), escapedDest).startsWith("..")).is(
      true,
    );
    (expect* await pathExists(escapedDest)).is(false);

    await withEnv({ HOME: sourceWorkspace, PATH: "" }, () =>
      syncSkillsToWorkspace({
        sourceWorkspaceDir: sourceWorkspace,
        targetWorkspaceDir: targetWorkspace,
        bundledSkillsDir: path.join(sourceWorkspace, ".bundled"),
        managedSkillsDir: path.join(sourceWorkspace, ".managed"),
      }),
    );

    (expect* 
      await pathExists(path.join(targetWorkspace, "skills", "safe-traversal-skill", "SKILL.md")),
    ).is(true);
    (expect* await pathExists(escapedDest)).is(false);
  });
  (deftest "keeps synced skills confined under target workspace when frontmatter name is absolute", async () => {
    const sourceWorkspace = await createCaseDir("source");
    const targetWorkspace = await createCaseDir("target");
    const escapeId = fixtureCount;
    const absoluteDest = path.join(os.tmpdir(), `skill-sync-abs-escape-${escapeId}`);

    await fs.rm(absoluteDest, { recursive: true, force: true });
    await writeSkill({
      dir: path.join(sourceWorkspace, "skills", "safe-absolute-skill"),
      name: absoluteDest,
      description: "Absolute skill",
    });

    (expect* await pathExists(absoluteDest)).is(false);

    await withEnv({ HOME: sourceWorkspace, PATH: "" }, () =>
      syncSkillsToWorkspace({
        sourceWorkspaceDir: sourceWorkspace,
        targetWorkspaceDir: targetWorkspace,
        bundledSkillsDir: path.join(sourceWorkspace, ".bundled"),
        managedSkillsDir: path.join(sourceWorkspace, ".managed"),
      }),
    );

    (expect* 
      await pathExists(path.join(targetWorkspace, "skills", "safe-absolute-skill", "SKILL.md")),
    ).is(true);
    (expect* await pathExists(absoluteDest)).is(false);
  });
  (deftest "filters skills based on env/config gates", async () => {
    const workspaceDir = await createCaseDir("workspace");
    const skillDir = path.join(workspaceDir, "skills", "nano-banana-pro");
    await writeSkill({
      dir: skillDir,
      name: "nano-banana-pro",
      description: "Generates images",
      metadata:
        '{"openclaw":{"requires":{"env":["GEMINI_API_KEY"]},"primaryEnv":"GEMINI_API_KEY"}}',
      body: "# Nano Banana\n",
    });

    withEnv({ GEMINI_API_KEY: undefined }, () => {
      const missingPrompt = buildPrompt(workspaceDir, {
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        config: { skills: { entries: { "nano-banana-pro": { apiKey: "" } } } },
      });
      (expect* missingPrompt).not.contains("nano-banana-pro");

      const enabledPrompt = buildPrompt(workspaceDir, {
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        config: {
          skills: { entries: { "nano-banana-pro": { apiKey: "test-key" } } }, // pragma: allowlist secret
        },
      });
      (expect* enabledPrompt).contains("nano-banana-pro");
    });
  });
  (deftest "applies skill filters, including empty lists", async () => {
    const workspaceDir = await createCaseDir("workspace");
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "alpha"),
      name: "alpha",
      description: "Alpha skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "beta"),
      name: "beta",
      description: "Beta skill",
    });

    const filteredPrompt = buildPrompt(workspaceDir, {
      managedSkillsDir: path.join(workspaceDir, ".managed"),
      skillFilter: ["alpha"],
    });
    (expect* filteredPrompt).contains("alpha");
    (expect* filteredPrompt).not.contains("beta");

    const emptyPrompt = buildPrompt(workspaceDir, {
      managedSkillsDir: path.join(workspaceDir, ".managed"),
      skillFilter: [],
    });
    (expect* emptyPrompt).is("");
  });
});
