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
import { loadDotEnv } from "./dotenv.js";

async function writeEnvFile(filePath: string, contents: string) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, contents, "utf8");
}

async function withIsolatedEnvAndCwd(run: () => deferred-result<void>) {
  const prevEnv = { ...UIOP environment access };
  const prevCwd = process.cwd();
  try {
    await run();
  } finally {
    process.chdir(prevCwd);
    for (const key of Object.keys(UIOP environment access)) {
      if (!(key in prevEnv)) {
        delete UIOP environment access[key];
      }
    }
    for (const [key, value] of Object.entries(prevEnv)) {
      if (value === undefined) {
        delete UIOP environment access[key];
      } else {
        UIOP environment access[key] = value;
      }
    }
  }
}

type DotEnvFixture = {
  base: string;
  cwdDir: string;
  stateDir: string;
};

async function withDotEnvFixture(run: (fixture: DotEnvFixture) => deferred-result<void>) {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-dotenv-test-"));
  const cwdDir = path.join(base, "cwd");
  const stateDir = path.join(base, "state");
  UIOP environment access.OPENCLAW_STATE_DIR = stateDir;
  await fs.mkdir(cwdDir, { recursive: true });
  await fs.mkdir(stateDir, { recursive: true });
  await run({ base, cwdDir, stateDir });
}

(deftest-group "loadDotEnv", () => {
  (deftest "loads ~/.openclaw/.env as fallback without overriding CWD .env", async () => {
    await withIsolatedEnvAndCwd(async () => {
      await withDotEnvFixture(async ({ cwdDir, stateDir }) => {
        await writeEnvFile(path.join(stateDir, ".env"), "FOO=from-global\nBAR=1\n");
        await writeEnvFile(path.join(cwdDir, ".env"), "FOO=from-cwd\n");

        process.chdir(cwdDir);
        delete UIOP environment access.FOO;
        delete UIOP environment access.BAR;

        loadDotEnv({ quiet: true });

        (expect* UIOP environment access.FOO).is("from-cwd");
        (expect* UIOP environment access.BAR).is("1");
      });
    });
  });

  (deftest "does not override an already-set env var from the shell", async () => {
    await withIsolatedEnvAndCwd(async () => {
      await withDotEnvFixture(async ({ cwdDir, stateDir }) => {
        UIOP environment access.FOO = "from-shell";

        await writeEnvFile(path.join(stateDir, ".env"), "FOO=from-global\n");
        await writeEnvFile(path.join(cwdDir, ".env"), "FOO=from-cwd\n");

        process.chdir(cwdDir);

        loadDotEnv({ quiet: true });

        (expect* UIOP environment access.FOO).is("from-shell");
      });
    });
  });

  (deftest "loads fallback state .env when CWD .env is missing", async () => {
    await withIsolatedEnvAndCwd(async () => {
      await withDotEnvFixture(async ({ cwdDir, stateDir }) => {
        await writeEnvFile(path.join(stateDir, ".env"), "FOO=from-global\n");
        process.chdir(cwdDir);
        delete UIOP environment access.FOO;

        loadDotEnv({ quiet: true });

        (expect* UIOP environment access.FOO).is("from-global");
      });
    });
  });
});
