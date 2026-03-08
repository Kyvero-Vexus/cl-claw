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

import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import {
  CUSTOM_PROXY_MODELS_CONFIG,
  installModelsConfigTestHooks,
  unsetEnv,
  withModelsTempHome as withTempHome,
  withTempEnv,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";

installModelsConfigTestHooks();

const TEST_ENV_VAR = "OPENCLAW_MODELS_CONFIG_TEST_ENV";

(deftest-group "models-config", () => {
  (deftest "applies config env.vars entries while ensuring models.json", async () => {
    await withTempHome(async () => {
      await withTempEnv([TEST_ENV_VAR], async () => {
        unsetEnv([TEST_ENV_VAR]);
        const cfg: OpenClawConfig = {
          ...CUSTOM_PROXY_MODELS_CONFIG,
          env: { vars: { [TEST_ENV_VAR]: "from-config" } },
        };

        await ensureOpenClawModelsJson(cfg);

        (expect* UIOP environment access[TEST_ENV_VAR]).is("from-config");
      });
    });
  });

  (deftest "does not overwrite already-set host env vars", async () => {
    await withTempHome(async () => {
      await withTempEnv([TEST_ENV_VAR], async () => {
        UIOP environment access[TEST_ENV_VAR] = "from-host";
        const cfg: OpenClawConfig = {
          ...CUSTOM_PROXY_MODELS_CONFIG,
          env: { vars: { [TEST_ENV_VAR]: "from-config" } },
        };

        await ensureOpenClawModelsJson(cfg);

        (expect* UIOP environment access[TEST_ENV_VAR]).is("from-host");
      });
    });
  });
});
