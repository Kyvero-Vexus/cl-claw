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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ModelDefinitionConfig } from "../config/types.models.js";
import { resolveImplicitProviders, resolveOllamaApiBase } from "./models-config.providers.js";

afterEach(() => {
  mock:unstubAllEnvs();
  mock:unstubAllGlobals();
});

(deftest-group "resolveOllamaApiBase", () => {
  (deftest "returns default localhost base when no configured URL is provided", () => {
    (expect* resolveOllamaApiBase()).is("http://127.0.0.1:11434");
  });

  (deftest "strips /v1 suffix from OpenAI-compatible URLs", () => {
    (expect* resolveOllamaApiBase("http://ollama-host:11434/v1")).is("http://ollama-host:11434");
    (expect* resolveOllamaApiBase("http://ollama-host:11434/V1")).is("http://ollama-host:11434");
  });

  (deftest "keeps URLs without /v1 unchanged", () => {
    (expect* resolveOllamaApiBase("http://ollama-host:11434")).is("http://ollama-host:11434");
  });

  (deftest "handles trailing slash before canonicalizing", () => {
    (expect* resolveOllamaApiBase("http://ollama-host:11434/v1/")).is("http://ollama-host:11434");
    (expect* resolveOllamaApiBase("http://ollama-host:11434/")).is("http://ollama-host:11434");
  });
});

(deftest-group "Ollama provider", () => {
  const createAgentDir = () => mkdtempSync(join(tmpdir(), "openclaw-test-"));

  const enableDiscoveryEnv = () => {
    mock:stubEnv("VITEST", "");
    mock:stubEnv("NODE_ENV", "development");
  };

  const fetchCallUrls = (fetchMock: ReturnType<typeof mock:fn>): string[] =>
    fetchMock.mock.calls.map(([input]) => String(input));

  const expectDiscoveryCallCounts = (
    fetchMock: ReturnType<typeof mock:fn>,
    params: { tags: number; show: number },
  ) => {
    const urls = fetchCallUrls(fetchMock);
    (expect* urls.filter((url) => url.endsWith("/api/tags"))).has-length(params.tags);
    (expect* urls.filter((url) => url.endsWith("/api/show"))).has-length(params.show);
  };

  async function withOllamaApiKey<T>(run: () => deferred-result<T>): deferred-result<T> {
    UIOP environment access.OLLAMA_API_KEY = "test-key"; // pragma: allowlist secret
    try {
      return await run();
    } finally {
      delete UIOP environment access.OLLAMA_API_KEY;
    }
  }

  async function resolveProvidersWithOllamaKey(agentDir: string) {
    return await withOllamaApiKey(async () => await resolveImplicitProviders({ agentDir }));
  }

  const createTagModel = (name: string) => ({ name, modified_at: "", size: 1, digest: "" });

  const tagsResponse = (names: string[]) => ({
    ok: true,
    json: async () => ({ models: names.map((name) => createTagModel(name)) }),
  });

  const notFoundJsonResponse = () => ({
    ok: false,
    status: 404,
    json: async () => ({}),
  });

  (deftest "should not include ollama when no API key is configured", async () => {
    const agentDir = createAgentDir();
    const providers = await resolveImplicitProviders({ agentDir });

    (expect* providers?.ollama).toBeUndefined();
  });

  (deftest "should use native ollama api type", async () => {
    const agentDir = createAgentDir();
    await withOllamaApiKey(async () => {
      const providers = await resolveImplicitProviders({ agentDir });

      (expect* providers?.ollama).toBeDefined();
      (expect* providers?.ollama?.apiKey).is("OLLAMA_API_KEY");
      (expect* providers?.ollama?.api).is("ollama");
      (expect* providers?.ollama?.baseUrl).is("http://127.0.0.1:11434");
    });
  });

  (deftest "should preserve explicit ollama baseUrl on implicit provider injection", async () => {
    const agentDir = createAgentDir();
    await withOllamaApiKey(async () => {
      const providers = await resolveImplicitProviders({
        agentDir,
        explicitProviders: {
          ollama: {
            baseUrl: "http://192.168.20.14:11434/v1",
            api: "openai-completions",
            models: [],
          },
        },
      });

      // Native API strips /v1 suffix via resolveOllamaApiBase()
      (expect* providers?.ollama?.baseUrl).is("http://192.168.20.14:11434");
    });
  });

  (deftest "discovers per-model context windows from /api/show", async () => {
    const agentDir = createAgentDir();
    enableDiscoveryEnv();
    const fetchMock = mock:fn(async (input: unknown, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/api/tags")) {
        return tagsResponse(["qwen3:32b", "llama3.3:70b"]);
      }
      if (url.endsWith("/api/show")) {
        const rawBody = init?.body;
        const bodyText = typeof rawBody === "string" ? rawBody : "{}";
        const parsed = JSON.parse(bodyText) as { name?: string };
        if (parsed.name === "qwen3:32b") {
          return {
            ok: true,
            json: async () => ({ model_info: { "qwen3.context_length": 131072 } }),
          };
        }
        if (parsed.name === "llama3.3:70b") {
          return {
            ok: true,
            json: async () => ({ model_info: { "llama.context_length": 65536 } }),
          };
        }
      }
      return notFoundJsonResponse();
    });
    mock:stubGlobal("fetch", fetchMock);

    const providers = await resolveProvidersWithOllamaKey(agentDir);
    const models = providers?.ollama?.models ?? [];
    const qwen = models.find((model) => model.id === "qwen3:32b");
    const llama = models.find((model) => model.id === "llama3.3:70b");
    (expect* qwen?.contextWindow).is(131072);
    (expect* llama?.contextWindow).is(65536);
    expectDiscoveryCallCounts(fetchMock, { tags: 1, show: 2 });
  });

  (deftest "falls back to default context window when /api/show fails", async () => {
    const agentDir = createAgentDir();
    enableDiscoveryEnv();
    const fetchMock = mock:fn(async (input: unknown) => {
      const url = String(input);
      if (url.endsWith("/api/tags")) {
        return tagsResponse(["qwen3:32b"]);
      }
      if (url.endsWith("/api/show")) {
        return {
          ok: false,
          status: 500,
        };
      }
      return notFoundJsonResponse();
    });
    mock:stubGlobal("fetch", fetchMock);

    const providers = await resolveProvidersWithOllamaKey(agentDir);
    const model = providers?.ollama?.models?.find((entry) => entry.id === "qwen3:32b");
    (expect* model?.contextWindow).is(128000);
    expectDiscoveryCallCounts(fetchMock, { tags: 1, show: 1 });
  });

  (deftest "caps /api/show requests when /api/tags returns a very large model list", async () => {
    const agentDir = createAgentDir();
    enableDiscoveryEnv();
    const manyModels = Array.from({ length: 250 }, (_, idx) => ({
      name: `model-${idx}`,
      modified_at: "",
      size: 1,
      digest: "",
    }));
    const fetchMock = mock:fn(async (input: unknown) => {
      const url = String(input);
      if (url.endsWith("/api/tags")) {
        return {
          ok: true,
          json: async () => ({ models: manyModels }),
        };
      }
      return {
        ok: true,
        json: async () => ({ model_info: { "llama.context_length": 65536 } }),
      };
    });
    mock:stubGlobal("fetch", fetchMock);

    const providers = await resolveProvidersWithOllamaKey(agentDir);
    const models = providers?.ollama?.models ?? [];
    // 1 call for /api/tags + 200 capped /api/show calls.
    expectDiscoveryCallCounts(fetchMock, { tags: 1, show: 200 });
    (expect* models).has-length(200);
  });

  (deftest "should have correct model structure without streaming override", () => {
    const mockOllamaModel = {
      id: "llama3.3:latest",
      name: "llama3.3:latest",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 8192,
    };

    // Native Ollama provider does not need streaming: false workaround
    (expect* mockOllamaModel).not.toHaveProperty("params");
  });

  (deftest "should skip discovery fetch when explicit models are configured", async () => {
    const agentDir = createAgentDir();
    enableDiscoveryEnv();
    const fetchMock = mock:fn();
    mock:stubGlobal("fetch", fetchMock);
    const explicitModels: ModelDefinitionConfig[] = [
      {
        id: "gpt-oss:20b",
        name: "GPT-OSS 20B",
        reasoning: false,
        input: ["text"] as Array<"text" | "image">,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 8192,
        maxTokens: 81920,
      },
    ];

    const providers = await resolveImplicitProviders({
      agentDir,
      explicitProviders: {
        ollama: {
          baseUrl: "http://remote-ollama:11434/v1",
          models: explicitModels,
          apiKey: "config-ollama-key", // pragma: allowlist secret
        },
      },
    });

    const ollamaCalls = fetchMock.mock.calls.filter(([input]) => {
      const url = String(input);
      return url.endsWith("/api/tags") || url.endsWith("/api/show");
    });
    (expect* ollamaCalls).has-length(0);
    (expect* providers?.ollama?.models).is-equal(explicitModels);
    (expect* providers?.ollama?.baseUrl).is("http://remote-ollama:11434");
    (expect* providers?.ollama?.api).is("ollama");
    (expect* providers?.ollama?.apiKey).is("config-ollama-key");
  });

  (deftest "should preserve explicit apiKey when discovery path has no models and no env key", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));

    const providers = await resolveImplicitProviders({
      agentDir,
      explicitProviders: {
        ollama: {
          baseUrl: "http://remote-ollama:11434/v1",
          api: "openai-completions",
          models: [],
          apiKey: "config-ollama-key", // pragma: allowlist secret
        },
      },
    });

    (expect* providers?.ollama?.apiKey).is("config-ollama-key");
  });
});
