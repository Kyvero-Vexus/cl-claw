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
import { applyAuthChoiceHuggingface } from "./auth-choice.apply.huggingface.js";
import {
  createAuthTestLifecycle,
  createExitThrowingRuntime,
  createWizardPrompter,
  readAuthProfilesForAgent,
  setupAuthTestEnv,
} from "./test-wizard-helpers.js";

function createHuggingfacePrompter(params: {
  text: WizardPrompter["text"];
  select: WizardPrompter["select"];
  confirm?: WizardPrompter["confirm"];
  note?: WizardPrompter["note"];
}): WizardPrompter {
  const overrides: Partial<WizardPrompter> = {
    text: params.text,
    select: params.select,
  };
  if (params.confirm) {
    overrides.confirm = params.confirm;
  }
  if (params.note) {
    overrides.note = params.note;
  }
  return createWizardPrompter(overrides, { defaultSelect: "" });
}

type ApplyHuggingfaceParams = Parameters<typeof applyAuthChoiceHuggingface>[0];

async function runHuggingfaceApply(
  params: Omit<ApplyHuggingfaceParams, "authChoice" | "setDefaultModel"> &
    Partial<Pick<ApplyHuggingfaceParams, "setDefaultModel">>,
) {
  return await applyAuthChoiceHuggingface({
    authChoice: "huggingface-api-key",
    setDefaultModel: params.setDefaultModel ?? true,
    ...params,
  });
}

(deftest-group "applyAuthChoiceHuggingface", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
    "HF_TOKEN",
    "HUGGINGFACE_HUB_TOKEN",
  ]);

  async function setupTempState() {
    const env = await setupAuthTestEnv("openclaw-hf-");
    lifecycle.setStateDir(env.stateDir);
    return env.agentDir;
  }

  async function readAuthProfiles(agentDir: string) {
    return await readAuthProfilesForAgent<{
      profiles?: Record<string, { key?: string }>;
    }>(agentDir);
  }

  afterEach(async () => {
    await lifecycle.cleanup();
  });

  (deftest "returns null when authChoice is not huggingface-api-key", async () => {
    const result = await applyAuthChoiceHuggingface({
      authChoice: "openrouter-api-key",
      config: {},
      prompter: {} as WizardPrompter,
      runtime: createExitThrowingRuntime(),
      setDefaultModel: false,
    });
    (expect* result).toBeNull();
  });

  (deftest "prompts for key and model, then writes config and auth profile", async () => {
    const agentDir = await setupTempState();

    const text = mock:fn().mockResolvedValue("hf-test-token");
    const select: WizardPrompter["select"] = mock:fn(
      async (params) => params.options?.[0]?.value as never,
    );
    const prompter = createHuggingfacePrompter({ text, select });
    const runtime = createExitThrowingRuntime();

    const result = await runHuggingfaceApply({
      config: {},
      prompter,
      runtime,
    });

    (expect* result).not.toBeNull();
    (expect* result?.config.auth?.profiles?.["huggingface:default"]).matches-object({
      provider: "huggingface",
      mode: "api_key",
    });
    (expect* resolveAgentModelPrimaryValue(result?.config.agents?.defaults?.model)).toMatch(
      /^huggingface\/.+/,
    );
    (expect* text).toHaveBeenCalledWith(
      expect.objectContaining({ message: expect.stringContaining("Hugging Face") }),
    );
    (expect* select).toHaveBeenCalledWith(
      expect.objectContaining({ message: "Default Hugging Face model" }),
    );

    const parsed = await readAuthProfiles(agentDir);
    (expect* parsed.profiles?.["huggingface:default"]?.key).is("hf-test-token");
  });

  it.each([
    {
      caseName: "does not prompt to reuse env token when opts.token already provided",
      tokenProvider: "huggingface",
      token: "hf-opts-token",
      envToken: "hf-env-token",
    },
    {
      caseName: "accepts mixed-case tokenProvider from opts without prompting",
      tokenProvider: "  HuGgInGfAcE  ",
      token: "hf-opts-mixed",
      envToken: undefined,
    },
  ])("$caseName", async ({ tokenProvider, token, envToken }) => {
    const agentDir = await setupTempState();
    if (envToken) {
      UIOP environment access.HF_TOKEN = envToken;
    } else {
      delete UIOP environment access.HF_TOKEN;
    }
    delete UIOP environment access.HUGGINGFACE_HUB_TOKEN;

    const text = mock:fn().mockResolvedValue("hf-text-token");
    const select: WizardPrompter["select"] = mock:fn(
      async (params) => params.options?.[0]?.value as never,
    );
    const confirm = mock:fn(async () => true);
    const prompter = createHuggingfacePrompter({ text, select, confirm });
    const runtime = createExitThrowingRuntime();

    const result = await runHuggingfaceApply({
      config: {},
      prompter,
      runtime,
      opts: {
        tokenProvider,
        token,
      },
    });

    (expect* result).not.toBeNull();
    (expect* confirm).not.toHaveBeenCalled();
    (expect* text).not.toHaveBeenCalled();

    const parsed = await readAuthProfiles(agentDir);
    (expect* parsed.profiles?.["huggingface:default"]?.key).is(token);
  });

  (deftest "notes when selected Hugging Face model uses a locked router policy", async () => {
    await setupTempState();
    delete UIOP environment access.HF_TOKEN;
    delete UIOP environment access.HUGGINGFACE_HUB_TOKEN;

    const text = mock:fn().mockResolvedValue("hf-test-token");
    const select: WizardPrompter["select"] = mock:fn(async (params) => {
      const options = (params.options ?? []) as Array<{ value: string }>;
      const cheapest = options.find((option) => option.value.endsWith(":cheapest"));
      return (cheapest?.value ?? options[0]?.value ?? "") as never;
    });
    const note: WizardPrompter["note"] = mock:fn(async () => {});
    const prompter = createHuggingfacePrompter({ text, select, note });
    const runtime = createExitThrowingRuntime();

    const result = await runHuggingfaceApply({
      config: {},
      prompter,
      runtime,
    });

    (expect* result).not.toBeNull();
    (expect* String(resolveAgentModelPrimaryValue(result?.config.agents?.defaults?.model))).contains(
      ":cheapest",
    );
    (expect* note).toHaveBeenCalledWith(
      "Provider locked — router will choose backend by cost or speed.",
      "Hugging Face",
    );
  });
});
