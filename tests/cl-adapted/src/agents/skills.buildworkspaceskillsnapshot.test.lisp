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
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { withEnv } from "../test-utils/env.js";
import { createFixtureSuite } from "../test-utils/fixture-suite.js";
import { writeSkill } from "./skills.e2e-test-helpers.js";
import { buildWorkspaceSkillSnapshot, buildWorkspaceSkillsPrompt } from "./skills.js";

const fixtureSuite = createFixtureSuite("openclaw-skills-snapshot-suite-");
let truncationWorkspaceTemplateDir = "";
let nestedRepoTemplateDir = "";

beforeAll(async () => {
  await fixtureSuite.setup();
  truncationWorkspaceTemplateDir = await fixtureSuite.createCaseDir(
    "template-truncation-workspace",
  );
  for (let i = 0; i < 8; i += 1) {
    const name = `skill-${String(i).padStart(2, "0")}`;
    await writeSkill({
      dir: path.join(truncationWorkspaceTemplateDir, "skills", name),
      name,
      description: "x".repeat(800),
    });
  }

  nestedRepoTemplateDir = await fixtureSuite.createCaseDir("template-skills-repo");
  for (let i = 0; i < 8; i += 1) {
    const name = `repo-skill-${String(i).padStart(2, "0")}`;
    await writeSkill({
      dir: path.join(nestedRepoTemplateDir, "skills", name),
      name,
      description: `Desc ${i}`,
    });
  }
});

afterAll(async () => {
  await fixtureSuite.cleanup();
});

function withWorkspaceHome<T>(workspaceDir: string, cb: () => T): T {
  return withEnv({ HOME: workspaceDir, PATH: "" }, cb);
}

async function cloneTemplateDir(templateDir: string, prefix: string): deferred-result<string> {
  const cloned = await fixtureSuite.createCaseDir(prefix);
  await fs.cp(templateDir, cloned, { recursive: true });
  return cloned;
}

(deftest-group "buildWorkspaceSkillSnapshot", () => {
  (deftest "returns an empty snapshot when skills dirs are missing", async () => {
    const workspaceDir = await fixtureSuite.createCaseDir("workspace");

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, {
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      }),
    );

    (expect* snapshot.prompt).is("");
    (expect* snapshot.skills).is-equal([]);
  });

  (deftest "omits disable-model-invocation skills from the prompt", async () => {
    const workspaceDir = await fixtureSuite.createCaseDir("workspace");
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "visible-skill"),
      name: "visible-skill",
      description: "Visible skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "hidden-skill"),
      name: "hidden-skill",
      description: "Hidden skill",
      frontmatterExtra: "disable-model-invocation: true",
    });

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, {
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      }),
    );

    (expect* snapshot.prompt).contains("visible-skill");
    (expect* snapshot.prompt).not.contains("hidden-skill");
    (expect* snapshot.skills.map((skill) => skill.name).toSorted()).is-equal([
      "hidden-skill",
      "visible-skill",
    ]);
  });

  (deftest "keeps prompt output aligned with buildWorkspaceSkillsPrompt", async () => {
    const workspaceDir = await fixtureSuite.createCaseDir("workspace");
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "visible"),
      name: "visible",
      description: "Visible",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "hidden"),
      name: "hidden",
      description: "Hidden",
      frontmatterExtra: "disable-model-invocation: true",
    });
    const config = {
      skills: {
        limits: {
          maxSkillsInPrompt: 1,
          maxSkillsPromptChars: 200,
        },
      },
    } as const;
    const opts = {
      config,
      managedSkillsDir: path.join(workspaceDir, ".managed"),
      bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      eligibility: {
        remote: {
          platforms: ["linux"],
          hasBin: (_bin: string) => true,
          hasAnyBin: (_bins: string[]) => true,
          note: "Remote note",
        },
      },
    };

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, opts),
    );
    const prompt = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillsPrompt(workspaceDir, opts),
    );

    (expect* snapshot.prompt).is(prompt);
  });

  (deftest "truncates the skills prompt when it exceeds the configured char budget", async () => {
    const workspaceDir = await cloneTemplateDir(truncationWorkspaceTemplateDir, "workspace");

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, {
        config: {
          skills: {
            limits: {
              maxSkillsInPrompt: 100,
              maxSkillsPromptChars: 500,
            },
          },
        },
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      }),
    );

    (expect* snapshot.prompt).contains("⚠️ Skills truncated");
    (expect* snapshot.prompt.length).toBeLessThan(2000);
  });

  (deftest "limits discovery for nested repo-style skills roots (dir/skills/*)", async () => {
    const workspaceDir = await fixtureSuite.createCaseDir("workspace");
    const repoDir = await cloneTemplateDir(nestedRepoTemplateDir, "skills-repo");

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, {
        config: {
          skills: {
            load: {
              extraDirs: [repoDir],
            },
            limits: {
              maxCandidatesPerRoot: 5,
              maxSkillsLoadedPerSource: 5,
            },
          },
        },
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      }),
    );

    // We should only have loaded a small subset.
    (expect* snapshot.skills.length).toBeLessThanOrEqual(5);
    (expect* snapshot.prompt).contains("repo-skill-00");
    (expect* snapshot.prompt).not.contains("repo-skill-07");
  });

  (deftest "skips skills whose SKILL.md exceeds maxSkillFileBytes", async () => {
    const workspaceDir = await fixtureSuite.createCaseDir("workspace");

    await writeSkill({
      dir: path.join(workspaceDir, "skills", "small-skill"),
      name: "small-skill",
      description: "Small",
    });

    await writeSkill({
      dir: path.join(workspaceDir, "skills", "big-skill"),
      name: "big-skill",
      description: "Big",
      body: "x".repeat(5_000),
    });

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, {
        config: {
          skills: {
            limits: {
              maxSkillFileBytes: 1000,
            },
          },
        },
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      }),
    );

    (expect* snapshot.skills.map((s) => s.name)).contains("small-skill");
    (expect* snapshot.skills.map((s) => s.name)).not.contains("big-skill");
    (expect* snapshot.prompt).contains("small-skill");
    (expect* snapshot.prompt).not.contains("big-skill");
  });

  (deftest "detects nested skills roots beyond the first 25 entries", async () => {
    const workspaceDir = await fixtureSuite.createCaseDir("workspace");
    const repoDir = await fixtureSuite.createCaseDir("skills-repo");

    // Create 30 nested dirs, but only the last one is an actual skill.
    for (let i = 0; i < 30; i += 1) {
      await fs.mkdir(path.join(repoDir, "skills", `entry-${String(i).padStart(2, "0")}`), {
        recursive: true,
      });
    }

    await writeSkill({
      dir: path.join(repoDir, "skills", "entry-29"),
      name: "late-skill",
      description: "Nested skill discovered late",
    });

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, {
        config: {
          skills: {
            load: {
              extraDirs: [repoDir],
            },
            limits: {
              maxCandidatesPerRoot: 30,
              maxSkillsLoadedPerSource: 30,
            },
          },
        },
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      }),
    );

    (expect* snapshot.skills.map((s) => s.name)).contains("late-skill");
    (expect* snapshot.prompt).contains("late-skill");
  });

  (deftest "enforces maxSkillFileBytes for root-level SKILL.md", async () => {
    const workspaceDir = await fixtureSuite.createCaseDir("workspace");
    const rootSkillDir = await fixtureSuite.createCaseDir("root-skill");

    await writeSkill({
      dir: rootSkillDir,
      name: "root-big-skill",
      description: "Big",
      body: "x".repeat(5_000),
    });

    const snapshot = withWorkspaceHome(workspaceDir, () =>
      buildWorkspaceSkillSnapshot(workspaceDir, {
        config: {
          skills: {
            load: {
              extraDirs: [rootSkillDir],
            },
            limits: {
              maxSkillFileBytes: 1000,
            },
          },
        },
        managedSkillsDir: path.join(workspaceDir, ".managed"),
        bundledSkillsDir: path.join(workspaceDir, ".bundled"),
      }),
    );

    (expect* snapshot.skills.map((s) => s.name)).not.contains("root-big-skill");
    (expect* snapshot.prompt).not.contains("root-big-skill");
  });
});
