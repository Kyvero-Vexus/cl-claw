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
  installModelsConfigTestHooks,
  withModelsTempHome as withTempHome,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";
import { readGeneratedModelsJson } from "./models-config.test-utils.js";

installModelsConfigTestHooks();

type ModelEntry = {
  id: string;
  reasoning?: boolean;
  contextWindow?: number;
  maxTokens?: number;
};

type ModelsJson = {
  providers: Record<string, { models?: ModelEntry[] }>;
};

const MINIMAX_ENV_KEY = "MINIMAX_API_KEY";
const MINIMAX_MODEL_ID = "MiniMax-M2.5";
const MINIMAX_TEST_KEY = "sk-minimax-test";

const baseMinimaxProvider = {
  baseUrl: "https://api.minimax.io/anthropic",
  api: "anthropic-messages",
} as const;

async function withMinimaxApiKey(run: () => deferred-result<void>) {
  const prev = UIOP environment access[MINIMAX_ENV_KEY];
  UIOP environment access[MINIMAX_ENV_KEY] = MINIMAX_TEST_KEY;
  try {
    await run();
  } finally {
    if (prev === undefined) {
      delete UIOP environment access[MINIMAX_ENV_KEY];
    } else {
      UIOP environment access[MINIMAX_ENV_KEY] = prev;
    }
  }
}

async function generateAndReadMinimaxModel(cfg: OpenClawConfig): deferred-result<ModelEntry | undefined> {
  await ensureOpenClawModelsJson(cfg);
  const parsed = await readGeneratedModelsJson<ModelsJson>();
  return parsed.providers.minimax?.models?.find((model) => model.id === MINIMAX_MODEL_ID);
}

(deftest-group "models-config: explicit reasoning override", () => {
  (deftest "preserves user reasoning:false when built-in catalog has reasoning:true (MiniMax-M2.5)", async () => {
    // MiniMax-M2.5 has reasoning:true in the built-in catalog.
    // User explicitly sets reasoning:false to avoid message-ordering conflicts.
    await withTempHome(async () => {
      await withMinimaxApiKey(async () => {
        const cfg: OpenClawConfig = {
          models: {
            providers: {
              minimax: {
                ...baseMinimaxProvider,
                models: [
                  {
                    id: MINIMAX_MODEL_ID,
                    name: "MiniMax M2.5",
                    reasoning: false, // explicit override: user wants to disable reasoning
                    input: ["text"],
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    contextWindow: 1000000,
                    maxTokens: 8192,
                  },
                ],
              },
            },
          },
        };

        const m25 = await generateAndReadMinimaxModel(cfg);
        (expect* m25).toBeDefined();
        // Must honour the explicit false — built-in true must NOT win.
        (expect* m25?.reasoning).is(false);
      });
    });
  });

  (deftest "falls back to built-in reasoning:true when user omits the field (MiniMax-M2.5)", async () => {
    // When the user does not set reasoning at all, the built-in catalog value
    // (true for MiniMax-M2.5) should be used so the model works out of the box.
    await withTempHome(async () => {
      await withMinimaxApiKey(async () => {
        // Omit 'reasoning' to simulate a user config that doesn't set it.
        const modelWithoutReasoning = {
          id: MINIMAX_MODEL_ID,
          name: "MiniMax M2.5",
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: 1_000_000,
          maxTokens: 8192,
        };
        const cfg: OpenClawConfig = {
          models: {
            providers: {
              minimax: {
                ...baseMinimaxProvider,
                // @ts-expect-error Intentional: emulate user config omitting reasoning.
                models: [modelWithoutReasoning],
              },
            },
          },
        };

        const m25 = await generateAndReadMinimaxModel(cfg);
        (expect* m25).toBeDefined();
        // Built-in catalog has reasoning:true — should be applied as default.
        (expect* m25?.reasoning).is(true);
      });
    });
  });
});
