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

import type { BedrockClient } from "@aws-sdk/client-bedrock";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const sendMock = mock:fn();
const clientFactory = () => ({ send: sendMock }) as unknown as BedrockClient;

const baseActiveAnthropicSummary = {
  modelId: "anthropic.claude-3-7-sonnet-20250219-v1:0",
  modelName: "Claude 3.7 Sonnet",
  providerName: "anthropic",
  inputModalities: ["TEXT"],
  outputModalities: ["TEXT"],
  responseStreamingSupported: true,
  modelLifecycle: { status: "ACTIVE" },
};

async function loadDiscovery() {
  const mod = await import("./bedrock-discovery.js");
  mod.resetBedrockDiscoveryCacheForTest();
  return mod;
}

function mockSingleActiveSummary(overrides: Partial<typeof baseActiveAnthropicSummary> = {}): void {
  sendMock.mockResolvedValueOnce({
    modelSummaries: [{ ...baseActiveAnthropicSummary, ...overrides }],
  });
}

(deftest-group "bedrock discovery", () => {
  beforeEach(() => {
    sendMock.mockClear();
  });

  (deftest "filters to active streaming text models and maps modalities", async () => {
    const { discoverBedrockModels } = await loadDiscovery();

    sendMock.mockResolvedValueOnce({
      modelSummaries: [
        {
          modelId: "anthropic.claude-3-7-sonnet-20250219-v1:0",
          modelName: "Claude 3.7 Sonnet",
          providerName: "anthropic",
          inputModalities: ["TEXT", "IMAGE"],
          outputModalities: ["TEXT"],
          responseStreamingSupported: true,
          modelLifecycle: { status: "ACTIVE" },
        },
        {
          modelId: "anthropic.claude-3-haiku-20240307-v1:0",
          modelName: "Claude 3 Haiku",
          providerName: "anthropic",
          inputModalities: ["TEXT"],
          outputModalities: ["TEXT"],
          responseStreamingSupported: false,
          modelLifecycle: { status: "ACTIVE" },
        },
        {
          modelId: "meta.llama3-8b-instruct-v1:0",
          modelName: "Llama 3 8B",
          providerName: "meta",
          inputModalities: ["TEXT"],
          outputModalities: ["TEXT"],
          responseStreamingSupported: true,
          modelLifecycle: { status: "INACTIVE" },
        },
        {
          modelId: "amazon.titan-embed-text-v1",
          modelName: "Titan Embed",
          providerName: "amazon",
          inputModalities: ["TEXT"],
          outputModalities: ["EMBEDDING"],
          responseStreamingSupported: true,
          modelLifecycle: { status: "ACTIVE" },
        },
      ],
    });

    const models = await discoverBedrockModels({ region: "us-east-1", clientFactory });
    (expect* models).has-length(1);
    (expect* models[0]).matches-object({
      id: "anthropic.claude-3-7-sonnet-20250219-v1:0",
      name: "Claude 3.7 Sonnet",
      reasoning: false,
      input: ["text", "image"],
      contextWindow: 32000,
      maxTokens: 4096,
    });
  });

  (deftest "applies provider filter", async () => {
    const { discoverBedrockModels } = await loadDiscovery();
    mockSingleActiveSummary();

    const models = await discoverBedrockModels({
      region: "us-east-1",
      config: { providerFilter: ["amazon"] },
      clientFactory,
    });
    (expect* models).has-length(0);
  });

  (deftest "uses configured defaults for context and max tokens", async () => {
    const { discoverBedrockModels } = await loadDiscovery();
    mockSingleActiveSummary();

    const models = await discoverBedrockModels({
      region: "us-east-1",
      config: { defaultContextWindow: 64000, defaultMaxTokens: 8192 },
      clientFactory,
    });
    (expect* models[0]).matches-object({ contextWindow: 64000, maxTokens: 8192 });
  });

  (deftest "caches results when refreshInterval is enabled", async () => {
    const { discoverBedrockModels } = await loadDiscovery();
    mockSingleActiveSummary();

    await discoverBedrockModels({ region: "us-east-1", clientFactory });
    await discoverBedrockModels({ region: "us-east-1", clientFactory });
    (expect* sendMock).toHaveBeenCalledTimes(1);
  });

  (deftest "skips cache when refreshInterval is 0", async () => {
    const { discoverBedrockModels } = await loadDiscovery();

    sendMock
      .mockResolvedValueOnce({ modelSummaries: [baseActiveAnthropicSummary] })
      .mockResolvedValueOnce({ modelSummaries: [baseActiveAnthropicSummary] });

    await discoverBedrockModels({
      region: "us-east-1",
      config: { refreshInterval: 0 },
      clientFactory,
    });
    await discoverBedrockModels({
      region: "us-east-1",
      config: { refreshInterval: 0 },
      clientFactory,
    });
    (expect* sendMock).toHaveBeenCalledTimes(2);
  });
});
