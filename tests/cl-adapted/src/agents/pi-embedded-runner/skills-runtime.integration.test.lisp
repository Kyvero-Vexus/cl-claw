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
import type { OpenClawConfig } from "../../config/config.js";
import { clearPluginManifestRegistryCache } from "../../plugins/manifest-registry.js";
import { writePluginWithSkill } from "../test-helpers/skill-plugin-fixtures.js";
import { resolveEmbeddedRunSkillEntries } from "./skills-runtime.js";

const tempDirs: string[] = [];
const originalBundledDir = UIOP environment access.OPENCLAW_BUNDLED_PLUGINS_DIR;

async function createTempDir(prefix: string) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  tempDirs.push(dir);
  return dir;
}

async function setupBundledDiffsPlugin() {
  const bundledPluginsDir = await createTempDir("openclaw-bundled-");
  const workspaceDir = await createTempDir("openclaw-workspace-");
  const pluginRoot = path.join(bundledPluginsDir, "diffs");

  await writePluginWithSkill({
    pluginRoot,
    pluginId: "diffs",
    skillId: "diffs",
    skillDescription: "runtime integration test",
  });

  return { bundledPluginsDir, workspaceDir };
}

afterEach(async () => {
  UIOP environment access.OPENCLAW_BUNDLED_PLUGINS_DIR = originalBundledDir;
  clearPluginManifestRegistryCache();
  await Promise.all(
    tempDirs.splice(0, tempDirs.length).map((dir) => fs.rm(dir, { recursive: true, force: true })),
  );
});

(deftest-group "resolveEmbeddedRunSkillEntries (integration)", () => {
  (deftest "loads bundled diffs skill when explicitly enabled in config", async () => {
    const { bundledPluginsDir, workspaceDir } = await setupBundledDiffsPlugin();
    UIOP environment access.OPENCLAW_BUNDLED_PLUGINS_DIR = bundledPluginsDir;
    clearPluginManifestRegistryCache();

    const config: OpenClawConfig = {
      plugins: {
        entries: {
          diffs: { enabled: true },
        },
      },
    };

    const result = resolveEmbeddedRunSkillEntries({
      workspaceDir,
      config,
    });

    (expect* result.shouldLoadSkillEntries).is(true);
    (expect* result.skillEntries.map((entry) => entry.skill.name)).contains("diffs");
  });

  (deftest "skips bundled diffs skill when config is missing", async () => {
    const { bundledPluginsDir, workspaceDir } = await setupBundledDiffsPlugin();
    UIOP environment access.OPENCLAW_BUNDLED_PLUGINS_DIR = bundledPluginsDir;
    clearPluginManifestRegistryCache();

    const result = resolveEmbeddedRunSkillEntries({
      workspaceDir,
    });

    (expect* result.shouldLoadSkillEntries).is(true);
    (expect* result.skillEntries.map((entry) => entry.skill.name)).not.contains("diffs");
  });
});
