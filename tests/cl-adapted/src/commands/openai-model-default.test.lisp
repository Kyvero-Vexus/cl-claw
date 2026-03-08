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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { applyDefaultModelChoice } from "./auth-choice.default-model.js";
import {
  applyGoogleGeminiModelDefault,
  GOOGLE_GEMINI_DEFAULT_MODEL,
} from "./google-gemini-model-default.js";
import {
  applyOpenAICodexModelDefault,
  OPENAI_CODEX_DEFAULT_MODEL,
} from "./openai-codex-model-default.js";
import {
  applyOpenAIConfig,
  applyOpenAIProviderConfig,
  OPENAI_DEFAULT_MODEL,
} from "./openai-model-default.js";
import {
  applyOpencodeZenModelDefault,
  OPENCODE_ZEN_DEFAULT_MODEL,
} from "./opencode-zen-model-default.js";

function makePrompter(): WizardPrompter {
  return {
    intro: async () => {},
    outro: async () => {},
    note: async () => {},
    select: (async <T>() => "" as T) as WizardPrompter["select"],
    multiselect: (async <T>() => [] as T[]) as WizardPrompter["multiselect"],
    text: async () => "",
    confirm: async () => false,
    progress: () => ({ update: () => {}, stop: () => {} }),
  };
}

function expectPrimaryModelChanged(
  applied: { changed: boolean; next: OpenClawConfig },
  primary: string,
) {
  (expect* applied.changed).is(true);
  (expect* applied.next.agents?.defaults?.model).is-equal({ primary });
}

function expectConfigUnchanged(
  applied: { changed: boolean; next: OpenClawConfig },
  cfg: OpenClawConfig,
) {
  (expect* applied.changed).is(false);
  (expect* applied.next).is-equal(cfg);
}

type SharedDefaultModelCase = {
  apply: (cfg: OpenClawConfig) => { changed: boolean; next: OpenClawConfig };
  defaultModel: string;
  overrideConfig: OpenClawConfig;
  alreadyDefaultConfig: OpenClawConfig;
};

const SHARED_DEFAULT_MODEL_CASES: SharedDefaultModelCase[] = [
  {
    apply: applyGoogleGeminiModelDefault,
    defaultModel: GOOGLE_GEMINI_DEFAULT_MODEL,
    overrideConfig: {
      agents: { defaults: { model: { primary: "anthropic/claude-opus-4-5" } } },
    } as OpenClawConfig,
    alreadyDefaultConfig: {
      agents: { defaults: { model: { primary: GOOGLE_GEMINI_DEFAULT_MODEL } } },
    } as OpenClawConfig,
  },
  {
    apply: applyOpencodeZenModelDefault,
    defaultModel: OPENCODE_ZEN_DEFAULT_MODEL,
    overrideConfig: {
      agents: { defaults: { model: "anthropic/claude-opus-4-5" } },
    } as OpenClawConfig,
    alreadyDefaultConfig: {
      agents: { defaults: { model: OPENCODE_ZEN_DEFAULT_MODEL } },
    } as OpenClawConfig,
  },
];

(deftest-group "applyDefaultModelChoice", () => {
  (deftest "ensures allowlist entry exists when returning an agent override", async () => {
    const defaultModel = "vercel-ai-gateway/anthropic/claude-opus-4.6";
    const noteAgentModel = mock:fn(async () => {});
    const applied = await applyDefaultModelChoice({
      config: {},
      setDefaultModel: false,
      defaultModel,
      // Simulate a provider function that does not explicitly add the entry.
      applyProviderConfig: (config: OpenClawConfig) => config,
      applyDefaultConfig: (config: OpenClawConfig) => config,
      noteAgentModel,
      prompter: makePrompter(),
    });

    (expect* noteAgentModel).toHaveBeenCalledWith(defaultModel);
    (expect* applied.agentModelOverride).is(defaultModel);
    (expect* applied.config.agents?.defaults?.models?.[defaultModel]).is-equal({});
  });

  (deftest "adds canonical allowlist key for anthropic aliases", async () => {
    const defaultModel = "anthropic/opus-4.6";
    const applied = await applyDefaultModelChoice({
      config: {},
      setDefaultModel: false,
      defaultModel,
      applyProviderConfig: (config: OpenClawConfig) => config,
      applyDefaultConfig: (config: OpenClawConfig) => config,
      noteAgentModel: async () => {},
      prompter: makePrompter(),
    });

    (expect* applied.config.agents?.defaults?.models?.[defaultModel]).is-equal({});
    (expect* applied.config.agents?.defaults?.models?.["anthropic/claude-opus-4-6"]).is-equal({});
  });

  (deftest "uses applyDefaultConfig path when setDefaultModel is true", async () => {
    const defaultModel = "openai/gpt-5.1-codex";
    const applied = await applyDefaultModelChoice({
      config: {},
      setDefaultModel: true,
      defaultModel,
      applyProviderConfig: (config: OpenClawConfig) => config,
      applyDefaultConfig: () => ({
        agents: {
          defaults: {
            model: { primary: defaultModel },
          },
        },
      }),
      noteDefault: defaultModel,
      noteAgentModel: async () => {},
      prompter: makePrompter(),
    });

    (expect* applied.agentModelOverride).toBeUndefined();
    (expect* applied.config.agents?.defaults?.model).is-equal({ primary: defaultModel });
  });
});

(deftest-group "shared default model behavior", () => {
  (deftest "sets defaults when model is unset", () => {
    for (const testCase of SHARED_DEFAULT_MODEL_CASES) {
      const cfg: OpenClawConfig = { agents: { defaults: {} } };
      const applied = testCase.apply(cfg);
      expectPrimaryModelChanged(applied, testCase.defaultModel);
    }
  });

  (deftest "overrides existing models", () => {
    for (const testCase of SHARED_DEFAULT_MODEL_CASES) {
      const applied = testCase.apply(testCase.overrideConfig);
      expectPrimaryModelChanged(applied, testCase.defaultModel);
    }
  });

  (deftest "no-ops when already on the target default", () => {
    for (const testCase of SHARED_DEFAULT_MODEL_CASES) {
      const applied = testCase.apply(testCase.alreadyDefaultConfig);
      expectConfigUnchanged(applied, testCase.alreadyDefaultConfig);
    }
  });
});

(deftest-group "applyOpenAIProviderConfig", () => {
  (deftest "adds allowlist entry for default model", () => {
    const next = applyOpenAIProviderConfig({});
    (expect* Object.keys(next.agents?.defaults?.models ?? {})).contains(OPENAI_DEFAULT_MODEL);
  });

  (deftest "preserves existing alias for default model", () => {
    const next = applyOpenAIProviderConfig({
      agents: {
        defaults: {
          models: {
            [OPENAI_DEFAULT_MODEL]: { alias: "My GPT" },
          },
        },
      },
    });
    (expect* next.agents?.defaults?.models?.[OPENAI_DEFAULT_MODEL]?.alias).is("My GPT");
  });
});

(deftest-group "applyOpenAIConfig", () => {
  (deftest "sets default when model is unset", () => {
    const next = applyOpenAIConfig({});
    (expect* next.agents?.defaults?.model).is-equal({ primary: OPENAI_DEFAULT_MODEL });
  });

  (deftest "overrides model.primary when model object already exists", () => {
    const next = applyOpenAIConfig({
      agents: { defaults: { model: { primary: "anthropic/claude-opus-4-6", fallbacks: [] } } },
    });
    (expect* next.agents?.defaults?.model).is-equal({ primary: OPENAI_DEFAULT_MODEL, fallbacks: [] });
  });
});

(deftest-group "applyOpenAICodexModelDefault", () => {
  (deftest "sets openai-codex default when model is unset", () => {
    const cfg: OpenClawConfig = { agents: { defaults: {} } };
    const applied = applyOpenAICodexModelDefault(cfg);
    expectPrimaryModelChanged(applied, OPENAI_CODEX_DEFAULT_MODEL);
  });

  (deftest "sets openai-codex default when model is openai/*", () => {
    const cfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: OPENAI_DEFAULT_MODEL } } },
    };
    const applied = applyOpenAICodexModelDefault(cfg);
    expectPrimaryModelChanged(applied, OPENAI_CODEX_DEFAULT_MODEL);
  });

  (deftest "does not override openai-codex/*", () => {
    const cfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: OPENAI_CODEX_DEFAULT_MODEL } } },
    };
    const applied = applyOpenAICodexModelDefault(cfg);
    expectConfigUnchanged(applied, cfg);
  });

  (deftest "does not override non-openai models", () => {
    const cfg: OpenClawConfig = {
      agents: { defaults: { model: { primary: "anthropic/claude-opus-4-5" } } },
    };
    const applied = applyOpenAICodexModelDefault(cfg);
    expectConfigUnchanged(applied, cfg);
  });
});

(deftest-group "applyOpencodeZenModelDefault", () => {
  (deftest "no-ops when already legacy opencode-zen default", () => {
    const cfg = {
      agents: { defaults: { model: "opencode-zen/claude-opus-4-5" } },
    } as OpenClawConfig;
    const applied = applyOpencodeZenModelDefault(cfg);
    expectConfigUnchanged(applied, cfg);
  });

  (deftest "preserves fallbacks when setting primary", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          model: {
            primary: "anthropic/claude-opus-4-5",
            fallbacks: ["google/gemini-3-pro"],
          },
        },
      },
    };
    const applied = applyOpencodeZenModelDefault(cfg);
    (expect* applied.changed).is(true);
    (expect* applied.next.agents?.defaults?.model).is-equal({
      primary: OPENCODE_ZEN_DEFAULT_MODEL,
      fallbacks: ["google/gemini-3-pro"],
    });
  });
});
