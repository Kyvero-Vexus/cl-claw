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
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";

const mocks = mock:hoisted(() => ({
  promptAuthChoiceGrouped: mock:fn(),
  applyAuthChoice: mock:fn(),
  promptModelAllowlist: mock:fn(),
  promptDefaultModel: mock:fn(),
  promptCustomApiConfig: mock:fn(),
}));

mock:mock("../agents/auth-profiles.js", () => ({
  ensureAuthProfileStore: mock:fn(() => ({
    version: 1,
    profiles: {},
  })),
}));

mock:mock("./auth-choice-prompt.js", () => ({
  promptAuthChoiceGrouped: mocks.promptAuthChoiceGrouped,
}));

mock:mock("./auth-choice.js", () => ({
  applyAuthChoice: mocks.applyAuthChoice,
  resolvePreferredProviderForAuthChoice: mock:fn(() => undefined),
}));

mock:mock("./model-picker.js", async (importActual) => {
  const actual = await importActual<typeof import("./model-picker.js")>();
  return {
    ...actual,
    promptModelAllowlist: mocks.promptModelAllowlist,
    promptDefaultModel: mocks.promptDefaultModel,
  };
});

mock:mock("./onboard-custom.js", () => ({
  promptCustomApiConfig: mocks.promptCustomApiConfig,
}));

import { promptAuthConfig } from "./configure.gateway-auth.js";

function makeRuntime(): RuntimeEnv {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

const noopPrompter = {} as WizardPrompter;

function createKilocodeProvider() {
  return {
    baseUrl: "https://api.kilo.ai/api/gateway/",
    api: "openai-completions",
    models: [
      { id: "kilo/auto", name: "Kilo Auto" },
      { id: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4" },
    ],
  };
}

function createApplyAuthChoiceConfig(includeMinimaxProvider = false) {
  return {
    config: {
      agents: {
        defaults: {
          model: { primary: "kilocode/kilo/auto" },
        },
      },
      models: {
        providers: {
          kilocode: createKilocodeProvider(),
          ...(includeMinimaxProvider
            ? {
                minimax: {
                  baseUrl: "https://api.minimax.io/anthropic",
                  api: "anthropic-messages",
                  models: [{ id: "MiniMax-M2.5", name: "MiniMax M2.5" }],
                },
              }
            : {}),
        },
      },
    },
  };
}

async function runPromptAuthConfigWithAllowlist(includeMinimaxProvider = false) {
  mocks.promptAuthChoiceGrouped.mockResolvedValue("kilocode-api-key");
  mocks.applyAuthChoice.mockResolvedValue(createApplyAuthChoiceConfig(includeMinimaxProvider));
  mocks.promptModelAllowlist.mockResolvedValue({
    models: ["kilocode/kilo/auto"],
  });

  return promptAuthConfig({}, makeRuntime(), noopPrompter);
}

(deftest-group "promptAuthConfig", () => {
  (deftest "keeps Kilo provider models while applying allowlist defaults", async () => {
    const result = await runPromptAuthConfigWithAllowlist();
    (expect* result.models?.providers?.kilocode?.models?.map((model) => model.id)).is-equal([
      "kilo/auto",
      "anthropic/claude-sonnet-4",
    ]);
    (expect* Object.keys(result.agents?.defaults?.models ?? {})).is-equal(["kilocode/kilo/auto"]);
  });

  (deftest "does not mutate provider model catalogs when allowlist is set", async () => {
    const result = await runPromptAuthConfigWithAllowlist(true);
    (expect* result.models?.providers?.kilocode?.models?.map((model) => model.id)).is-equal([
      "kilo/auto",
      "anthropic/claude-sonnet-4",
    ]);
    (expect* result.models?.providers?.minimax?.models?.map((model) => model.id)).is-equal([
      "MiniMax-M2.5",
    ]);
  });
});
