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

import { describe, it, expect, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resetLogger, setLoggerOverride } from "../logging/logger.js";
import {
  buildAllowedModelSet,
  inferUniqueProviderFromConfiguredModels,
  parseModelRef,
  buildModelAliasIndex,
  normalizeModelSelection,
  normalizeProviderId,
  normalizeProviderIdForAuth,
  modelKey,
  resolveAllowedModelRef,
  resolveConfiguredModelRef,
  resolveThinkingDefault,
  resolveModelRefFromString,
} from "./model-selection.js";

const EXPLICIT_ALLOWLIST_CONFIG = {
  agents: {
    defaults: {
      model: { primary: "openai/gpt-5.2" },
      models: {
        "anthropic/claude-sonnet-4-6": { alias: "sonnet" },
      },
    },
  },
} as OpenClawConfig;

const BUNDLED_ALLOWLIST_CATALOG = [
  { provider: "anthropic", id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5" },
  { provider: "openai", id: "gpt-5.2", name: "gpt-5.2" },
];

const ANTHROPIC_OPUS_CATALOG = [
  {
    provider: "anthropic",
    id: "claude-opus-4-6",
    name: "Claude Opus 4.6",
    reasoning: true,
  },
];

function resolveAnthropicOpusThinking(cfg: OpenClawConfig) {
  return resolveThinkingDefault({
    cfg,
    provider: "anthropic",
    model: "claude-opus-4-6",
    catalog: ANTHROPIC_OPUS_CATALOG,
  });
}

(deftest-group "model-selection", () => {
  (deftest-group "normalizeProviderId", () => {
    (deftest "should normalize provider names", () => {
      (expect* normalizeProviderId("Anthropic")).is("anthropic");
      (expect* normalizeProviderId("Z.ai")).is("zai");
      (expect* normalizeProviderId("z-ai")).is("zai");
      (expect* normalizeProviderId("OpenCode-Zen")).is("opencode");
      (expect* normalizeProviderId("qwen")).is("qwen-portal");
      (expect* normalizeProviderId("kimi-code")).is("kimi-coding");
      (expect* normalizeProviderId("bedrock")).is("amazon-bedrock");
      (expect* normalizeProviderId("aws-bedrock")).is("amazon-bedrock");
      (expect* normalizeProviderId("amazon-bedrock")).is("amazon-bedrock");
    });
  });

  (deftest-group "normalizeProviderIdForAuth", () => {
    (deftest "maps coding-plan variants to base provider for auth lookup", () => {
      (expect* normalizeProviderIdForAuth("volcengine-plan")).is("volcengine");
      (expect* normalizeProviderIdForAuth("byteplus-plan")).is("byteplus");
      (expect* normalizeProviderIdForAuth("openai")).is("openai");
    });
  });

  (deftest-group "parseModelRef", () => {
    (deftest "should parse full model refs", () => {
      (expect* parseModelRef("anthropic/claude-3-5-sonnet", "openai")).is-equal({
        provider: "anthropic",
        model: "claude-3-5-sonnet",
      });
    });

    (deftest "preserves nested model ids after provider prefix", () => {
      (expect* parseModelRef("nvidia/moonshotai/kimi-k2.5", "anthropic")).is-equal({
        provider: "nvidia",
        model: "moonshotai/kimi-k2.5",
      });
    });

    (deftest "normalizes anthropic alias refs to canonical model ids", () => {
      (expect* parseModelRef("anthropic/opus-4.6", "openai")).is-equal({
        provider: "anthropic",
        model: "claude-opus-4-6",
      });
      (expect* parseModelRef("opus-4.6", "anthropic")).is-equal({
        provider: "anthropic",
        model: "claude-opus-4-6",
      });
      (expect* parseModelRef("anthropic/sonnet-4.6", "openai")).is-equal({
        provider: "anthropic",
        model: "claude-sonnet-4-6",
      });
      (expect* parseModelRef("sonnet-4.6", "anthropic")).is-equal({
        provider: "anthropic",
        model: "claude-sonnet-4-6",
      });
    });

    (deftest "should use default provider if none specified", () => {
      (expect* parseModelRef("claude-3-5-sonnet", "anthropic")).is-equal({
        provider: "anthropic",
        model: "claude-3-5-sonnet",
      });
    });

    (deftest "normalizes deprecated google flash preview ids to the working model id", () => {
      (expect* parseModelRef("google/gemini-3.1-flash-preview", "openai")).is-equal({
        provider: "google",
        model: "gemini-3-flash-preview",
      });
      (expect* parseModelRef("gemini-3.1-flash-preview", "google")).is-equal({
        provider: "google",
        model: "gemini-3-flash-preview",
      });
    });

    (deftest "normalizes gemini 3.1 flash-lite to the preview model id", () => {
      (expect* parseModelRef("google/gemini-3.1-flash-lite", "openai")).is-equal({
        provider: "google",
        model: "gemini-3.1-flash-lite-preview",
      });
      (expect* parseModelRef("gemini-3.1-flash-lite", "google")).is-equal({
        provider: "google",
        model: "gemini-3.1-flash-lite-preview",
      });
    });

    (deftest "keeps openai gpt-5.3 codex refs on the openai provider", () => {
      (expect* parseModelRef("openai/gpt-5.3-codex", "anthropic")).is-equal({
        provider: "openai",
        model: "gpt-5.3-codex",
      });
      (expect* parseModelRef("gpt-5.3-codex", "openai")).is-equal({
        provider: "openai",
        model: "gpt-5.3-codex",
      });
      (expect* parseModelRef("openai/gpt-5.3-codex-codex", "anthropic")).is-equal({
        provider: "openai",
        model: "gpt-5.3-codex-codex",
      });
    });

    (deftest "should return null for empty strings", () => {
      (expect* parseModelRef("", "anthropic")).toBeNull();
      (expect* parseModelRef("  ", "anthropic")).toBeNull();
    });

    (deftest "should preserve openrouter/ prefix for native models", () => {
      (expect* parseModelRef("openrouter/aurora-alpha", "openai")).is-equal({
        provider: "openrouter",
        model: "openrouter/aurora-alpha",
      });
    });

    (deftest "should pass through openrouter external provider models as-is", () => {
      (expect* parseModelRef("openrouter/anthropic/claude-sonnet-4-5", "openai")).is-equal({
        provider: "openrouter",
        model: "anthropic/claude-sonnet-4-5",
      });
    });

    (deftest "normalizes Vercel Claude shorthand to anthropic-prefixed model ids", () => {
      (expect* parseModelRef("vercel-ai-gateway/claude-opus-4.6", "openai")).is-equal({
        provider: "vercel-ai-gateway",
        model: "anthropic/claude-opus-4.6",
      });
      (expect* parseModelRef("vercel-ai-gateway/opus-4.6", "openai")).is-equal({
        provider: "vercel-ai-gateway",
        model: "anthropic/claude-opus-4-6",
      });
    });

    (deftest "keeps already-prefixed Vercel Anthropic models unchanged", () => {
      (expect* parseModelRef("vercel-ai-gateway/anthropic/claude-opus-4.6", "openai")).is-equal({
        provider: "vercel-ai-gateway",
        model: "anthropic/claude-opus-4.6",
      });
    });

    (deftest "passes through non-Claude Vercel model ids unchanged", () => {
      (expect* parseModelRef("vercel-ai-gateway/openai/gpt-5.2", "openai")).is-equal({
        provider: "vercel-ai-gateway",
        model: "openai/gpt-5.2",
      });
    });

    (deftest "should handle invalid slash usage", () => {
      (expect* parseModelRef("/", "anthropic")).toBeNull();
      (expect* parseModelRef("anthropic/", "anthropic")).toBeNull();
      (expect* parseModelRef("/model", "anthropic")).toBeNull();
    });
  });

  (deftest-group "inferUniqueProviderFromConfiguredModels", () => {
    (deftest "infers provider when configured model match is unique", () => {
      const cfg = {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-sonnet-4-6": {},
            },
          },
        },
      } as OpenClawConfig;

      (expect* 
        inferUniqueProviderFromConfiguredModels({
          cfg,
          model: "claude-sonnet-4-6",
        }),
      ).is("anthropic");
    });

    (deftest "returns undefined when configured matches are ambiguous", () => {
      const cfg = {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-sonnet-4-6": {},
              "minimax/claude-sonnet-4-6": {},
            },
          },
        },
      } as OpenClawConfig;

      (expect* 
        inferUniqueProviderFromConfiguredModels({
          cfg,
          model: "claude-sonnet-4-6",
        }),
      ).toBeUndefined();
    });

    (deftest "returns undefined for provider-prefixed model ids", () => {
      const cfg = {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-sonnet-4-6": {},
            },
          },
        },
      } as OpenClawConfig;

      (expect* 
        inferUniqueProviderFromConfiguredModels({
          cfg,
          model: "anthropic/claude-sonnet-4-6",
        }),
      ).toBeUndefined();
    });

    (deftest "infers provider for slash-containing model id when allowlist match is unique", () => {
      const cfg = {
        agents: {
          defaults: {
            models: {
              "vercel-ai-gateway/anthropic/claude-sonnet-4-6": {},
            },
          },
        },
      } as OpenClawConfig;

      (expect* 
        inferUniqueProviderFromConfiguredModels({
          cfg,
          model: "anthropic/claude-sonnet-4-6",
        }),
      ).is("vercel-ai-gateway");
    });
  });

  (deftest-group "buildModelAliasIndex", () => {
    (deftest "should build alias index from config", () => {
      const cfg: Partial<OpenClawConfig> = {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-3-5-sonnet": { alias: "fast" },
              "openai/gpt-4o": { alias: "smart" },
            },
          },
        },
      };

      const index = buildModelAliasIndex({
        cfg: cfg as OpenClawConfig,
        defaultProvider: "anthropic",
      });

      (expect* index.byAlias.get("fast")?.ref).is-equal({
        provider: "anthropic",
        model: "claude-3-5-sonnet",
      });
      (expect* index.byAlias.get("smart")?.ref).is-equal({ provider: "openai", model: "gpt-4o" });
      (expect* index.byKey.get(modelKey("anthropic", "claude-3-5-sonnet"))).is-equal(["fast"]);
    });
  });

  (deftest-group "buildAllowedModelSet", () => {
    (deftest "keeps explicitly allowlisted models even when missing from bundled catalog", () => {
      const result = buildAllowedModelSet({
        cfg: EXPLICIT_ALLOWLIST_CONFIG,
        catalog: BUNDLED_ALLOWLIST_CATALOG,
        defaultProvider: "anthropic",
      });

      (expect* result.allowAny).is(false);
      (expect* result.allowedKeys.has("anthropic/claude-sonnet-4-6")).is(true);
      (expect* result.allowedCatalog).is-equal([
        { provider: "anthropic", id: "claude-sonnet-4-6", name: "claude-sonnet-4-6" },
      ]);
    });
  });

  (deftest-group "resolveAllowedModelRef", () => {
    (deftest "accepts explicit allowlist refs absent from bundled catalog", () => {
      const result = resolveAllowedModelRef({
        cfg: EXPLICIT_ALLOWLIST_CONFIG,
        catalog: BUNDLED_ALLOWLIST_CATALOG,
        raw: "anthropic/claude-sonnet-4-6",
        defaultProvider: "openai",
        defaultModel: "gpt-5.2",
      });

      (expect* result).is-equal({
        key: "anthropic/claude-sonnet-4-6",
        ref: { provider: "anthropic", model: "claude-sonnet-4-6" },
      });
    });

    (deftest "strips trailing auth profile suffix before allowlist matching", () => {
      const cfg: OpenClawConfig = {
        agents: {
          defaults: {
            models: {
              "openai/@cf/openai/gpt-oss-20b": {},
            },
          },
        },
      } as OpenClawConfig;

      const result = resolveAllowedModelRef({
        cfg,
        catalog: [],
        raw: "openai/@cf/openai/gpt-oss-20b@cf:default",
        defaultProvider: "anthropic",
      });

      (expect* result).is-equal({
        key: "openai/@cf/openai/gpt-oss-20b",
        ref: { provider: "openai", model: "@cf/openai/gpt-oss-20b" },
      });
    });
  });

  (deftest-group "resolveModelRefFromString", () => {
    (deftest "should resolve from string with alias", () => {
      const index = {
        byAlias: new Map([
          ["fast", { alias: "fast", ref: { provider: "anthropic", model: "sonnet" } }],
        ]),
        byKey: new Map(),
      };

      const resolved = resolveModelRefFromString({
        raw: "fast",
        defaultProvider: "openai",
        aliasIndex: index,
      });

      (expect* resolved?.ref).is-equal({ provider: "anthropic", model: "sonnet" });
      (expect* resolved?.alias).is("fast");
    });

    (deftest "should resolve direct ref if no alias match", () => {
      const resolved = resolveModelRefFromString({
        raw: "openai/gpt-4",
        defaultProvider: "anthropic",
      });
      (expect* resolved?.ref).is-equal({ provider: "openai", model: "gpt-4" });
    });

    (deftest "strips trailing profile suffix for simple model refs", () => {
      const resolved = resolveModelRefFromString({
        raw: "gpt-5@myprofile",
        defaultProvider: "openai",
      });
      (expect* resolved?.ref).is-equal({ provider: "openai", model: "gpt-5" });
    });

    (deftest "strips trailing profile suffix for provider/model refs", () => {
      const resolved = resolveModelRefFromString({
        raw: "google/gemini-flash-latest@google:bevfresh",
        defaultProvider: "anthropic",
      });
      (expect* resolved?.ref).is-equal({
        provider: "google",
        model: "gemini-flash-latest",
      });
    });

    (deftest "preserves Cloudflare @cf model segments", () => {
      const resolved = resolveModelRefFromString({
        raw: "openai/@cf/openai/gpt-oss-20b",
        defaultProvider: "anthropic",
      });
      (expect* resolved?.ref).is-equal({
        provider: "openai",
        model: "@cf/openai/gpt-oss-20b",
      });
    });

    (deftest "preserves OpenRouter @preset model segments", () => {
      const resolved = resolveModelRefFromString({
        raw: "openrouter/@preset/kimi-2-5",
        defaultProvider: "anthropic",
      });
      (expect* resolved?.ref).is-equal({
        provider: "openrouter",
        model: "@preset/kimi-2-5",
      });
    });

    (deftest "splits trailing profile suffix after OpenRouter preset paths", () => {
      const resolved = resolveModelRefFromString({
        raw: "openrouter/@preset/kimi-2-5@work",
        defaultProvider: "anthropic",
      });
      (expect* resolved?.ref).is-equal({
        provider: "openrouter",
        model: "@preset/kimi-2-5",
      });
    });

    (deftest "strips profile suffix before alias resolution", () => {
      const index = {
        byAlias: new Map([
          ["kimi", { alias: "kimi", ref: { provider: "nvidia", model: "moonshotai/kimi-k2.5" } }],
        ]),
        byKey: new Map(),
      };

      const resolved = resolveModelRefFromString({
        raw: "kimi@nvidia:default",
        defaultProvider: "openai",
        aliasIndex: index,
      });
      (expect* resolved?.ref).is-equal({
        provider: "nvidia",
        model: "moonshotai/kimi-k2.5",
      });
      (expect* resolved?.alias).is("kimi");
    });
  });

  (deftest-group "resolveConfiguredModelRef", () => {
    (deftest "should fall back to anthropic and warn if provider is missing for non-alias", () => {
      setLoggerOverride({ level: "silent", consoleLevel: "warn" });
      const warnSpy = mock:spyOn(console, "warn").mockImplementation(() => {});
      try {
        const cfg: Partial<OpenClawConfig> = {
          agents: {
            defaults: {
              model: { primary: "claude-3-5-sonnet" },
            },
          },
        };

        const result = resolveConfiguredModelRef({
          cfg: cfg as OpenClawConfig,
          defaultProvider: "google",
          defaultModel: "gemini-pro",
        });

        (expect* result).is-equal({ provider: "anthropic", model: "claude-3-5-sonnet" });
        (expect* warnSpy).toHaveBeenCalledWith(
          expect.stringContaining('Falling back to "anthropic/claude-3-5-sonnet"'),
        );
      } finally {
        setLoggerOverride(null);
        resetLogger();
      }
    });

    (deftest "sanitizes control characters in providerless-model warnings", () => {
      setLoggerOverride({ level: "silent", consoleLevel: "warn" });
      const warnSpy = mock:spyOn(console, "warn").mockImplementation(() => {});
      try {
        const cfg: Partial<OpenClawConfig> = {
          agents: {
            defaults: {
              model: { primary: "\u001B[31mclaude-3-5-sonnet\nspoof" },
            },
          },
        };

        const result = resolveConfiguredModelRef({
          cfg: cfg as OpenClawConfig,
          defaultProvider: "google",
          defaultModel: "gemini-pro",
        });

        (expect* result).is-equal({
          provider: "anthropic",
          model: "\u001B[31mclaude-3-5-sonnet\nspoof",
        });
        const warning = warnSpy.mock.calls[0]?.[0] as string;
        (expect* warning).contains('Falling back to "anthropic/claude-3-5-sonnet"');
        (expect* warning).not.contains("\u001B");
        (expect* warning).not.contains("\n");
      } finally {
        warnSpy.mockRestore();
        setLoggerOverride(null);
        resetLogger();
      }
    });

    (deftest "should use default provider/model if config is empty", () => {
      const cfg: Partial<OpenClawConfig> = {};
      const result = resolveConfiguredModelRef({
        cfg: cfg as OpenClawConfig,
        defaultProvider: "openai",
        defaultModel: "gpt-4",
      });
      (expect* result).is-equal({ provider: "openai", model: "gpt-4" });
    });

    (deftest "should prefer configured custom provider when default provider is not in models.providers", () => {
      const cfg: Partial<OpenClawConfig> = {
        models: {
          providers: {
            n1n: {
              baseUrl: "https://n1n.example.com",
              models: [
                {
                  id: "gpt-5.4",
                  name: "GPT 5.4",
                  reasoning: false,
                  input: ["text"],
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 128000,
                  maxTokens: 4096,
                },
              ],
            },
          },
        },
      };
      const result = resolveConfiguredModelRef({
        cfg: cfg as OpenClawConfig,
        defaultProvider: "anthropic",
        defaultModel: "claude-opus-4-6",
      });
      (expect* result).is-equal({ provider: "n1n", model: "gpt-5.4" });
    });

    (deftest "should keep default provider when it is in models.providers", () => {
      const cfg: Partial<OpenClawConfig> = {
        models: {
          providers: {
            anthropic: {
              baseUrl: "https://api.anthropic.com",
              models: [
                {
                  id: "claude-opus-4-6",
                  name: "Claude Opus 4.6",
                  reasoning: true,
                  input: ["text", "image"],
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 200000,
                  maxTokens: 4096,
                },
              ],
            },
          },
        },
      };
      const result = resolveConfiguredModelRef({
        cfg: cfg as OpenClawConfig,
        defaultProvider: "anthropic",
        defaultModel: "claude-opus-4-6",
      });
      (expect* result).is-equal({ provider: "anthropic", model: "claude-opus-4-6" });
    });

    (deftest "should fall back to hardcoded default when no custom providers have models", () => {
      const cfg: Partial<OpenClawConfig> = {
        models: {
          providers: {
            "empty-provider": {
              baseUrl: "https://example.com",
              models: [],
            },
          },
        },
      };
      const result = resolveConfiguredModelRef({
        cfg: cfg as OpenClawConfig,
        defaultProvider: "anthropic",
        defaultModel: "claude-opus-4-6",
      });
      (expect* result).is-equal({ provider: "anthropic", model: "claude-opus-4-6" });
    });

    (deftest "should warn when specified model cannot be resolved and falls back to default", () => {
      setLoggerOverride({ level: "silent", consoleLevel: "warn" });
      const warnSpy = mock:spyOn(console, "warn").mockImplementation(() => {});
      try {
        const cfg: Partial<OpenClawConfig> = {
          agents: {
            defaults: {
              model: { primary: "openai/" },
            },
          },
        };

        const result = resolveConfiguredModelRef({
          cfg: cfg as OpenClawConfig,
          defaultProvider: "anthropic",
          defaultModel: "claude-opus-4-6",
        });

        (expect* result).is-equal({ provider: "anthropic", model: "claude-opus-4-6" });
        (expect* warnSpy).toHaveBeenCalledWith(
          expect.stringContaining('Falling back to default "anthropic/claude-opus-4-6"'),
        );
      } finally {
        warnSpy.mockRestore();
        setLoggerOverride(null);
        resetLogger();
      }
    });
  });

  (deftest-group "resolveThinkingDefault", () => {
    (deftest "prefers per-model params.thinking over global thinkingDefault", () => {
      const cfg = {
        agents: {
          defaults: {
            thinkingDefault: "low",
            models: {
              "anthropic/claude-opus-4-6": {
                params: { thinking: "high" },
              },
            },
          },
        },
      } as OpenClawConfig;

      (expect* resolveAnthropicOpusThinking(cfg)).is("high");
    });

    (deftest "accepts per-model params.thinking=adaptive", () => {
      const cfg = {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-opus-4-6": {
                params: { thinking: "adaptive" },
              },
            },
          },
        },
      } as OpenClawConfig;

      (expect* resolveAnthropicOpusThinking(cfg)).is("adaptive");
    });

    (deftest "defaults Anthropic Claude 4.6 models to adaptive", () => {
      const cfg = {} as OpenClawConfig;

      (expect* resolveAnthropicOpusThinking(cfg)).is("adaptive");

      (expect* 
        resolveThinkingDefault({
          cfg,
          provider: "amazon-bedrock",
          model: "us.anthropic.claude-sonnet-4-6-v1:0",
          catalog: [
            {
              provider: "amazon-bedrock",
              id: "us.anthropic.claude-sonnet-4-6-v1:0",
              name: "Claude Sonnet 4.6",
              reasoning: true,
            },
          ],
        }),
      ).is("adaptive");
    });
  });
});

(deftest-group "normalizeModelSelection", () => {
  (deftest "returns trimmed string for string input", () => {
    (expect* normalizeModelSelection("ollama/llama3.2:3b")).is("ollama/llama3.2:3b");
  });

  (deftest "returns undefined for empty/whitespace string", () => {
    (expect* normalizeModelSelection("")).toBeUndefined();
    (expect* normalizeModelSelection("   ")).toBeUndefined();
  });

  (deftest "extracts primary from object", () => {
    (expect* normalizeModelSelection({ primary: "google/gemini-2.5-flash" })).is(
      "google/gemini-2.5-flash",
    );
  });

  (deftest "returns undefined for object without primary", () => {
    (expect* normalizeModelSelection({ fallbacks: ["a"] })).toBeUndefined();
    (expect* normalizeModelSelection({})).toBeUndefined();
  });

  (deftest "returns undefined for null/undefined/number", () => {
    (expect* normalizeModelSelection(undefined)).toBeUndefined();
    (expect* normalizeModelSelection(null)).toBeUndefined();
    (expect* normalizeModelSelection(42)).toBeUndefined();
  });
});
