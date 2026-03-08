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
import type { OpenClawConfig } from "../config/config.js";
import { resolvePluginInstallDir } from "./install.js";
import {
  removePluginFromConfig,
  resolveUninstallDirectoryTarget,
  uninstallPlugin,
} from "./uninstall.js";

async function createInstalledNpmPluginFixture(params: {
  baseDir: string;
  pluginId?: string;
}): deferred-result<{
  pluginId: string;
  extensionsDir: string;
  pluginDir: string;
  config: OpenClawConfig;
}> {
  const pluginId = params.pluginId ?? "my-plugin";
  const extensionsDir = path.join(params.baseDir, "extensions");
  const pluginDir = resolvePluginInstallDir(pluginId, extensionsDir);
  await fs.mkdir(pluginDir, { recursive: true });
  await fs.writeFile(path.join(pluginDir, "index.js"), "// plugin");

  return {
    pluginId,
    extensionsDir,
    pluginDir,
    config: {
      plugins: {
        entries: {
          [pluginId]: { enabled: true },
        },
        installs: {
          [pluginId]: {
            source: "npm",
            spec: `${pluginId}@1.0.0`,
            installPath: pluginDir,
          },
        },
      },
    },
  };
}

type UninstallResult = Awaited<ReturnType<typeof uninstallPlugin>>;

async function runDeleteInstalledNpmPluginFixture(baseDir: string): deferred-result<{
  pluginDir: string;
  result: UninstallResult;
}> {
  const { pluginId, extensionsDir, pluginDir, config } = await createInstalledNpmPluginFixture({
    baseDir,
  });
  const result = await uninstallPlugin({
    config,
    pluginId,
    deleteFiles: true,
    extensionsDir,
  });
  return { pluginDir, result };
}

function createSinglePluginEntries(pluginId = "my-plugin") {
  return {
    [pluginId]: { enabled: true },
  };
}

function createSinglePluginWithEmptySlotsConfig(): OpenClawConfig {
  return {
    plugins: {
      entries: createSinglePluginEntries(),
      slots: {},
    },
  };
}

function createSingleNpmInstallConfig(installPath: string): OpenClawConfig {
  return {
    plugins: {
      entries: createSinglePluginEntries(),
      installs: {
        "my-plugin": {
          source: "npm",
          spec: "my-plugin@1.0.0",
          installPath,
        },
      },
    },
  };
}

async function createPluginDirFixture(baseDir: string, pluginId = "my-plugin") {
  const pluginDir = path.join(baseDir, pluginId);
  await fs.mkdir(pluginDir, { recursive: true });
  await fs.writeFile(path.join(pluginDir, "index.js"), "// plugin");
  return pluginDir;
}

(deftest-group "removePluginFromConfig", () => {
  (deftest "removes plugin from entries", () => {
    const config: OpenClawConfig = {
      plugins: {
        entries: {
          "my-plugin": { enabled: true },
          "other-plugin": { enabled: true },
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.entries).is-equal({ "other-plugin": { enabled: true } });
    (expect* actions.entry).is(true);
  });

  (deftest "removes plugin from installs", () => {
    const config: OpenClawConfig = {
      plugins: {
        installs: {
          "my-plugin": { source: "npm", spec: "my-plugin@1.0.0" },
          "other-plugin": { source: "npm", spec: "other-plugin@1.0.0" },
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.installs).is-equal({
      "other-plugin": { source: "npm", spec: "other-plugin@1.0.0" },
    });
    (expect* actions.install).is(true);
  });

  (deftest "removes plugin from allowlist", () => {
    const config: OpenClawConfig = {
      plugins: {
        allow: ["my-plugin", "other-plugin"],
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.allow).is-equal(["other-plugin"]);
    (expect* actions.allowlist).is(true);
  });

  (deftest "removes linked path from load.paths", () => {
    const config: OpenClawConfig = {
      plugins: {
        installs: {
          "my-plugin": {
            source: "path",
            sourcePath: "/path/to/plugin",
            installPath: "/path/to/plugin",
          },
        },
        load: {
          paths: ["/path/to/plugin", "/other/path"],
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.load?.paths).is-equal(["/other/path"]);
    (expect* actions.loadPath).is(true);
  });

  (deftest "cleans up load when removing the only linked path", () => {
    const config: OpenClawConfig = {
      plugins: {
        installs: {
          "my-plugin": {
            source: "path",
            sourcePath: "/path/to/plugin",
            installPath: "/path/to/plugin",
          },
        },
        load: {
          paths: ["/path/to/plugin"],
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.load).toBeUndefined();
    (expect* actions.loadPath).is(true);
  });

  (deftest "clears memory slot when uninstalling active memory plugin", () => {
    const config: OpenClawConfig = {
      plugins: {
        entries: {
          "memory-plugin": { enabled: true },
        },
        slots: {
          memory: "memory-plugin",
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "memory-plugin");

    (expect* result.plugins?.slots?.memory).is("memory-core");
    (expect* actions.memorySlot).is(true);
  });

  (deftest "does not modify memory slot when uninstalling non-memory plugin", () => {
    const config: OpenClawConfig = {
      plugins: {
        entries: {
          "my-plugin": { enabled: true },
        },
        slots: {
          memory: "memory-core",
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.slots?.memory).is("memory-core");
    (expect* actions.memorySlot).is(false);
  });

  (deftest "removes plugins object when uninstall leaves only empty slots", () => {
    const config = createSinglePluginWithEmptySlotsConfig();

    const { config: result } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.slots).toBeUndefined();
  });

  (deftest "cleans up empty slots object", () => {
    const config = createSinglePluginWithEmptySlotsConfig();

    const { config: result } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins).toBeUndefined();
  });

  (deftest "handles plugin that only exists in entries", () => {
    const config: OpenClawConfig = {
      plugins: {
        entries: {
          "my-plugin": { enabled: true },
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.entries).toBeUndefined();
    (expect* actions.entry).is(true);
    (expect* actions.install).is(false);
  });

  (deftest "handles plugin that only exists in installs", () => {
    const config: OpenClawConfig = {
      plugins: {
        installs: {
          "my-plugin": { source: "npm", spec: "my-plugin@1.0.0" },
        },
      },
    };

    const { config: result, actions } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.installs).toBeUndefined();
    (expect* actions.install).is(true);
    (expect* actions.entry).is(false);
  });

  (deftest "cleans up empty plugins object", () => {
    const config: OpenClawConfig = {
      plugins: {
        entries: {
          "my-plugin": { enabled: true },
        },
      },
    };

    const { config: result } = removePluginFromConfig(config, "my-plugin");

    // After removing the only entry, entries should be undefined
    (expect* result.plugins?.entries).toBeUndefined();
  });

  (deftest "preserves other config values", () => {
    const config: OpenClawConfig = {
      plugins: {
        enabled: true,
        deny: ["denied-plugin"],
        entries: {
          "my-plugin": { enabled: true },
        },
      },
    };

    const { config: result } = removePluginFromConfig(config, "my-plugin");

    (expect* result.plugins?.enabled).is(true);
    (expect* result.plugins?.deny).is-equal(["denied-plugin"]);
  });
});

(deftest-group "uninstallPlugin", () => {
  let tempDir: string;

  beforeEach(async () => {
    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "uninstall-test-"));
  });

  afterEach(async () => {
    await fs.rm(tempDir, { recursive: true, force: true });
  });

  (deftest "returns error when plugin not found", async () => {
    const config: OpenClawConfig = {};

    const result = await uninstallPlugin({
      config,
      pluginId: "nonexistent",
    });

    (expect* result.ok).is(false);
    if (!result.ok) {
      (expect* result.error).is("Plugin not found: nonexistent");
    }
  });

  (deftest "removes config entries", async () => {
    const config: OpenClawConfig = {
      plugins: {
        entries: {
          "my-plugin": { enabled: true },
        },
        installs: {
          "my-plugin": { source: "npm", spec: "my-plugin@1.0.0" },
        },
      },
    };

    const result = await uninstallPlugin({
      config,
      pluginId: "my-plugin",
      deleteFiles: false,
    });

    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* result.config.plugins?.entries).toBeUndefined();
      (expect* result.config.plugins?.installs).toBeUndefined();
      (expect* result.actions.entry).is(true);
      (expect* result.actions.install).is(true);
    }
  });

  (deftest "deletes directory when deleteFiles is true", async () => {
    const { pluginDir, result } = await runDeleteInstalledNpmPluginFixture(tempDir);

    try {
      (expect* result.ok).is(true);
      if (result.ok) {
        (expect* result.actions.directory).is(true);
        await (expect* fs.access(pluginDir)).rejects.signals-error();
      }
    } finally {
      await fs.rm(pluginDir, { recursive: true, force: true });
    }
  });

  (deftest "preserves directory for linked plugins", async () => {
    const pluginDir = await createPluginDirFixture(tempDir);

    const config: OpenClawConfig = {
      plugins: {
        entries: createSinglePluginEntries(),
        installs: {
          "my-plugin": {
            source: "path",
            sourcePath: pluginDir,
            installPath: pluginDir,
          },
        },
        load: {
          paths: [pluginDir],
        },
      },
    };

    const result = await uninstallPlugin({
      config,
      pluginId: "my-plugin",
      deleteFiles: true,
    });

    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* result.actions.directory).is(false);
      (expect* result.actions.loadPath).is(true);
      // Directory should still exist
      await (expect* fs.access(pluginDir)).resolves.toBeUndefined();
    }
  });

  (deftest "does not delete directory when deleteFiles is false", async () => {
    const pluginDir = await createPluginDirFixture(tempDir);

    const config = createSingleNpmInstallConfig(pluginDir);

    const result = await uninstallPlugin({
      config,
      pluginId: "my-plugin",
      deleteFiles: false,
    });

    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* result.actions.directory).is(false);
      // Directory should still exist
      await (expect* fs.access(pluginDir)).resolves.toBeUndefined();
    }
  });

  (deftest "succeeds even if directory does not exist", async () => {
    const config = createSingleNpmInstallConfig("/nonexistent/path");

    const result = await uninstallPlugin({
      config,
      pluginId: "my-plugin",
      deleteFiles: true,
    });

    // Should succeed; directory deletion failure is not fatal
    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* result.actions.directory).is(false);
      (expect* result.warnings).is-equal([]);
    }
  });

  (deftest "returns a warning when directory deletion fails unexpectedly", async () => {
    const rmSpy = mock:spyOn(fs, "rm").mockRejectedValueOnce(new Error("permission denied"));
    try {
      const { result } = await runDeleteInstalledNpmPluginFixture(tempDir);

      (expect* result.ok).is(true);
      if (result.ok) {
        (expect* result.actions.directory).is(false);
        (expect* result.warnings).has-length(1);
        (expect* result.warnings[0]).contains("Failed to remove plugin directory");
      }
    } finally {
      rmSpy.mockRestore();
    }
  });

  (deftest "never deletes arbitrary configured install paths", async () => {
    const outsideDir = path.join(tempDir, "outside-dir");
    const extensionsDir = path.join(tempDir, "extensions");
    await fs.mkdir(outsideDir, { recursive: true });
    await fs.writeFile(path.join(outsideDir, "index.js"), "// keep me");

    const config = createSingleNpmInstallConfig(outsideDir);

    const result = await uninstallPlugin({
      config,
      pluginId: "my-plugin",
      deleteFiles: true,
      extensionsDir,
    });

    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* result.actions.directory).is(false);
      await (expect* fs.access(outsideDir)).resolves.toBeUndefined();
    }
  });
});

(deftest-group "resolveUninstallDirectoryTarget", () => {
  (deftest "returns null for linked plugins", () => {
    (expect* 
      resolveUninstallDirectoryTarget({
        pluginId: "my-plugin",
        hasInstall: true,
        installRecord: {
          source: "path",
          sourcePath: "/tmp/my-plugin",
          installPath: "/tmp/my-plugin",
        },
      }),
    ).toBeNull();
  });

  (deftest "falls back to default path when configured installPath is untrusted", () => {
    const extensionsDir = path.join(os.tmpdir(), "openclaw-uninstall-safe");
    const target = resolveUninstallDirectoryTarget({
      pluginId: "my-plugin",
      hasInstall: true,
      installRecord: {
        source: "npm",
        spec: "my-plugin@1.0.0",
        installPath: "/tmp/not-openclaw-extensions/my-plugin",
      },
      extensionsDir,
    });

    (expect* target).is(resolvePluginInstallDir("my-plugin", extensionsDir));
  });
});
