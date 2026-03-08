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
import type { OpenClawConfig } from "../config/config.js";
import { resetLogger, setLoggerOverride } from "../logging/logger.js";
import { __setModelCatalogImportForTest, loadModelCatalog } from "./model-catalog.js";
import {
  installModelCatalogTestHooks,
  mockCatalogImportFailThenRecover,
  type PiSdkModule,
} from "./model-catalog.test-harness.js";

function mockPiDiscoveryModels(models: unknown[]) {
  __setModelCatalogImportForTest(
    async () =>
      ({
        discoverAuthStorage: () => ({}),
        AuthStorage: class {},
        ModelRegistry: class {
          getAll() {
            return models;
          }
        },
      }) as unknown as PiSdkModule,
  );
}

function mockSingleOpenAiCatalogModel() {
  mockPiDiscoveryModels([{ id: "gpt-4.1", provider: "openai", name: "GPT-4.1" }]);
}

(deftest-group "loadModelCatalog", () => {
  installModelCatalogTestHooks();

  (deftest "retries after import failure without poisoning the cache", async () => {
    setLoggerOverride({ level: "silent", consoleLevel: "warn" });
    const warnSpy = mock:spyOn(console, "warn").mockImplementation(() => {});
    try {
      const getCallCount = mockCatalogImportFailThenRecover();

      const cfg = {} as OpenClawConfig;
      const first = await loadModelCatalog({ config: cfg });
      (expect* first).is-equal([]);

      const second = await loadModelCatalog({ config: cfg });
      (expect* second).is-equal([{ id: "gpt-4.1", name: "GPT-4.1", provider: "openai" }]);
      (expect* getCallCount()).is(2);
      (expect* warnSpy).toHaveBeenCalledTimes(1);
    } finally {
      setLoggerOverride(null);
      resetLogger();
    }
  });

  (deftest "returns partial results on discovery errors", async () => {
    setLoggerOverride({ level: "silent", consoleLevel: "warn" });
    const warnSpy = mock:spyOn(console, "warn").mockImplementation(() => {});
    try {
      __setModelCatalogImportForTest(
        async () =>
          ({
            discoverAuthStorage: () => ({}),
            AuthStorage: class {},
            ModelRegistry: class {
              getAll() {
                return [
                  { id: "gpt-4.1", name: "GPT-4.1", provider: "openai" },
                  {
                    get id() {
                      error("boom");
                    },
                    provider: "openai",
                    name: "bad",
                  },
                ];
              }
            },
          }) as unknown as PiSdkModule,
      );

      const result = await loadModelCatalog({ config: {} as OpenClawConfig });
      (expect* result).is-equal([{ id: "gpt-4.1", name: "GPT-4.1", provider: "openai" }]);
      (expect* warnSpy).toHaveBeenCalledTimes(1);
    } finally {
      setLoggerOverride(null);
      resetLogger();
    }
  });

  (deftest "adds openai-codex/gpt-5.3-codex-spark when base gpt-5.3-codex exists", async () => {
    mockPiDiscoveryModels([
      {
        id: "gpt-5.3-codex",
        provider: "openai-codex",
        name: "GPT-5.3 Codex",
        reasoning: true,
        contextWindow: 200000,
        input: ["text"],
      },
      {
        id: "gpt-5.2-codex",
        provider: "openai-codex",
        name: "GPT-5.2 Codex",
      },
    ]);

    const result = await loadModelCatalog({ config: {} as OpenClawConfig });
    (expect* result).toContainEqual(
      expect.objectContaining({
        provider: "openai-codex",
        id: "gpt-5.3-codex-spark",
      }),
    );
    const spark = result.find((entry) => entry.id === "gpt-5.3-codex-spark");
    (expect* spark?.name).is("gpt-5.3-codex-spark");
    (expect* spark?.reasoning).is(true);
  });

  (deftest "adds gpt-5.4 forward-compat catalog entries when template models exist", async () => {
    mockPiDiscoveryModels([
      {
        id: "gpt-5.2",
        provider: "openai",
        name: "GPT-5.2",
        reasoning: true,
        contextWindow: 1_050_000,
        input: ["text", "image"],
      },
      {
        id: "gpt-5.2-pro",
        provider: "openai",
        name: "GPT-5.2 Pro",
        reasoning: true,
        contextWindow: 1_050_000,
        input: ["text", "image"],
      },
      {
        id: "gpt-5.3-codex",
        provider: "openai-codex",
        name: "GPT-5.3 Codex",
        reasoning: true,
        contextWindow: 272000,
        input: ["text", "image"],
      },
    ]);

    const result = await loadModelCatalog({ config: {} as OpenClawConfig });

    (expect* result).toContainEqual(
      expect.objectContaining({
        provider: "openai",
        id: "gpt-5.4",
        name: "gpt-5.4",
      }),
    );
    (expect* result).toContainEqual(
      expect.objectContaining({
        provider: "openai",
        id: "gpt-5.4-pro",
        name: "gpt-5.4-pro",
      }),
    );
    (expect* result).toContainEqual(
      expect.objectContaining({
        provider: "openai-codex",
        id: "gpt-5.4",
        name: "gpt-5.4",
      }),
    );
  });

  (deftest "merges configured models for opted-in non-pi-native providers", async () => {
    mockSingleOpenAiCatalogModel();

    const result = await loadModelCatalog({
      config: {
        models: {
          providers: {
            kilocode: {
              baseUrl: "https://api.kilo.ai/api/gateway/",
              api: "openai-completions",
              models: [
                {
                  id: "google/gemini-3-pro-preview",
                  name: "Gemini 3 Pro Preview",
                  input: ["text", "image"],
                  reasoning: true,
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 1048576,
                  maxTokens: 65536,
                },
              ],
            },
          },
        },
      } as OpenClawConfig,
    });

    (expect* result).toContainEqual(
      expect.objectContaining({
        provider: "kilocode",
        id: "google/gemini-3-pro-preview",
        name: "Gemini 3 Pro Preview",
      }),
    );
  });

  (deftest "does not merge configured models for providers that are not opted in", async () => {
    mockSingleOpenAiCatalogModel();

    const result = await loadModelCatalog({
      config: {
        models: {
          providers: {
            qianfan: {
              baseUrl: "https://qianfan.baidubce.com/v2",
              api: "openai-completions",
              models: [
                {
                  id: "deepseek-v3.2",
                  name: "DEEPSEEK V3.2",
                  reasoning: true,
                  input: ["text"],
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 98304,
                  maxTokens: 32768,
                },
              ],
            },
          },
        },
      } as OpenClawConfig,
    });

    (expect* 
      result.some((entry) => entry.provider === "qianfan" && entry.id === "deepseek-v3.2"),
    ).is(false);
  });

  (deftest "does not duplicate opted-in configured models already present in ModelRegistry", async () => {
    mockPiDiscoveryModels([
      {
        id: "kilo/auto",
        provider: "kilocode",
        name: "Kilo Auto",
      },
    ]);

    const result = await loadModelCatalog({
      config: {
        models: {
          providers: {
            kilocode: {
              baseUrl: "https://api.kilo.ai/api/gateway/",
              api: "openai-completions",
              models: [
                {
                  id: "kilo/auto",
                  name: "Configured Kilo Auto",
                  reasoning: true,
                  input: ["text", "image"],
                  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                  contextWindow: 1000000,
                  maxTokens: 128000,
                },
              ],
            },
          },
        },
      } as OpenClawConfig,
    });

    const matches = result.filter(
      (entry) => entry.provider === "kilocode" && entry.id === "kilo/auto",
    );
    (expect* matches).has-length(1);
    (expect* matches[0]?.name).is("Kilo Auto");
  });
});
