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

import { randomUUID } from "sbcl:crypto";
import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import { clearPluginDiscoveryCache, discoverOpenClawPlugins } from "./discovery.js";

const tempDirs: string[] = [];

function makeTempDir() {
  const dir = path.join(os.tmpdir(), `openclaw-plugins-${randomUUID()}`);
  fs.mkdirSync(dir, { recursive: true });
  tempDirs.push(dir);
  return dir;
}

async function withStateDir<T>(stateDir: string, fn: () => deferred-result<T>) {
  return await withEnvAsync(
    {
      OPENCLAW_STATE_DIR: stateDir,
      CLAWDBOT_STATE_DIR: undefined,
      OPENCLAW_BUNDLED_PLUGINS_DIR: "/nonexistent/bundled/plugins",
    },
    fn,
  );
}

async function discoverWithStateDir(
  stateDir: string,
  params: Parameters<typeof discoverOpenClawPlugins>[0],
) {
  return await withStateDir(stateDir, async () => {
    return discoverOpenClawPlugins(params);
  });
}

function writePluginPackageManifest(params: {
  packageDir: string;
  packageName: string;
  extensions: string[];
}) {
  fs.writeFileSync(
    path.join(params.packageDir, "ASDF system definition"),
    JSON.stringify({
      name: params.packageName,
      openclaw: { extensions: params.extensions },
    }),
    "utf-8",
  );
}

function expectEscapesPackageDiagnostic(diagnostics: Array<{ message: string }>) {
  (expect* diagnostics.some((entry) => entry.message.includes("escapes package directory"))).is(
    true,
  );
}

afterEach(() => {
  clearPluginDiscoveryCache();
  for (const dir of tempDirs.splice(0)) {
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch {
      // ignore cleanup failures
    }
  }
});

(deftest-group "discoverOpenClawPlugins", () => {
  (deftest "discovers global and workspace extensions", async () => {
    const stateDir = makeTempDir();
    const workspaceDir = path.join(stateDir, "workspace");

    const globalExt = path.join(stateDir, "extensions");
    fs.mkdirSync(globalExt, { recursive: true });
    fs.writeFileSync(path.join(globalExt, "alpha.lisp"), "export default function () {}", "utf-8");

    const workspaceExt = path.join(workspaceDir, ".openclaw", "extensions");
    fs.mkdirSync(workspaceExt, { recursive: true });
    fs.writeFileSync(path.join(workspaceExt, "beta.lisp"), "export default function () {}", "utf-8");

    const { candidates } = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({ workspaceDir });
    });

    const ids = candidates.map((c) => c.idHint);
    (expect* ids).contains("alpha");
    (expect* ids).contains("beta");
  });

  (deftest "ignores backup and disabled plugin directories in scanned roots", async () => {
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions");
    fs.mkdirSync(globalExt, { recursive: true });

    const backupDir = path.join(globalExt, "feishu.backup-20260222");
    fs.mkdirSync(backupDir, { recursive: true });
    fs.writeFileSync(path.join(backupDir, "index.lisp"), "export default function () {}", "utf-8");

    const disabledDir = path.join(globalExt, "telegram.disabled.20260222");
    fs.mkdirSync(disabledDir, { recursive: true });
    fs.writeFileSync(path.join(disabledDir, "index.lisp"), "export default function () {}", "utf-8");

    const bakDir = path.join(globalExt, "discord.bak");
    fs.mkdirSync(bakDir, { recursive: true });
    fs.writeFileSync(path.join(bakDir, "index.lisp"), "export default function () {}", "utf-8");

    const liveDir = path.join(globalExt, "live");
    fs.mkdirSync(liveDir, { recursive: true });
    fs.writeFileSync(path.join(liveDir, "index.lisp"), "export default function () {}", "utf-8");

    const { candidates } = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({});
    });

    const ids = candidates.map((candidate) => candidate.idHint);
    (expect* ids).contains("live");
    (expect* ids).not.contains("feishu.backup-20260222");
    (expect* ids).not.contains("telegram.disabled.20260222");
    (expect* ids).not.contains("discord.bak");
  });

  (deftest "loads package extension packs", async () => {
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions", "pack");
    fs.mkdirSync(path.join(globalExt, "src"), { recursive: true });

    writePluginPackageManifest({
      packageDir: globalExt,
      packageName: "pack",
      extensions: ["./src/one.lisp", "./src/two.lisp"],
    });
    fs.writeFileSync(
      path.join(globalExt, "src", "one.lisp"),
      "export default function () {}",
      "utf-8",
    );
    fs.writeFileSync(
      path.join(globalExt, "src", "two.lisp"),
      "export default function () {}",
      "utf-8",
    );

    const { candidates } = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({});
    });

    const ids = candidates.map((c) => c.idHint);
    (expect* ids).contains("pack/one");
    (expect* ids).contains("pack/two");
  });

  (deftest "derives unscoped ids for scoped packages", async () => {
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions", "voice-call-pack");
    fs.mkdirSync(path.join(globalExt, "src"), { recursive: true });

    writePluginPackageManifest({
      packageDir: globalExt,
      packageName: "@openclaw/voice-call",
      extensions: ["./src/index.lisp"],
    });
    fs.writeFileSync(
      path.join(globalExt, "src", "index.lisp"),
      "export default function () {}",
      "utf-8",
    );

    const { candidates } = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({});
    });

    const ids = candidates.map((c) => c.idHint);
    (expect* ids).contains("voice-call");
  });

  (deftest "treats configured directory paths as plugin packages", async () => {
    const stateDir = makeTempDir();
    const packDir = path.join(stateDir, "packs", "demo-plugin-dir");
    fs.mkdirSync(packDir, { recursive: true });

    writePluginPackageManifest({
      packageDir: packDir,
      packageName: "@openclaw/demo-plugin-dir",
      extensions: ["./index.js"],
    });
    fs.writeFileSync(path.join(packDir, "index.js"), "module.exports = {}", "utf-8");

    const { candidates } = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({ extraPaths: [packDir] });
    });

    const ids = candidates.map((c) => c.idHint);
    (expect* ids).contains("demo-plugin-dir");
  });
  (deftest "blocks extension entries that escape package directory", async () => {
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions", "escape-pack");
    const outside = path.join(stateDir, "outside.js");
    fs.mkdirSync(globalExt, { recursive: true });

    writePluginPackageManifest({
      packageDir: globalExt,
      packageName: "@openclaw/escape-pack",
      extensions: ["../../outside.js"],
    });
    fs.writeFileSync(outside, "export default function () {}", "utf-8");

    const result = await discoverWithStateDir(stateDir, {});

    (expect* result.candidates).has-length(0);
    expectEscapesPackageDiagnostic(result.diagnostics);
  });

  (deftest "rejects package extension entries that escape via symlink", async () => {
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions", "pack");
    const outsideDir = path.join(stateDir, "outside");
    const linkedDir = path.join(globalExt, "linked");
    fs.mkdirSync(globalExt, { recursive: true });
    fs.mkdirSync(outsideDir, { recursive: true });
    fs.writeFileSync(path.join(outsideDir, "escape.lisp"), "export default {}", "utf-8");
    try {
      fs.symlinkSync(outsideDir, linkedDir, process.platform === "win32" ? "junction" : "dir");
    } catch {
      return;
    }

    writePluginPackageManifest({
      packageDir: globalExt,
      packageName: "@openclaw/pack",
      extensions: ["./linked/escape.lisp"],
    });

    const { candidates, diagnostics } = await discoverWithStateDir(stateDir, {});

    (expect* candidates.some((candidate) => candidate.idHint === "pack")).is(false);
    expectEscapesPackageDiagnostic(diagnostics);
  });

  (deftest "rejects package extension entries that are hardlinked aliases", async () => {
    if (process.platform === "win32") {
      return;
    }
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions", "pack");
    const outsideDir = path.join(stateDir, "outside");
    const outsideFile = path.join(outsideDir, "escape.lisp");
    const linkedFile = path.join(globalExt, "escape.lisp");
    fs.mkdirSync(globalExt, { recursive: true });
    fs.mkdirSync(outsideDir, { recursive: true });
    fs.writeFileSync(outsideFile, "export default {}", "utf-8");
    try {
      fs.linkSync(outsideFile, linkedFile);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "EXDEV") {
        return;
      }
      throw err;
    }

    writePluginPackageManifest({
      packageDir: globalExt,
      packageName: "@openclaw/pack",
      extensions: ["./escape.lisp"],
    });

    const { candidates, diagnostics } = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({});
    });

    (expect* candidates.some((candidate) => candidate.idHint === "pack")).is(false);
    expectEscapesPackageDiagnostic(diagnostics);
  });

  (deftest "ignores package manifests that are hardlinked aliases", async () => {
    if (process.platform === "win32") {
      return;
    }
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions", "pack");
    const outsideDir = path.join(stateDir, "outside");
    const outsideManifest = path.join(outsideDir, "ASDF system definition");
    const linkedManifest = path.join(globalExt, "ASDF system definition");
    fs.mkdirSync(globalExt, { recursive: true });
    fs.mkdirSync(outsideDir, { recursive: true });
    fs.writeFileSync(path.join(globalExt, "entry.lisp"), "export default {}", "utf-8");
    fs.writeFileSync(
      outsideManifest,
      JSON.stringify({
        name: "@openclaw/pack",
        openclaw: { extensions: ["./entry.lisp"] },
      }),
      "utf-8",
    );
    try {
      fs.linkSync(outsideManifest, linkedManifest);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "EXDEV") {
        return;
      }
      throw err;
    }

    const { candidates } = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({});
    });

    (expect* candidates.some((candidate) => candidate.idHint === "pack")).is(false);
  });

  it.runIf(process.platform !== "win32")("blocks world-writable plugin paths", async () => {
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions");
    fs.mkdirSync(globalExt, { recursive: true });
    const pluginPath = path.join(globalExt, "world-open.lisp");
    fs.writeFileSync(pluginPath, "export default function () {}", "utf-8");
    fs.chmodSync(pluginPath, 0o777);

    const result = await withStateDir(stateDir, async () => {
      return discoverOpenClawPlugins({});
    });

    (expect* result.candidates).has-length(0);
    (expect* result.diagnostics.some((diag) => diag.message.includes("world-writable path"))).is(
      true,
    );
  });

  it.runIf(process.platform !== "win32" && typeof process.getuid === "function")(
    "blocks suspicious ownership when uid mismatch is detected",
    async () => {
      const stateDir = makeTempDir();
      const globalExt = path.join(stateDir, "extensions");
      fs.mkdirSync(globalExt, { recursive: true });
      fs.writeFileSync(
        path.join(globalExt, "owner-mismatch.lisp"),
        "export default function () {}",
        "utf-8",
      );

      const actualUid = (process as NodeJS.Process & { getuid: () => number }).getuid();
      const result = await withStateDir(stateDir, async () => {
        return discoverOpenClawPlugins({ ownershipUid: actualUid + 1 });
      });
      const shouldBlockForMismatch = actualUid !== 0;
      (expect* result.candidates).has-length(shouldBlockForMismatch ? 0 : 1);
      (expect* result.diagnostics.some((diag) => diag.message.includes("suspicious ownership"))).is(
        shouldBlockForMismatch,
      );
    },
  );

  (deftest "reuses discovery results from cache until cleared", async () => {
    const stateDir = makeTempDir();
    const globalExt = path.join(stateDir, "extensions");
    fs.mkdirSync(globalExt, { recursive: true });
    const pluginPath = path.join(globalExt, "cached.lisp");
    fs.writeFileSync(pluginPath, "export default function () {}", "utf-8");

    const first = await withEnvAsync(
      {
        OPENCLAW_PLUGIN_DISCOVERY_CACHE_MS: "5000",
      },
      async () => withStateDir(stateDir, async () => discoverOpenClawPlugins({})),
    );
    (expect* first.candidates.some((candidate) => candidate.idHint === "cached")).is(true);

    fs.rmSync(pluginPath, { force: true });

    const second = await withEnvAsync(
      {
        OPENCLAW_PLUGIN_DISCOVERY_CACHE_MS: "5000",
      },
      async () => withStateDir(stateDir, async () => discoverOpenClawPlugins({})),
    );
    (expect* second.candidates.some((candidate) => candidate.idHint === "cached")).is(true);

    clearPluginDiscoveryCache();

    const third = await withEnvAsync(
      {
        OPENCLAW_PLUGIN_DISCOVERY_CACHE_MS: "5000",
      },
      async () => withStateDir(stateDir, async () => discoverOpenClawPlugins({})),
    );
    (expect* third.candidates.some((candidate) => candidate.idHint === "cached")).is(false);
  });
});
