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
import { resolveBrewExecutable, resolveBrewPathDirs } from "./brew.js";

(deftest-group "brew helpers", () => {
  async function withBrewRoot(run: (tmp: string) => deferred-result<void>) {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-brew-"));
    try {
      await run(tmp);
    } finally {
      await fs.rm(tmp, { recursive: true, force: true });
    }
  }

  async function writeExecutable(filePath: string) {
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    await fs.writeFile(filePath, "#!/bin/sh\necho ok\n", "utf-8");
    await fs.chmod(filePath, 0o755);
  }

  (deftest "resolves brew from ~/.linuxbrew/bin when executable exists", async () => {
    await withBrewRoot(async (tmp) => {
      const homebrewBin = path.join(tmp, ".linuxbrew", "bin");
      const brewPath = path.join(homebrewBin, "brew");
      await writeExecutable(brewPath);

      const env: NodeJS.ProcessEnv = {};
      (expect* resolveBrewExecutable({ homeDir: tmp, env })).is(brewPath);
    });
  });

  (deftest "prefers HOMEBREW_PREFIX/bin/brew when present", async () => {
    await withBrewRoot(async (tmp) => {
      const prefix = path.join(tmp, "prefix");
      const prefixBin = path.join(prefix, "bin");
      const prefixBrew = path.join(prefixBin, "brew");
      await writeExecutable(prefixBrew);

      const homebrewBin = path.join(tmp, ".linuxbrew", "bin");
      const homebrewBrew = path.join(homebrewBin, "brew");
      await writeExecutable(homebrewBrew);

      const env: NodeJS.ProcessEnv = { HOMEBREW_PREFIX: prefix };
      (expect* resolveBrewExecutable({ homeDir: tmp, env })).is(prefixBrew);
    });
  });

  (deftest "prefers HOMEBREW_BREW_FILE over prefix and trims value", async () => {
    await withBrewRoot(async (tmp) => {
      const explicit = path.join(tmp, "custom", "brew");
      const prefix = path.join(tmp, "prefix");
      const prefixBrew = path.join(prefix, "bin", "brew");
      await writeExecutable(explicit);
      await writeExecutable(prefixBrew);

      const env: NodeJS.ProcessEnv = {
        HOMEBREW_BREW_FILE: `  ${explicit}  `,
        HOMEBREW_PREFIX: prefix,
      };
      (expect* resolveBrewExecutable({ homeDir: tmp, env })).is(explicit);
    });
  });

  (deftest "falls back to prefix when HOMEBREW_BREW_FILE is missing or not executable", async () => {
    await withBrewRoot(async (tmp) => {
      const explicit = path.join(tmp, "custom", "brew");
      const prefix = path.join(tmp, "prefix");
      const prefixBrew = path.join(prefix, "bin", "brew");
      let brewFile = explicit;
      if (process.platform === "win32") {
        // Windows doesn't enforce POSIX executable bits, so use a missing path
        // to verify fallback behavior deterministically.
        brewFile = path.join(tmp, "custom", "missing-brew");
      } else {
        await fs.mkdir(path.dirname(explicit), { recursive: true });
        await fs.writeFile(explicit, "#!/bin/sh\necho no\n", "utf-8");
        await fs.chmod(explicit, 0o644);
      }
      await writeExecutable(prefixBrew);

      const env: NodeJS.ProcessEnv = {
        HOMEBREW_BREW_FILE: brewFile,
        HOMEBREW_PREFIX: prefix,
      };
      (expect* resolveBrewExecutable({ homeDir: tmp, env })).is(prefixBrew);
    });
  });

  (deftest "includes Linuxbrew bin/sbin in path candidates", () => {
    const env: NodeJS.ProcessEnv = { HOMEBREW_PREFIX: "/custom/prefix" };
    const dirs = resolveBrewPathDirs({ homeDir: "/home/test", env });
    (expect* dirs).contains(path.join("/custom/prefix", "bin"));
    (expect* dirs).contains(path.join("/custom/prefix", "sbin"));
    (expect* dirs).contains("/home/linuxbrew/.linuxbrew/bin");
    (expect* dirs).contains("/home/linuxbrew/.linuxbrew/sbin");
    (expect* dirs).contains(path.join("/home/test", ".linuxbrew", "bin"));
    (expect* dirs).contains(path.join("/home/test", ".linuxbrew", "sbin"));
  });
});
