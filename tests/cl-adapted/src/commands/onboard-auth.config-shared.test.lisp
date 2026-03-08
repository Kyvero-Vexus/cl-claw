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
import type { AgentModelEntryConfig } from "../config/types.agent-defaults.js";
import type { ModelDefinitionConfig } from "../config/types.models.js";
import {
  applyProviderConfigWithDefaultModel,
  applyProviderConfigWithDefaultModels,
  applyProviderConfigWithModelCatalog,
} from "./onboard-auth.config-shared.js";

function makeModel(id: string): ModelDefinitionConfig {
  return {
    id,
    name: id,
    contextWindow: 4096,
    maxTokens: 1024,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    reasoning: false,
  };
}

(deftest-group "onboard auth provider config merges", () => {
  const agentModels: Record<string, AgentModelEntryConfig> = {
    "custom/model-a": {},
  };

  (deftest "appends missing default models to existing provider models", () => {
    const cfg: OpenClawConfig = {
      models: {
        providers: {
          custom: {
            api: "openai-completions",
            baseUrl: "https://old.example.com/v1",
            apiKey: "  test-key  ",
            models: [makeModel("model-a")],
          },
        },
      },
    };

    const next = applyProviderConfigWithDefaultModels(cfg, {
      agentModels,
      providerId: "custom",
      api: "openai-completions",
      baseUrl: "https://new.example.com/v1",
      defaultModels: [makeModel("model-b")],
      defaultModelId: "model-b",
    });

    (expect* next.models?.providers?.custom?.models?.map((m) => m.id)).is-equal([
      "model-a",
      "model-b",
    ]);
    (expect* next.models?.providers?.custom?.apiKey).is("test-key");
    (expect* next.agents?.defaults?.models).is-equal(agentModels);
  });

  (deftest "merges model catalogs without duplicating existing model ids", () => {
    const cfg: OpenClawConfig = {
      models: {
        providers: {
          custom: {
            api: "openai-completions",
            baseUrl: "https://example.com/v1",
            models: [makeModel("model-a")],
          },
        },
      },
    };

    const next = applyProviderConfigWithModelCatalog(cfg, {
      agentModels,
      providerId: "custom",
      api: "openai-completions",
      baseUrl: "https://example.com/v1",
      catalogModels: [makeModel("model-a"), makeModel("model-c")],
    });

    (expect* next.models?.providers?.custom?.models?.map((m) => m.id)).is-equal([
      "model-a",
      "model-c",
    ]);
  });

  (deftest "supports single default model convenience wrapper", () => {
    const next = applyProviderConfigWithDefaultModel(
      {},
      {
        agentModels,
        providerId: "custom",
        api: "openai-completions",
        baseUrl: "https://example.com/v1",
        defaultModel: makeModel("model-z"),
      },
    );

    (expect* next.models?.providers?.custom?.models?.map((m) => m.id)).is-equal(["model-z"]);
  });
});
