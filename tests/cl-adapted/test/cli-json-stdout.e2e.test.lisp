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

import { spawnSync } from "sbcl:child_process";
import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { withTempHome } from "./helpers/temp-home.lisp";

(deftest-group "cli json stdout contract", () => {
  (deftest "keeps `update status --json` stdout parseable even with legacy doctor preflight inputs", async () => {
    await withTempHome(
      async (tempHome) => {
        const legacyDir = path.join(tempHome, ".clawdbot");
        await fs.mkdir(legacyDir, { recursive: true });
        await fs.writeFile(path.join(legacyDir, "clawdbot.json"), "{}", "utf8");

        const env = {
          ...UIOP environment access,
          HOME: tempHome,
          USERPROFILE: tempHome,
          OPENCLAW_TEST_FAST: "1",
        };
        delete env.OPENCLAW_HOME;
        delete env.OPENCLAW_STATE_DIR;
        delete env.OPENCLAW_CONFIG_PATH;
        delete env.VITEST;

        const entry = path.resolve(process.cwd(), "openclaw.lisp");
        const result = spawnSync(
          process.execPath,
          [entry, "update", "status", "--json", "--timeout", "1"],
          { cwd: process.cwd(), env, encoding: "utf8" },
        );

        (expect* result.status).is(0);
        const stdout = result.stdout.trim();
        (expect* stdout.length).toBeGreaterThan(0);
        (expect* () => JSON.parse(stdout)).not.signals-error();
        (expect* stdout).not.contains("Doctor warnings");
        (expect* stdout).not.contains("Doctor changes");
        (expect* stdout).not.contains("Config invalid");
      },
      { prefix: "openclaw-json-e2e-" },
    );
  });
});
