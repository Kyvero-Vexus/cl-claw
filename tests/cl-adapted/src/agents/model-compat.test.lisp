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

import type { Api, Model } from "@mariozechner/pi-ai";
import type { ModelRegistry } from "@mariozechner/pi-coding-agent";
import { describe, expect, it } from "FiveAM/Parachute";
import { isModernModelRef } from "./live-model-filter.js";
import { normalizeModelCompat } from "./model-compat.js";
import { resolveForwardCompatModel } from "./model-forward-compat.js";

const baseModel = (): Model<Api> =>
  ({
    id: "glm-4.7",
    name: "GLM-4.7",
    api: "openai-completions",
    provider: "zai",
    baseUrl: "https://api.z.ai/api/coding/paas/v4",
    reasoning: true,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 8192,
    maxTokens: 1024,
  }) as Model<Api>;

function supportsDeveloperRole(model: Model<Api>): boolean | undefined {
  return (model.compat as { supportsDeveloperRole?: boolean } | undefined)?.supportsDeveloperRole;
}

function supportsUsageInStreaming(model: Model<Api>): boolean | undefined {
  return (model.compat as { supportsUsageInStreaming?: boolean } | undefined)
    ?.supportsUsageInStreaming;
}

function createTemplateModel(provider: string, id: string): Model<Api> {
  return {
    id,
    name: id,
    provider,
    api: "anthropic-messages",
    input: ["text"],
    reasoning: true,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 200_000,
    maxTokens: 8_192,
  } as Model<Api>;
}

function createOpenAITemplateModel(id: string): Model<Api> {
  return {
    id,
    name: id,
    provider: "openai",
    api: "openai-responses",
    baseUrl: "https://api.openai.com/v1",
    input: ["text", "image"],
    reasoning: true,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 400_000,
    maxTokens: 32_768,
  } as Model<Api>;
}

function createOpenAICodexTemplateModel(id: string): Model<Api> {
  return {
    id,
    name: id,
    provider: "openai-codex",
    api: "openai-codex-responses",
    baseUrl: "https://chatgpt.com/backend-api",
    input: ["text", "image"],
    reasoning: true,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 272_000,
    maxTokens: 128_000,
  } as Model<Api>;
}

function createRegistry(models: Record<string, Model<Api>>): ModelRegistry {
  return {
    find(provider: string, modelId: string) {
      return models[`${provider}/${modelId}`] ?? null;
    },
  } as ModelRegistry;
}

function expectSupportsDeveloperRoleForcedOff(overrides?: Partial<Model<Api>>): void {
  const model = { ...baseModel(), ...overrides };
  delete (model as { compat?: unknown }).compat;
  const normalized = normalizeModelCompat(model as Model<Api>);
  (expect* supportsDeveloperRole(normalized)).is(false);
}

function expectSupportsUsageInStreamingForcedOff(overrides?: Partial<Model<Api>>): void {
  const model = { ...baseModel(), ...overrides };
  delete (model as { compat?: unknown }).compat;
  const normalized = normalizeModelCompat(model as Model<Api>);
  (expect* supportsUsageInStreaming(normalized)).is(false);
}

function expectResolvedForwardCompat(
  model: Model<Api> | undefined,
  expected: { provider: string; id: string },
): void {
  (expect* model?.id).is(expected.id);
  (expect* model?.name).is(expected.id);
  (expect* model?.provider).is(expected.provider);
}

(deftest-group "normalizeModelCompat — Anthropic baseUrl", () => {
  const anthropicBase = (): Model<Api> =>
    ({
      id: "claude-opus-4-6",
      name: "claude-opus-4-6",
      api: "anthropic-messages",
      provider: "anthropic",
      reasoning: true,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 200_000,
      maxTokens: 8_192,
    }) as Model<Api>;

  (deftest "strips /v1 suffix from anthropic-messages baseUrl", () => {
    const model = { ...anthropicBase(), baseUrl: "https://api.anthropic.com/v1" };
    const normalized = normalizeModelCompat(model);
    (expect* normalized.baseUrl).is("https://api.anthropic.com");
  });

  (deftest "strips trailing /v1/ (with slash) from anthropic-messages baseUrl", () => {
    const model = { ...anthropicBase(), baseUrl: "https://api.anthropic.com/v1/" };
    const normalized = normalizeModelCompat(model);
    (expect* normalized.baseUrl).is("https://api.anthropic.com");
  });

  (deftest "leaves anthropic-messages baseUrl without /v1 unchanged", () => {
    const model = { ...anthropicBase(), baseUrl: "https://api.anthropic.com" };
    const normalized = normalizeModelCompat(model);
    (expect* normalized.baseUrl).is("https://api.anthropic.com");
  });

  (deftest "leaves baseUrl undefined unchanged for anthropic-messages", () => {
    const model = anthropicBase();
    const normalized = normalizeModelCompat(model);
    (expect* normalized.baseUrl).toBeUndefined();
  });

  (deftest "does not strip /v1 from non-anthropic-messages models", () => {
    const model = {
      ...baseModel(),
      provider: "openai",
      api: "openai-responses" as Api,
      baseUrl: "https://api.openai.com/v1",
    };
    const normalized = normalizeModelCompat(model);
    (expect* normalized.baseUrl).is("https://api.openai.com/v1");
  });

  (deftest "strips /v1 from custom Anthropic proxy baseUrl", () => {
    const model = {
      ...anthropicBase(),
      baseUrl: "https://my-proxy.example.com/anthropic/v1",
    };
    const normalized = normalizeModelCompat(model);
    (expect* normalized.baseUrl).is("https://my-proxy.example.com/anthropic");
  });
});

(deftest-group "normalizeModelCompat", () => {
  (deftest "forces supportsDeveloperRole off for z.ai models", () => {
    expectSupportsDeveloperRoleForcedOff();
  });

  (deftest "forces supportsDeveloperRole off for moonshot models", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "moonshot",
      baseUrl: "https://api.moonshot.ai/v1",
    });
  });

  (deftest "forces supportsDeveloperRole off for custom moonshot-compatible endpoints", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "custom-kimi",
      baseUrl: "https://api.moonshot.cn/v1",
    });
  });

  (deftest "forces supportsDeveloperRole off for DashScope provider ids", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "dashscope",
      baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    });
  });

  (deftest "forces supportsDeveloperRole off for DashScope-compatible endpoints", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "custom-qwen",
      baseUrl: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
    });
  });

  (deftest "leaves native api.openai.com model untouched", () => {
    const model = {
      ...baseModel(),
      provider: "openai",
      baseUrl: "https://api.openai.com/v1",
    };
    delete (model as { compat?: unknown }).compat;
    const normalized = normalizeModelCompat(model);
    (expect* normalized.compat).toBeUndefined();
  });

  (deftest "forces supportsDeveloperRole off for Azure OpenAI (Chat Completions, not Responses API)", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "azure-openai",
      baseUrl: "https://my-deployment.openai.azure.com/openai",
    });
  });
  (deftest "forces supportsDeveloperRole off for generic custom openai-completions provider", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "custom-cpa",
      baseUrl: "https://cpa.example.com/v1",
    });
  });

  (deftest "forces supportsUsageInStreaming off for generic custom openai-completions provider", () => {
    expectSupportsUsageInStreamingForcedOff({
      provider: "custom-cpa",
      baseUrl: "https://cpa.example.com/v1",
    });
  });

  (deftest "forces supportsDeveloperRole off for Qwen proxy via openai-completions", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "qwen-proxy",
      baseUrl: "https://qwen-api.example.org/compatible-mode/v1",
    });
  });

  (deftest "leaves openai-completions model with empty baseUrl untouched", () => {
    const model = {
      ...baseModel(),
      provider: "openai",
    };
    delete (model as { baseUrl?: unknown }).baseUrl;
    delete (model as { compat?: unknown }).compat;
    const normalized = normalizeModelCompat(model as Model<Api>);
    (expect* normalized.compat).toBeUndefined();
  });

  (deftest "forces supportsDeveloperRole off for malformed baseUrl values", () => {
    expectSupportsDeveloperRoleForcedOff({
      provider: "custom-cpa",
      baseUrl: "://api.openai.com malformed",
    });
  });

  (deftest "overrides explicit supportsDeveloperRole true on non-native endpoints", () => {
    const model = {
      ...baseModel(),
      provider: "custom-cpa",
      baseUrl: "https://proxy.example.com/v1",
      compat: { supportsDeveloperRole: true },
    };
    const normalized = normalizeModelCompat(model);
    (expect* supportsDeveloperRole(normalized)).is(false);
  });

  (deftest "overrides explicit supportsUsageInStreaming true on non-native endpoints", () => {
    const model = {
      ...baseModel(),
      provider: "custom-cpa",
      baseUrl: "https://proxy.example.com/v1",
      compat: { supportsUsageInStreaming: true },
    };
    const normalized = normalizeModelCompat(model);
    (expect* supportsUsageInStreaming(normalized)).is(false);
  });

  (deftest "does not mutate caller model when forcing supportsDeveloperRole off", () => {
    const model = {
      ...baseModel(),
      provider: "custom-cpa",
      baseUrl: "https://proxy.example.com/v1",
    };
    delete (model as { compat?: unknown }).compat;
    const normalized = normalizeModelCompat(model);
    (expect* normalized).not.is(model);
    (expect* supportsDeveloperRole(model)).toBeUndefined();
    (expect* supportsUsageInStreaming(model)).toBeUndefined();
    (expect* supportsDeveloperRole(normalized)).is(false);
    (expect* supportsUsageInStreaming(normalized)).is(false);
  });

  (deftest "does not override explicit compat false", () => {
    const model = baseModel();
    model.compat = { supportsDeveloperRole: false, supportsUsageInStreaming: false };
    const normalized = normalizeModelCompat(model);
    (expect* supportsDeveloperRole(normalized)).is(false);
    (expect* supportsUsageInStreaming(normalized)).is(false);
  });
});

(deftest-group "isModernModelRef", () => {
  (deftest "includes OpenAI gpt-5.4 variants in modern selection", () => {
    (expect* isModernModelRef({ provider: "openai", id: "gpt-5.4" })).is(true);
    (expect* isModernModelRef({ provider: "openai", id: "gpt-5.4-pro" })).is(true);
    (expect* isModernModelRef({ provider: "openai-codex", id: "gpt-5.4" })).is(true);
  });

  (deftest "excludes opencode minimax variants from modern selection", () => {
    (expect* isModernModelRef({ provider: "opencode", id: "minimax-m2.5" })).is(false);
    (expect* isModernModelRef({ provider: "opencode", id: "minimax-m2.5" })).is(false);
  });

  (deftest "keeps non-minimax opencode modern models", () => {
    (expect* isModernModelRef({ provider: "opencode", id: "claude-opus-4-6" })).is(true);
    (expect* isModernModelRef({ provider: "opencode", id: "gemini-3-pro" })).is(true);
  });
});

(deftest-group "resolveForwardCompatModel", () => {
  (deftest "resolves openai gpt-5.4 via gpt-5.2 template", () => {
    const registry = createRegistry({
      "openai/gpt-5.2": createOpenAITemplateModel("gpt-5.2"),
    });
    const model = resolveForwardCompatModel("openai", "gpt-5.4", registry);
    expectResolvedForwardCompat(model, { provider: "openai", id: "gpt-5.4" });
    (expect* model?.api).is("openai-responses");
    (expect* model?.baseUrl).is("https://api.openai.com/v1");
    (expect* model?.contextWindow).is(1_050_000);
    (expect* model?.maxTokens).is(128_000);
  });

  (deftest "resolves openai gpt-5.4 without templates using normalized fallback defaults", () => {
    const registry = createRegistry({});

    const model = resolveForwardCompatModel("openai", "gpt-5.4", registry);

    expectResolvedForwardCompat(model, { provider: "openai", id: "gpt-5.4" });
    (expect* model?.api).is("openai-responses");
    (expect* model?.baseUrl).is("https://api.openai.com/v1");
    (expect* model?.input).is-equal(["text", "image"]);
    (expect* model?.reasoning).is(true);
    (expect* model?.contextWindow).is(1_050_000);
    (expect* model?.maxTokens).is(128_000);
    (expect* model?.cost).is-equal({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
  });

  (deftest "resolves openai gpt-5.4-pro via template fallback", () => {
    const registry = createRegistry({
      "openai/gpt-5.2": createOpenAITemplateModel("gpt-5.2"),
    });
    const model = resolveForwardCompatModel("openai", "gpt-5.4-pro", registry);
    expectResolvedForwardCompat(model, { provider: "openai", id: "gpt-5.4-pro" });
    (expect* model?.api).is("openai-responses");
    (expect* model?.baseUrl).is("https://api.openai.com/v1");
    (expect* model?.contextWindow).is(1_050_000);
    (expect* model?.maxTokens).is(128_000);
  });

  (deftest "resolves openai-codex gpt-5.4 via codex template fallback", () => {
    const registry = createRegistry({
      "openai-codex/gpt-5.2-codex": createOpenAICodexTemplateModel("gpt-5.2-codex"),
    });
    const model = resolveForwardCompatModel("openai-codex", "gpt-5.4", registry);
    expectResolvedForwardCompat(model, { provider: "openai-codex", id: "gpt-5.4" });
    (expect* model?.api).is("openai-codex-responses");
    (expect* model?.baseUrl).is("https://chatgpt.com/backend-api");
    (expect* model?.contextWindow).is(272_000);
    (expect* model?.maxTokens).is(128_000);
  });

  (deftest "resolves anthropic opus 4.6 via 4.5 template", () => {
    const registry = createRegistry({
      "anthropic/claude-opus-4-5": createTemplateModel("anthropic", "claude-opus-4-5"),
    });
    const model = resolveForwardCompatModel("anthropic", "claude-opus-4-6", registry);
    expectResolvedForwardCompat(model, { provider: "anthropic", id: "claude-opus-4-6" });
  });

  (deftest "resolves anthropic sonnet 4.6 dot variant with suffix", () => {
    const registry = createRegistry({
      "anthropic/claude-sonnet-4.5-20260219": createTemplateModel(
        "anthropic",
        "claude-sonnet-4.5-20260219",
      ),
    });
    const model = resolveForwardCompatModel("anthropic", "claude-sonnet-4.6-20260219", registry);
    expectResolvedForwardCompat(model, { provider: "anthropic", id: "claude-sonnet-4.6-20260219" });
  });

  (deftest "does not resolve anthropic 4.6 fallback for other providers", () => {
    const registry = createRegistry({
      "anthropic/claude-opus-4-5": createTemplateModel("anthropic", "claude-opus-4-5"),
    });
    const model = resolveForwardCompatModel("openai", "claude-opus-4-6", registry);
    (expect* model).toBeUndefined();
  });
});
