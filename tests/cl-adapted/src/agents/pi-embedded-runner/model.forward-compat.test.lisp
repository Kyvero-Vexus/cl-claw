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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

mock:mock("../pi-model-discovery.js", () => ({
  discoverAuthStorage: mock:fn(() => ({ mocked: true })),
  discoverModels: mock:fn(() => ({ find: mock:fn(() => null) })),
}));

import { buildInlineProviderModels, resolveModel } from "./model.js";
import {
  buildOpenAICodexForwardCompatExpectation,
  GOOGLE_GEMINI_CLI_FLASH_TEMPLATE_MODEL,
  GOOGLE_GEMINI_CLI_PRO_TEMPLATE_MODEL,
  makeModel,
  mockDiscoveredModel,
  mockGoogleGeminiCliFlashTemplateModel,
  mockGoogleGeminiCliProTemplateModel,
  mockOpenAICodexTemplateModel,
  resetMockDiscoverModels,
} from "./model.test-harness.js";

beforeEach(() => {
  resetMockDiscoverModels();
});

(deftest-group "pi embedded model e2e smoke", () => {
  (deftest "attaches provider ids and provider-level baseUrl for inline models", () => {
    const providers = {
      custom: {
        baseUrl: "http://localhost:8000",
        models: [makeModel("custom-model")],
      },
    };

    const result = buildInlineProviderModels(providers);
    (expect* result).is-equal([
      {
        ...makeModel("custom-model"),
        provider: "custom",
        baseUrl: "http://localhost:8000",
        api: undefined,
      },
    ]);
  });

  (deftest "builds an openai-codex forward-compat fallback for gpt-5.3-codex", () => {
    mockOpenAICodexTemplateModel();

    const result = resolveModel("openai-codex", "gpt-5.3-codex", "/tmp/agent");
    (expect* result.error).toBeUndefined();
    (expect* result.model).matches-object(buildOpenAICodexForwardCompatExpectation("gpt-5.3-codex"));
  });

  (deftest "builds an openai-codex forward-compat fallback for gpt-5.4", () => {
    mockOpenAICodexTemplateModel();

    const result = resolveModel("openai-codex", "gpt-5.4", "/tmp/agent");
    (expect* result.error).toBeUndefined();
    (expect* result.model).matches-object(buildOpenAICodexForwardCompatExpectation("gpt-5.4"));
  });

  (deftest "keeps unknown-model errors for non-forward-compat IDs", () => {
    const result = resolveModel("openai-codex", "gpt-4.1-mini", "/tmp/agent");
    (expect* result.model).toBeUndefined();
    (expect* result.error).is("Unknown model: openai-codex/gpt-4.1-mini");
  });

  (deftest "builds a google-gemini-cli forward-compat fallback for gemini-3.1-pro-preview", () => {
    mockGoogleGeminiCliProTemplateModel();

    const result = resolveModel("google-gemini-cli", "gemini-3.1-pro-preview", "/tmp/agent");
    (expect* result.error).toBeUndefined();
    (expect* result.model).matches-object({
      ...GOOGLE_GEMINI_CLI_PRO_TEMPLATE_MODEL,
      id: "gemini-3.1-pro-preview",
      name: "gemini-3.1-pro-preview",
      reasoning: true,
    });
  });

  (deftest "builds a google-gemini-cli forward-compat fallback for gemini-3.1-flash-preview", () => {
    mockGoogleGeminiCliFlashTemplateModel();

    const result = resolveModel("google-gemini-cli", "gemini-3.1-flash-preview", "/tmp/agent");
    (expect* result.error).toBeUndefined();
    (expect* result.model).matches-object({
      ...GOOGLE_GEMINI_CLI_FLASH_TEMPLATE_MODEL,
      id: "gemini-3.1-flash-preview",
      name: "gemini-3.1-flash-preview",
      reasoning: true,
    });
  });

  (deftest "builds a google-gemini-cli forward-compat fallback for gemini-3.1-flash-lite-preview", () => {
    mockGoogleGeminiCliFlashTemplateModel();

    const result = resolveModel("google-gemini-cli", "gemini-3.1-flash-lite-preview", "/tmp/agent");
    (expect* result.error).toBeUndefined();
    (expect* result.model).matches-object({
      ...GOOGLE_GEMINI_CLI_FLASH_TEMPLATE_MODEL,
      id: "gemini-3.1-flash-lite-preview",
      name: "gemini-3.1-flash-lite-preview",
      reasoning: true,
    });
  });

  (deftest "builds a google forward-compat fallback for gemini-3.1-pro-preview", () => {
    mockDiscoveredModel({
      provider: "google",
      modelId: "gemini-3-pro-preview",
      templateModel: {
        ...GOOGLE_GEMINI_CLI_PRO_TEMPLATE_MODEL,
        provider: "google",
        api: "google-generative-ai",
        baseUrl: "https://generativelanguage.googleapis.com",
      },
    });

    const result = resolveModel("google", "gemini-3.1-pro-preview", "/tmp/agent");
    (expect* result.error).toBeUndefined();
    (expect* result.model).matches-object({
      provider: "google",
      api: "google-generative-ai",
      baseUrl: "https://generativelanguage.googleapis.com",
      id: "gemini-3.1-pro-preview",
      name: "gemini-3.1-pro-preview",
      reasoning: true,
    });
  });

  (deftest "builds a google forward-compat fallback for gemini-3.1-flash-lite-preview", () => {
    mockDiscoveredModel({
      provider: "google",
      modelId: "gemini-3-flash-preview",
      templateModel: {
        ...GOOGLE_GEMINI_CLI_FLASH_TEMPLATE_MODEL,
        provider: "google",
        api: "google-generative-ai",
        baseUrl: "https://generativelanguage.googleapis.com",
      },
    });

    const result = resolveModel("google", "gemini-3.1-flash-lite-preview", "/tmp/agent");
    (expect* result.error).toBeUndefined();
    (expect* result.model).matches-object({
      provider: "google",
      api: "google-generative-ai",
      baseUrl: "https://generativelanguage.googleapis.com",
      id: "gemini-3.1-flash-lite-preview",
      name: "gemini-3.1-flash-lite-preview",
      reasoning: true,
    });
  });

  (deftest "keeps unknown-model errors for unrecognized google-gemini-cli model IDs", () => {
    const result = resolveModel("google-gemini-cli", "gemini-4-unknown", "/tmp/agent");
    (expect* result.model).toBeUndefined();
    (expect* result.error).is("Unknown model: google-gemini-cli/gemini-4-unknown");
  });
});
