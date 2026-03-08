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
import { DEFAULT_CONTEXT_TOKENS } from "../agents/defaults.js";
import { applyModelDefaults } from "./defaults.js";
import type { OpenClawConfig } from "./types.js";

(deftest-group "applyModelDefaults", () => {
  function buildProxyProviderConfig(overrides?: { contextWindow?: number; maxTokens?: number }) {
    return {
      models: {
        providers: {
          myproxy: {
            baseUrl: "https://proxy.example/v1",
            apiKey: "sk-test",
            api: "openai-completions",
            models: [
              {
                id: "gpt-5.2",
                name: "GPT-5.2",
                reasoning: false,
                input: ["text"],
                cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                contextWindow: overrides?.contextWindow ?? 200_000,
                maxTokens: overrides?.maxTokens ?? 8192,
              },
            ],
          },
        },
      },
    } satisfies OpenClawConfig;
  }

  (deftest "adds default aliases when models are present", () => {
    const cfg = {
      agents: {
        defaults: {
          models: {
            "anthropic/claude-opus-4-6": {},
            "openai/gpt-5.4": {},
          },
        },
      },
    } satisfies OpenClawConfig;
    const next = applyModelDefaults(cfg);

    (expect* next.agents?.defaults?.models?.["anthropic/claude-opus-4-6"]?.alias).is("opus");
    (expect* next.agents?.defaults?.models?.["openai/gpt-5.4"]?.alias).is("gpt");
  });

  (deftest "does not override existing aliases", () => {
    const cfg = {
      agents: {
        defaults: {
          models: {
            "anthropic/claude-opus-4-5": { alias: "Opus" },
          },
        },
      },
    } satisfies OpenClawConfig;

    const next = applyModelDefaults(cfg);

    (expect* next.agents?.defaults?.models?.["anthropic/claude-opus-4-5"]?.alias).is("Opus");
  });

  (deftest "respects explicit empty alias disables", () => {
    const cfg = {
      agents: {
        defaults: {
          models: {
            "google/gemini-3.1-pro-preview": { alias: "" },
            "google/gemini-3-flash-preview": {},
            "google/gemini-3.1-flash-lite-preview": {},
          },
        },
      },
    } satisfies OpenClawConfig;

    const next = applyModelDefaults(cfg);

    (expect* next.agents?.defaults?.models?.["google/gemini-3.1-pro-preview"]?.alias).is("");
    (expect* next.agents?.defaults?.models?.["google/gemini-3-flash-preview"]?.alias).is(
      "gemini-flash",
    );
    (expect* next.agents?.defaults?.models?.["google/gemini-3.1-flash-lite-preview"]?.alias).is(
      "gemini-flash-lite",
    );
  });

  (deftest "fills missing model provider defaults", () => {
    const cfg = buildProxyProviderConfig();

    const next = applyModelDefaults(cfg);
    const model = next.models?.providers?.myproxy?.models?.[0];

    (expect* model?.reasoning).is(false);
    (expect* model?.input).is-equal(["text"]);
    (expect* model?.cost).is-equal({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
    (expect* model?.contextWindow).is(DEFAULT_CONTEXT_TOKENS);
    (expect* model?.maxTokens).is(8192);
  });

  (deftest "clamps maxTokens to contextWindow", () => {
    const cfg = buildProxyProviderConfig({ contextWindow: 32768, maxTokens: 40960 });

    const next = applyModelDefaults(cfg);
    const model = next.models?.providers?.myproxy?.models?.[0];

    (expect* model?.contextWindow).is(32768);
    (expect* model?.maxTokens).is(32768);
  });

  (deftest "defaults anthropic provider and model api to anthropic-messages", () => {
    const cfg = {
      models: {
        providers: {
          anthropic: {
            baseUrl: "https://relay.example.com/api",
            apiKey: "cr_xxxx", // pragma: allowlist secret
            models: [
              {
                id: "claude-opus-4-6",
                name: "Claude Opus 4.6",
                reasoning: false,
                input: ["text"],
                cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                contextWindow: 200_000,
                maxTokens: 8192,
              },
            ],
          },
        },
      },
    } satisfies OpenClawConfig;

    const next = applyModelDefaults(cfg);
    const provider = next.models?.providers?.anthropic;
    const model = provider?.models?.[0];

    (expect* provider?.api).is("anthropic-messages");
    (expect* model?.api).is("anthropic-messages");
  });

  (deftest "propagates provider api to models when model api is missing", () => {
    const cfg = buildProxyProviderConfig();

    const next = applyModelDefaults(cfg);
    const model = next.models?.providers?.myproxy?.models?.[0];
    (expect* model?.api).is("openai-completions");
  });
});
