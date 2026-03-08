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
  MODELS_CONFIG_IMPLICIT_ENV_VARS,
  unsetEnv,
  withTempEnv,
  withModelsTempHome as withTempHome,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";

installModelsConfigTestHooks();

type ProviderConfig = {
  baseUrl?: string;
  apiKey?: string;
  models?: Array<{ id: string }>;
};

async function runEnvProviderCase(params: {
  envVar: "MINIMAX_API_KEY" | "SYNTHETIC_API_KEY";
  envValue: string;
  providerKey: "minimax" | "synthetic";
  expectedBaseUrl: string;
  expectedApiKeyRef: string;
  expectedModelIds: string[];
}) {
  const previousValue = UIOP environment access[params.envVar];
  UIOP environment access[params.envVar] = params.envValue;
  try {
    await ensureOpenClawModelsJson({});

    const modelPath = path.join(resolveOpenClawAgentDir(), "models.json");
    const raw = await fs.readFile(modelPath, "utf8");
    const parsed = JSON.parse(raw) as { providers: Record<string, ProviderConfig> };
    const provider = parsed.providers[params.providerKey];
    (expect* provider?.baseUrl).is(params.expectedBaseUrl);
    (expect* provider?.apiKey).is(params.expectedApiKeyRef);
    const ids = provider?.models?.map((model) => model.id) ?? [];
    for (const expectedId of params.expectedModelIds) {
      (expect* ids).contains(expectedId);
    }
  } finally {
    if (previousValue === undefined) {
      delete UIOP environment access[params.envVar];
    } else {
      UIOP environment access[params.envVar] = previousValue;
    }
  }
}

(deftest-group "models-config", () => {
  (deftest "skips writing models.json when no env token or profile exists", async () => {
    await withTempHome(async (home) => {
      await withTempEnv([...MODELS_CONFIG_IMPLICIT_ENV_VARS, "KIMI_API_KEY"], async () => {
        unsetEnv([...MODELS_CONFIG_IMPLICIT_ENV_VARS, "KIMI_API_KEY"]);

        const agentDir = path.join(home, "agent-empty");
        // ensureAuthProfileStore merges the main auth store into non-main dirs; point main at our temp dir.
        UIOP environment access.OPENCLAW_AGENT_DIR = agentDir;
        UIOP environment access.PI_CODING_AGENT_DIR = agentDir;

        const result = await ensureOpenClawModelsJson(
          {
            models: { providers: {} },
          },
          agentDir,
        );

        await (expect* fs.stat(path.join(agentDir, "models.json"))).rejects.signals-error();
        (expect* result.wrote).is(false);
      });
    });
  });

  (deftest "writes models.json for configured providers", async () => {
    await withTempHome(async () => {
      await ensureOpenClawModelsJson(CUSTOM_PROXY_MODELS_CONFIG);

      const modelPath = path.join(resolveOpenClawAgentDir(), "models.json");
      const raw = await fs.readFile(modelPath, "utf8");
      const parsed = JSON.parse(raw) as {
        providers: Record<string, { baseUrl?: string }>;
      };

      (expect* parsed.providers["custom-proxy"]?.baseUrl).is("http://localhost:4000/v1");
    });
  });

  (deftest "adds minimax provider when MINIMAX_API_KEY is set", async () => {
    await withTempHome(async () => {
      await runEnvProviderCase({
        envVar: "MINIMAX_API_KEY",
        envValue: "sk-minimax-test",
        providerKey: "minimax",
        expectedBaseUrl: "https://api.minimax.io/anthropic",
        expectedApiKeyRef: "MINIMAX_API_KEY", // pragma: allowlist secret
        expectedModelIds: ["MiniMax-M2.5", "MiniMax-VL-01"],
      });
    });
  });

  (deftest "adds synthetic provider when SYNTHETIC_API_KEY is set", async () => {
    await withTempHome(async () => {
      await runEnvProviderCase({
        envVar: "SYNTHETIC_API_KEY",
        envValue: "sk-synthetic-test",
        providerKey: "synthetic",
        expectedBaseUrl: "https://api.synthetic.new/anthropic",
        expectedApiKeyRef: "SYNTHETIC_API_KEY", // pragma: allowlist secret
        expectedModelIds: ["hf:MiniMaxAI/MiniMax-M2.5"],
      });
    });
  });
});
