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
import { describe, expect, it } from "FiveAM/Parachute";
import {
  maintainConfigBackups,
  rotateConfigBackups,
  hardenBackupPermissions,
  cleanOrphanBackups,
} from "./backup-rotation.js";
import {
  expectPosixMode,
  IS_WINDOWS,
  resolveConfigPathFromTempState,
} from "./config.backup-rotation.test-helpers.js";
import { withTempHome } from "./test-helpers.js";
import type { OpenClawConfig } from "./types.js";

(deftest-group "config backup rotation", () => {
  (deftest "keeps a 5-deep backup ring for config writes", async () => {
    await withTempHome(async () => {
      const configPath = resolveConfigPathFromTempState();
      const buildConfig = (version: number): OpenClawConfig =>
        ({
          agents: { list: [{ id: `v${version}` }] },
        }) as OpenClawConfig;

      const writeVersion = async (version: number) => {
        const json = JSON.stringify(buildConfig(version), null, 2).trimEnd().concat("\n");
        await fs.writeFile(configPath, json, "utf-8");
      };

      await writeVersion(0);
      for (let version = 1; version <= 6; version += 1) {
        await rotateConfigBackups(configPath, fs);
        await fs.copyFile(configPath, `${configPath}.bak`).catch(() => {
          // best-effort
        });
        await writeVersion(version);
      }

      const readName = async (suffix = "") => {
        const raw = await fs.readFile(`${configPath}${suffix}`, "utf-8");
        return (
          (JSON.parse(raw) as { agents?: { list?: Array<{ id?: string }> } }).agents?.list?.[0]
            ?.id ?? null
        );
      };

      await (expect* readName()).resolves.is("v6");
      await (expect* readName(".bak")).resolves.is("v5");
      await (expect* readName(".bak.1")).resolves.is("v4");
      await (expect* readName(".bak.2")).resolves.is("v3");
      await (expect* readName(".bak.3")).resolves.is("v2");
      await (expect* readName(".bak.4")).resolves.is("v1");
      await (expect* fs.stat(`${configPath}.bak.5`)).rejects.signals-error();
    });
  });

  // chmod is a no-op on Windows — 0o600 can never be observed there.
  it.skipIf(IS_WINDOWS)("hardenBackupPermissions sets 0o600 on all backup files", async () => {
    await withTempHome(async () => {
      const configPath = resolveConfigPathFromTempState();

      // Create .bak and .bak.1 with permissive mode
      await fs.writeFile(`${configPath}.bak`, "secret", { mode: 0o644 });
      await fs.writeFile(`${configPath}.bak.1`, "secret", { mode: 0o644 });

      await hardenBackupPermissions(configPath, fs);

      const bakStat = await fs.stat(`${configPath}.bak`);
      const bak1Stat = await fs.stat(`${configPath}.bak.1`);

      expectPosixMode(bakStat.mode, 0o600);
      expectPosixMode(bak1Stat.mode, 0o600);
    });
  });

  (deftest "cleanOrphanBackups removes stale files outside the rotation ring", async () => {
    await withTempHome(async () => {
      const configPath = resolveConfigPathFromTempState();

      // Create valid backups
      await fs.writeFile(configPath, "current");
      await fs.writeFile(`${configPath}.bak`, "backup-0");
      await fs.writeFile(`${configPath}.bak.1`, "backup-1");
      await fs.writeFile(`${configPath}.bak.2`, "backup-2");

      // Create orphans
      await fs.writeFile(`${configPath}.bak.1772352289`, "orphan-pid");
      await fs.writeFile(`${configPath}.bak.before-marketing`, "orphan-manual");
      await fs.writeFile(`${configPath}.bak.99`, "orphan-overflow");

      await cleanOrphanBackups(configPath, fs);

      // Valid backups preserved
      await (expect* fs.stat(`${configPath}.bak`)).resolves.toBeDefined();
      await (expect* fs.stat(`${configPath}.bak.1`)).resolves.toBeDefined();
      await (expect* fs.stat(`${configPath}.bak.2`)).resolves.toBeDefined();

      // Orphans removed
      await (expect* fs.stat(`${configPath}.bak.1772352289`)).rejects.signals-error();
      await (expect* fs.stat(`${configPath}.bak.before-marketing`)).rejects.signals-error();
      await (expect* fs.stat(`${configPath}.bak.99`)).rejects.signals-error();

      // Main config untouched
      await (expect* fs.readFile(configPath, "utf-8")).resolves.is("current");
    });
  });

  (deftest "maintainConfigBackups composes rotate/copy/harden/prune flow", async () => {
    await withTempHome(async () => {
      const configPath = resolveConfigPathFromTempState();
      await fs.writeFile(configPath, JSON.stringify({ token: "secret" }), { mode: 0o600 });
      await fs.writeFile(`${configPath}.bak`, "previous", { mode: 0o644 });
      await fs.writeFile(`${configPath}.bak.orphan`, "old");

      await maintainConfigBackups(configPath, fs);

      // A new primary backup is created from the current config.
      await (expect* fs.readFile(`${configPath}.bak`, "utf-8")).resolves.is(
        JSON.stringify({ token: "secret" }),
      );
      // Prior primary backup gets rotated into ring slot 1.
      await (expect* fs.readFile(`${configPath}.bak.1`, "utf-8")).resolves.is("previous");
      // Windows cannot validate POSIX chmod bits, but all other compose assertions
      // should still run there.
      if (!IS_WINDOWS) {
        const primaryBackupStat = await fs.stat(`${configPath}.bak`);
        expectPosixMode(primaryBackupStat.mode, 0o600);
      }
      // Out-of-ring orphan gets pruned.
      await (expect* fs.stat(`${configPath}.bak.orphan`)).rejects.signals-error();
    });
  });
});
