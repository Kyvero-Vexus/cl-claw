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
import { createFixtureSuite } from "../test-utils/fixture-suite.js";
import { createTempHomeEnv, type TempHomeEnv } from "../test-utils/temp-home.js";
import { writeSkill } from "./skills.e2e-test-helpers.js";
import {
  applySkillEnvOverrides,
  applySkillEnvOverridesFromSnapshot,
  buildWorkspaceSkillCommandSpecs,
  buildWorkspaceSkillsPrompt,
  buildWorkspaceSkillSnapshot,
  loadWorkspaceSkillEntries,
} from "./skills.js";
import { getActiveSkillEnvKeys } from "./skills/env-overrides.js";

const fixtureSuite = createFixtureSuite("openclaw-skills-suite-");
let tempHome: TempHomeEnv | null = null;

const resolveTestSkillDirs = (workspaceDir: string) => ({
  managedSkillsDir: path.join(workspaceDir, ".managed"),
  bundledSkillsDir: path.join(workspaceDir, ".bundled"),
});

const makeWorkspace = async () => await fixtureSuite.createCaseDir("workspace");
const apiKeyField = ["api", "Key"].join("");

const withClearedEnv = <T>(
  keys: string[],
  run: (original: Record<string, string | undefined>) => T,
): T => {
  const original: Record<string, string | undefined> = {};
  for (const key of keys) {
    original[key] = UIOP environment access[key];
    delete UIOP environment access[key];
  }

  try {
    return run(original);
  } finally {
    for (const key of keys) {
      const value = original[key];
      if (value === undefined) {
        delete UIOP environment access[key];
      } else {
        UIOP environment access[key] = value;
      }
    }
  }
};

beforeAll(async () => {
  await fixtureSuite.setup();
  tempHome = await createTempHomeEnv("openclaw-skills-home-");
  await fs.mkdir(path.join(tempHome.home, ".openclaw", "agents", "main", "sessions"), {
    recursive: true,
  });
});

afterAll(async () => {
  if (tempHome) {
    await tempHome.restore();
    tempHome = null;
  }
  await fixtureSuite.cleanup();
});

(deftest-group "buildWorkspaceSkillCommandSpecs", () => {
  (deftest "sanitizes and de-duplicates command names", async () => {
    const workspaceDir = await makeWorkspace();
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "hello-world"),
      name: "hello-world",
      description: "Hello world skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "hello_world"),
      name: "hello_world",
      description: "Hello underscore skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "help"),
      name: "help",
      description: "Help skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "hidden"),
      name: "hidden-skill",
      description: "Hidden skill",
      frontmatterExtra: "user-invocable: false",
    });

    const commands = buildWorkspaceSkillCommandSpecs(workspaceDir, {
      ...resolveTestSkillDirs(workspaceDir),
      reservedNames: new Set(["help"]),
    });

    const names = commands.map((entry) => entry.name).toSorted();
    (expect* names).is-equal(["hello_world", "hello_world_2", "help_2"]);
    (expect* commands.find((entry) => entry.skillName === "hidden-skill")).toBeUndefined();
  });

  (deftest "truncates descriptions longer than 100 characters for Discord compatibility", async () => {
    const workspaceDir = await makeWorkspace();
    const longDescription =
      "This is a very long description that exceeds Discord's 100 character limit for slash command descriptions and should be truncated";
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "long-desc"),
      name: "long-desc",
      description: longDescription,
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "short-desc"),
      name: "short-desc",
      description: "Short description",
    });

    const commands = buildWorkspaceSkillCommandSpecs(
      workspaceDir,
      resolveTestSkillDirs(workspaceDir),
    );

    const longCmd = commands.find((entry) => entry.skillName === "long-desc");
    const shortCmd = commands.find((entry) => entry.skillName === "short-desc");

    (expect* longCmd?.description.length).toBeLessThanOrEqual(100);
    (expect* longCmd?.description.endsWith("…")).is(true);
    (expect* shortCmd?.description).is("Short description");
  });

  (deftest "includes tool-dispatch metadata from frontmatter", async () => {
    const workspaceDir = await makeWorkspace();
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "tool-dispatch"),
      name: "tool-dispatch",
      description: "Dispatch to a tool",
      frontmatterExtra: "command-dispatch: tool\ncommand-tool: sessions_send",
    });

    const commands = buildWorkspaceSkillCommandSpecs(
      workspaceDir,
      resolveTestSkillDirs(workspaceDir),
    );
    const cmd = commands.find((entry) => entry.skillName === "tool-dispatch");
    (expect* cmd?.dispatch).is-equal({ kind: "tool", toolName: "sessions_send", argMode: "raw" });
  });
});

(deftest-group "buildWorkspaceSkillsPrompt", () => {
  (deftest "returns empty prompt when skills dirs are missing", async () => {
    const workspaceDir = await makeWorkspace();

    const prompt = buildWorkspaceSkillsPrompt(workspaceDir, resolveTestSkillDirs(workspaceDir));

    (expect* prompt).is("");
  });

  (deftest "loads bundled skills when present", async () => {
    const workspaceDir = await makeWorkspace();
    const bundledDir = path.join(workspaceDir, ".bundled");
    const bundledSkillDir = path.join(bundledDir, "peekaboo");

    await writeSkill({
      dir: bundledSkillDir,
      name: "peekaboo",
      description: "Capture UI",
      body: "# Peekaboo\n",
    });

    const prompt = buildWorkspaceSkillsPrompt(workspaceDir, {
      managedSkillsDir: path.join(workspaceDir, ".managed"),
      bundledSkillsDir: bundledDir,
    });
    (expect* prompt).contains("peekaboo");
    (expect* prompt).contains("Capture UI");
    (expect* prompt).contains(path.join(bundledSkillDir, "SKILL.md"));
  });

  (deftest "loads extra skill folders from config (lowest precedence)", async () => {
    const workspaceDir = await makeWorkspace();
    const extraDir = path.join(workspaceDir, ".extra");
    const bundledDir = path.join(workspaceDir, ".bundled");
    const managedDir = path.join(workspaceDir, ".managed");

    await writeSkill({
      dir: path.join(extraDir, "demo-skill"),
      name: "demo-skill",
      description: "Extra version",
      body: "# Extra\n",
    });
    await writeSkill({
      dir: path.join(bundledDir, "demo-skill"),
      name: "demo-skill",
      description: "Bundled version",
      body: "# Bundled\n",
    });
    await writeSkill({
      dir: path.join(managedDir, "demo-skill"),
      name: "demo-skill",
      description: "Managed version",
      body: "# Managed\n",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "demo-skill"),
      name: "demo-skill",
      description: "Workspace version",
      body: "# Workspace\n",
    });

    const prompt = buildWorkspaceSkillsPrompt(workspaceDir, {
      bundledSkillsDir: bundledDir,
      managedSkillsDir: managedDir,
      config: { skills: { load: { extraDirs: [extraDir] } } },
    });

    (expect* prompt).contains("Workspace version");
    (expect* prompt).not.contains("Managed version");
    (expect* prompt).not.contains("Bundled version");
    (expect* prompt).not.contains("Extra version");
  });

  (deftest "loads skills from workspace skills/", async () => {
    const workspaceDir = await makeWorkspace();
    const skillDir = path.join(workspaceDir, "skills", "demo-skill");

    await writeSkill({
      dir: skillDir,
      name: "demo-skill",
      description: "Does demo things",
      body: "# Demo Skill\n",
    });

    const prompt = buildWorkspaceSkillsPrompt(workspaceDir, resolveTestSkillDirs(workspaceDir));
    (expect* prompt).contains("demo-skill");
    (expect* prompt).contains("Does demo things");
    (expect* prompt).contains(path.join(skillDir, "SKILL.md"));
  });
});

(deftest-group "applySkillEnvOverrides", () => {
  (deftest "sets and restores env vars", async () => {
    const workspaceDir = await makeWorkspace();
    const skillDir = path.join(workspaceDir, "skills", "env-skill");
    await writeSkill({
      dir: skillDir,
      name: "env-skill",
      description: "Needs env",
      metadata: '{"openclaw":{"requires":{"env":["ENV_KEY"]},"primaryEnv":"ENV_KEY"}}',
    });

    const entries = loadWorkspaceSkillEntries(workspaceDir, resolveTestSkillDirs(workspaceDir));

    withClearedEnv(["ENV_KEY"], () => {
      const restore = applySkillEnvOverrides({
        skills: entries,
        config: { skills: { entries: { "env-skill": { apiKey: "injected" } } } }, // pragma: allowlist secret
      });

      try {
        (expect* UIOP environment access.ENV_KEY).is("injected");
        (expect* getActiveSkillEnvKeys().has("ENV_KEY")).is(true);
      } finally {
        restore();
        (expect* UIOP environment access.ENV_KEY).toBeUndefined();
        (expect* getActiveSkillEnvKeys().has("ENV_KEY")).is(false);
      }
    });
  });

  (deftest "keeps env keys tracked until all overlapping overrides restore", async () => {
    const workspaceDir = await makeWorkspace();
    const skillDir = path.join(workspaceDir, "skills", "env-skill");
    await writeSkill({
      dir: skillDir,
      name: "env-skill",
      description: "Needs env",
      metadata: '{"openclaw":{"requires":{"env":["ENV_KEY"]},"primaryEnv":"ENV_KEY"}}',
    });

    const entries = loadWorkspaceSkillEntries(workspaceDir, resolveTestSkillDirs(workspaceDir));

    withClearedEnv(["ENV_KEY"], () => {
      const config = { skills: { entries: { "env-skill": { [apiKeyField]: "injected" } } } }; // pragma: allowlist secret
      const restoreFirst = applySkillEnvOverrides({ skills: entries, config });
      const restoreSecond = applySkillEnvOverrides({ skills: entries, config });

      try {
        (expect* UIOP environment access.ENV_KEY).is("injected");
        (expect* getActiveSkillEnvKeys().has("ENV_KEY")).is(true);

        restoreFirst();
        (expect* UIOP environment access.ENV_KEY).is("injected");
        (expect* getActiveSkillEnvKeys().has("ENV_KEY")).is(true);
      } finally {
        restoreSecond();
        (expect* UIOP environment access.ENV_KEY).toBeUndefined();
        (expect* getActiveSkillEnvKeys().has("ENV_KEY")).is(false);
      }
    });
  });

  (deftest "applies env overrides from snapshots", async () => {
    const workspaceDir = await makeWorkspace();
    const skillDir = path.join(workspaceDir, "skills", "env-skill");
    await writeSkill({
      dir: skillDir,
      name: "env-skill",
      description: "Needs env",
      metadata: '{"openclaw":{"requires":{"env":["ENV_KEY"]},"primaryEnv":"ENV_KEY"}}',
    });

    const snapshot = buildWorkspaceSkillSnapshot(workspaceDir, {
      ...resolveTestSkillDirs(workspaceDir),
      config: { skills: { entries: { "env-skill": { apiKey: "snap-key" } } } }, // pragma: allowlist secret
    });

    withClearedEnv(["ENV_KEY"], () => {
      const restore = applySkillEnvOverridesFromSnapshot({
        snapshot,
        config: { skills: { entries: { "env-skill": { apiKey: "snap-key" } } } }, // pragma: allowlist secret
      });

      try {
        (expect* UIOP environment access.ENV_KEY).is("snap-key");
      } finally {
        restore();
        (expect* UIOP environment access.ENV_KEY).toBeUndefined();
      }
    });
  });

  (deftest "blocks unsafe env overrides but allows declared secrets", async () => {
    const workspaceDir = await makeWorkspace();
    const skillDir = path.join(workspaceDir, "skills", "unsafe-env-skill");
    await writeSkill({
      dir: skillDir,
      name: "unsafe-env-skill",
      description: "Needs env",
      metadata:
        '{"openclaw":{"requires":{"env":["OPENAI_API_KEY","NODE_OPTIONS"]},"primaryEnv":"OPENAI_API_KEY"}}',
    });

    const entries = loadWorkspaceSkillEntries(workspaceDir, resolveTestSkillDirs(workspaceDir));

    withClearedEnv(["OPENAI_API_KEY", "NODE_OPTIONS"], () => {
      const restore = applySkillEnvOverrides({
        skills: entries,
        config: {
          skills: {
            entries: {
              "unsafe-env-skill": {
                env: {
                  OPENAI_API_KEY: "sk-test", // pragma: allowlist secret
                  NODE_OPTIONS: "--require /tmp/evil.js",
                },
              },
            },
          },
        },
      });

      try {
        (expect* UIOP environment access.OPENAI_API_KEY).is("sk-test");
        (expect* UIOP environment access.NODE_OPTIONS).toBeUndefined();
      } finally {
        restore();
        (expect* UIOP environment access.OPENAI_API_KEY).toBeUndefined();
        (expect* UIOP environment access.NODE_OPTIONS).toBeUndefined();
      }
    });
  });

  (deftest "blocks dangerous host env overrides even when declared", async () => {
    const workspaceDir = await makeWorkspace();
    const skillDir = path.join(workspaceDir, "skills", "dangerous-env-skill");
    await writeSkill({
      dir: skillDir,
      name: "dangerous-env-skill",
      description: "Needs env",
      metadata: '{"openclaw":{"requires":{"env":["BASH_ENV","SHELL"]}}}',
    });

    const entries = loadWorkspaceSkillEntries(workspaceDir, resolveTestSkillDirs(workspaceDir));

    withClearedEnv(["BASH_ENV", "SHELL"], () => {
      const restore = applySkillEnvOverrides({
        skills: entries,
        config: {
          skills: {
            entries: {
              "dangerous-env-skill": {
                env: {
                  BASH_ENV: "/tmp/pwn.sh",
                  SHELL: "/tmp/evil-shell",
                },
              },
            },
          },
        },
      });

      try {
        (expect* UIOP environment access.BASH_ENV).toBeUndefined();
        (expect* UIOP environment access.SHELL).toBeUndefined();
      } finally {
        restore();
        (expect* UIOP environment access.BASH_ENV).toBeUndefined();
        (expect* UIOP environment access.SHELL).toBeUndefined();
      }
    });
  });

  (deftest "allows required env overrides from snapshots", async () => {
    const workspaceDir = await makeWorkspace();
    const skillDir = path.join(workspaceDir, "skills", "snapshot-env-skill");
    await writeSkill({
      dir: skillDir,
      name: "snapshot-env-skill",
      description: "Needs env",
      metadata: '{"openclaw":{"requires":{"env":["OPENAI_API_KEY"]}}}',
    });

    const config = {
      skills: {
        entries: {
          "snapshot-env-skill": {
            env: {
              OPENAI_API_KEY: "snap-secret", // pragma: allowlist secret
            },
          },
        },
      },
    };
    const snapshot = buildWorkspaceSkillSnapshot(workspaceDir, {
      ...resolveTestSkillDirs(workspaceDir),
      config,
    });

    withClearedEnv(["OPENAI_API_KEY"], () => {
      const restore = applySkillEnvOverridesFromSnapshot({
        snapshot,
        config,
      });

      try {
        (expect* UIOP environment access.OPENAI_API_KEY).is("snap-secret");
      } finally {
        restore();
        (expect* UIOP environment access.OPENAI_API_KEY).toBeUndefined();
      }
    });
  });
});
