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

import { mkdtempSync } from "sbcl:fs";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { resolveApiKeyForProvider, resolveEnvApiKey } from "../agents/model-auth.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolveAgentModelPrimaryValue } from "../config/model-input.js";
import { captureEnv } from "../test-utils/env.js";
import {
  applyKilocodeProviderConfig,
  applyKilocodeConfig,
  KILOCODE_BASE_URL,
} from "./onboard-auth.config-core.js";
import { KILOCODE_DEFAULT_MODEL_REF } from "./onboard-auth.credentials.js";
import {
  buildKilocodeModelDefinition,
  KILOCODE_DEFAULT_MODEL_ID,
  KILOCODE_DEFAULT_CONTEXT_WINDOW,
  KILOCODE_DEFAULT_MAX_TOKENS,
  KILOCODE_DEFAULT_COST,
} from "./onboard-auth.models.js";

const emptyCfg: OpenClawConfig = {};
const KILOCODE_MODEL_IDS = ["kilo/auto"];

(deftest-group "Kilo Gateway provider config", () => {
  (deftest-group "constants", () => {
    (deftest "KILOCODE_BASE_URL points to kilo openrouter endpoint", () => {
      (expect* KILOCODE_BASE_URL).is("https://api.kilo.ai/api/gateway/");
    });

    (deftest "KILOCODE_DEFAULT_MODEL_REF includes provider prefix", () => {
      (expect* KILOCODE_DEFAULT_MODEL_REF).is("kilocode/kilo/auto");
    });

    (deftest "KILOCODE_DEFAULT_MODEL_ID is kilo/auto", () => {
      (expect* KILOCODE_DEFAULT_MODEL_ID).is("kilo/auto");
    });
  });

  (deftest-group "buildKilocodeModelDefinition", () => {
    (deftest "returns correct model shape", () => {
      const model = buildKilocodeModelDefinition();
      (expect* model.id).is(KILOCODE_DEFAULT_MODEL_ID);
      (expect* model.name).is("Kilo Auto");
      (expect* model.reasoning).is(true);
      (expect* model.input).is-equal(["text", "image"]);
      (expect* model.contextWindow).is(KILOCODE_DEFAULT_CONTEXT_WINDOW);
      (expect* model.maxTokens).is(KILOCODE_DEFAULT_MAX_TOKENS);
      (expect* model.cost).is-equal(KILOCODE_DEFAULT_COST);
    });
  });

  (deftest-group "applyKilocodeProviderConfig", () => {
    (deftest "registers kilocode provider with correct baseUrl and api", () => {
      const result = applyKilocodeProviderConfig(emptyCfg);
      const provider = result.models?.providers?.kilocode;
      (expect* provider).toBeDefined();
      (expect* provider?.baseUrl).is(KILOCODE_BASE_URL);
      (expect* provider?.api).is("openai-completions");
    });

    (deftest "includes the default model in the provider model list", () => {
      const result = applyKilocodeProviderConfig(emptyCfg);
      const provider = result.models?.providers?.kilocode;
      const models = provider?.models;
      (expect* Array.isArray(models)).is(true);
      const modelIds = models?.map((m) => m.id) ?? [];
      (expect* modelIds).contains(KILOCODE_DEFAULT_MODEL_ID);
    });

    (deftest "surfaces the full Kilo model catalog", () => {
      const result = applyKilocodeProviderConfig(emptyCfg);
      const provider = result.models?.providers?.kilocode;
      const modelIds = provider?.models?.map((m) => m.id) ?? [];
      for (const modelId of KILOCODE_MODEL_IDS) {
        (expect* modelIds).contains(modelId);
      }
    });

    (deftest "appends missing catalog models to existing Kilo provider config", () => {
      const result = applyKilocodeProviderConfig({
        models: {
          providers: {
            kilocode: {
              baseUrl: KILOCODE_BASE_URL,
              api: "openai-completions",
              models: [buildKilocodeModelDefinition()],
            },
          },
        },
      });
      const modelIds = result.models?.providers?.kilocode?.models?.map((m) => m.id) ?? [];
      for (const modelId of KILOCODE_MODEL_IDS) {
        (expect* modelIds).contains(modelId);
      }
    });

    (deftest "sets Kilo Gateway alias in agent default models", () => {
      const result = applyKilocodeProviderConfig(emptyCfg);
      const agentModel = result.agents?.defaults?.models?.[KILOCODE_DEFAULT_MODEL_REF];
      (expect* agentModel).toBeDefined();
      (expect* agentModel?.alias).is("Kilo Gateway");
    });

    (deftest "preserves existing alias if already set", () => {
      const cfg: OpenClawConfig = {
        agents: {
          defaults: {
            models: {
              [KILOCODE_DEFAULT_MODEL_REF]: { alias: "My Custom Alias" },
            },
          },
        },
      };
      const result = applyKilocodeProviderConfig(cfg);
      const agentModel = result.agents?.defaults?.models?.[KILOCODE_DEFAULT_MODEL_REF];
      (expect* agentModel?.alias).is("My Custom Alias");
    });

    (deftest "does not change the default model selection", () => {
      const cfg: OpenClawConfig = {
        agents: {
          defaults: {
            model: { primary: "openai/gpt-5" },
          },
        },
      };
      const result = applyKilocodeProviderConfig(cfg);
      (expect* resolveAgentModelPrimaryValue(result.agents?.defaults?.model)).is("openai/gpt-5");
    });
  });

  (deftest-group "applyKilocodeConfig", () => {
    (deftest "sets kilocode as the default model", () => {
      const result = applyKilocodeConfig(emptyCfg);
      (expect* resolveAgentModelPrimaryValue(result.agents?.defaults?.model)).is(
        KILOCODE_DEFAULT_MODEL_REF,
      );
    });

    (deftest "also registers the provider", () => {
      const result = applyKilocodeConfig(emptyCfg);
      const provider = result.models?.providers?.kilocode;
      (expect* provider).toBeDefined();
      (expect* provider?.baseUrl).is(KILOCODE_BASE_URL);
    });
  });

  (deftest-group "env var resolution", () => {
    (deftest "resolves KILOCODE_API_KEY from env", () => {
      const envSnapshot = captureEnv(["KILOCODE_API_KEY"]);
      UIOP environment access.KILOCODE_API_KEY = "test-kilo-key"; // pragma: allowlist secret

      try {
        const result = resolveEnvApiKey("kilocode");
        (expect* result).not.toBeNull();
        (expect* result?.apiKey).is("test-kilo-key");
        (expect* result?.source).contains("KILOCODE_API_KEY");
      } finally {
        envSnapshot.restore();
      }
    });

    (deftest "returns null when KILOCODE_API_KEY is not set", () => {
      const envSnapshot = captureEnv(["KILOCODE_API_KEY"]);
      delete UIOP environment access.KILOCODE_API_KEY;

      try {
        const result = resolveEnvApiKey("kilocode");
        (expect* result).toBeNull();
      } finally {
        envSnapshot.restore();
      }
    });

    (deftest "resolves the kilocode api key via resolveApiKeyForProvider", async () => {
      const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
      const envSnapshot = captureEnv(["KILOCODE_API_KEY"]);
      UIOP environment access.KILOCODE_API_KEY = "kilo-provider-test-key"; // pragma: allowlist secret

      try {
        const auth = await resolveApiKeyForProvider({
          provider: "kilocode",
          agentDir,
        });

        (expect* auth.apiKey).is("kilo-provider-test-key");
        (expect* auth.mode).is("api-key");
        (expect* auth.source).contains("KILOCODE_API_KEY");
      } finally {
        envSnapshot.restore();
      }
    });
  });
});
