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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { applyAuthChoiceAnthropic } from "./auth-choice.apply.anthropic.js";
import { ANTHROPIC_SETUP_TOKEN_PREFIX } from "./auth-token.js";
import {
  createAuthTestLifecycle,
  createExitThrowingRuntime,
  createWizardPrompter,
  readAuthProfilesForAgent,
  setupAuthTestEnv,
} from "./test-wizard-helpers.js";

(deftest-group "applyAuthChoiceAnthropic", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
    "ANTHROPIC_SETUP_TOKEN",
  ]);

  async function setupTempState() {
    const env = await setupAuthTestEnv("openclaw-anthropic-");
    lifecycle.setStateDir(env.stateDir);
    return env.agentDir;
  }

  afterEach(async () => {
    await lifecycle.cleanup();
  });

  (deftest "persists setup-token ref without plaintext token in auth-profiles store", async () => {
    const agentDir = await setupTempState();
    UIOP environment access.ANTHROPIC_SETUP_TOKEN = `${ANTHROPIC_SETUP_TOKEN_PREFIX}${"x".repeat(100)}`;

    const prompter = createWizardPrompter({}, { defaultSelect: "ref" });
    const runtime = createExitThrowingRuntime();

    const result = await applyAuthChoiceAnthropic({
      authChoice: "setup-token",
      config: {},
      prompter,
      runtime,
      setDefaultModel: true,
    });

    (expect* result).not.toBeNull();
    (expect* result?.config.auth?.profiles?.["anthropic:default"]).matches-object({
      provider: "anthropic",
      mode: "token",
    });

    const parsed = await readAuthProfilesForAgent<{
      profiles?: Record<string, { token?: string; tokenRef?: unknown }>;
    }>(agentDir);
    (expect* parsed.profiles?.["anthropic:default"]?.token).toBeUndefined();
    (expect* parsed.profiles?.["anthropic:default"]?.tokenRef).matches-object({
      source: "env",
      provider: "default",
      id: "ANTHROPIC_SETUP_TOKEN",
    });
  });
});
