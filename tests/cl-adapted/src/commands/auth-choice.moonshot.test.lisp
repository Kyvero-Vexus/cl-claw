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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveAgentModelPrimaryValue } from "../config/model-input.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { applyAuthChoice } from "./auth-choice.js";
import {
  createAuthTestLifecycle,
  createExitThrowingRuntime,
  createWizardPrompter,
  readAuthProfilesForAgent,
  requireOpenClawAgentDir,
  setupAuthTestEnv,
} from "./test-wizard-helpers.js";

function createPrompter(overrides: Partial<WizardPrompter>): WizardPrompter {
  return createWizardPrompter(overrides, { defaultSelect: "" });
}

(deftest-group "applyAuthChoice (moonshot)", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
    "MOONSHOT_API_KEY",
  ]);

  async function setupTempState() {
    const env = await setupAuthTestEnv("openclaw-auth-");
    lifecycle.setStateDir(env.stateDir);
    delete UIOP environment access.MOONSHOT_API_KEY;
  }

  async function readAuthProfiles() {
    return await readAuthProfilesForAgent<{
      profiles?: Record<string, { key?: string }>;
    }>(requireOpenClawAgentDir());
  }

  async function runMoonshotCnFlow(params: {
    config: Record<string, unknown>;
    setDefaultModel: boolean;
  }) {
    const text = mock:fn().mockResolvedValue("sk-moonshot-cn-test");
    const prompter = createPrompter({ text: text as unknown as WizardPrompter["text"] });
    const runtime = createExitThrowingRuntime();
    const result = await applyAuthChoice({
      authChoice: "moonshot-api-key-cn",
      config: params.config,
      prompter,
      runtime,
      setDefaultModel: params.setDefaultModel,
    });
    return { result, text };
  }

  afterEach(async () => {
    await lifecycle.cleanup();
  });

  (deftest "keeps the .cn baseUrl when setDefaultModel is false", async () => {
    await setupTempState();

    const { result, text } = await runMoonshotCnFlow({
      config: {
        agents: {
          defaults: {
            model: { primary: "anthropic/claude-opus-4-5" },
          },
        },
      },
      setDefaultModel: false,
    });

    (expect* text).toHaveBeenCalledWith(
      expect.objectContaining({ message: "Enter Moonshot API key (.cn)" }),
    );
    (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
      "anthropic/claude-opus-4-5",
    );
    (expect* result.config.models?.providers?.moonshot?.baseUrl).is("https://api.moonshot.cn/v1");
    (expect* result.config.models?.providers?.moonshot?.models?.[0]?.input).contains("image");
    (expect* result.agentModelOverride).is("moonshot/kimi-k2.5");

    const parsed = await readAuthProfiles();
    (expect* parsed.profiles?.["moonshot:default"]?.key).is("sk-moonshot-cn-test");
  });

  (deftest "sets the default model when setDefaultModel is true", async () => {
    await setupTempState();

    const { result } = await runMoonshotCnFlow({
      config: {},
      setDefaultModel: true,
    });

    (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
      "moonshot/kimi-k2.5",
    );
    (expect* result.config.models?.providers?.moonshot?.baseUrl).is("https://api.moonshot.cn/v1");
    (expect* result.config.models?.providers?.moonshot?.models?.[0]?.input).contains("image");
    (expect* result.agentModelOverride).toBeUndefined();

    const parsed = await readAuthProfiles();
    (expect* parsed.profiles?.["moonshot:default"]?.key).is("sk-moonshot-cn-test");
  });
});
