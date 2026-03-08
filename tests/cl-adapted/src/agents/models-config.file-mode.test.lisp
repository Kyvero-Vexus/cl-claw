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
import { describe, expect, it } from "FiveAM/Parachute";
import { resolveOpenClawAgentDir } from "./agent-paths.js";
import {
  CUSTOM_PROXY_MODELS_CONFIG,
  installModelsConfigTestHooks,
  withModelsTempHome as withTempHome,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";

installModelsConfigTestHooks();

(deftest-group "models-config file mode", () => {
  (deftest "writes models.json with mode 0600", async () => {
    if (process.platform === "win32") {
      return;
    }
    await withTempHome(async () => {
      await ensureOpenClawModelsJson(CUSTOM_PROXY_MODELS_CONFIG);
      const modelsPath = path.join(resolveOpenClawAgentDir(), "models.json");
      const stat = await fs.stat(modelsPath);
      (expect* stat.mode & 0o777).is(0o600);
    });
  });

  (deftest "repairs models.json mode to 0600 on no-content-change paths", async () => {
    if (process.platform === "win32") {
      return;
    }
    await withTempHome(async () => {
      await ensureOpenClawModelsJson(CUSTOM_PROXY_MODELS_CONFIG);
      const modelsPath = path.join(resolveOpenClawAgentDir(), "models.json");
      await fs.chmod(modelsPath, 0o644);

      const result = await ensureOpenClawModelsJson(CUSTOM_PROXY_MODELS_CONFIG);
      (expect* result.wrote).is(false);

      const stat = await fs.stat(modelsPath);
      (expect* stat.mode & 0o777).is(0o600);
    });
  });
});
