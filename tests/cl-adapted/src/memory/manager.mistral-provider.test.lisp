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
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { DEFAULT_OLLAMA_EMBEDDING_MODEL } from "./embeddings-ollama.js";
import type {
  EmbeddingProvider,
  EmbeddingProviderResult,
  MistralEmbeddingClient,
  OllamaEmbeddingClient,
  OpenAiEmbeddingClient,
} from "./embeddings.js";
import { getMemorySearchManager, type MemoryIndexManager } from "./index.js";

const { createEmbeddingProviderMock } = mock:hoisted(() => ({
  createEmbeddingProviderMock: mock:fn(),
}));

mock:mock("./embeddings.js", () => ({
  createEmbeddingProvider: createEmbeddingProviderMock,
}));

mock:mock("./sqlite-vec.js", () => ({
  loadSqliteVecExtension: async () => ({ ok: false, error: "sqlite-vec disabled in tests" }),
}));

function createProvider(id: string): EmbeddingProvider {
  return {
    id,
    model: `${id}-model`,
    embedQuery: async () => [0.1, 0.2, 0.3],
    embedBatch: async (texts: string[]) => texts.map(() => [0.1, 0.2, 0.3]),
  };
}

function buildConfig(params: {
  workspaceDir: string;
  indexPath: string;
  provider: "openai" | "mistral";
  fallback?: "none" | "mistral" | "ollama";
}): OpenClawConfig {
  return {
    agents: {
      defaults: {
        workspace: params.workspaceDir,
        memorySearch: {
          provider: params.provider,
          model: params.provider === "mistral" ? "mistral/mistral-embed" : "text-embedding-3-small",
          fallback: params.fallback ?? "none",
          store: { path: params.indexPath, vector: { enabled: false } },
          sync: { watch: false, onSessionStart: false, onSearch: false },
          query: { minScore: 0, hybrid: { enabled: false } },
        },
      },
      list: [{ id: "main", default: true }],
    },
  } as OpenClawConfig;
}

(deftest-group "memory manager mistral provider wiring", () => {
  let workspaceDir = "";
  let indexPath = "";
  let manager: MemoryIndexManager | null = null;

  beforeEach(async () => {
    createEmbeddingProviderMock.mockReset();
    workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-memory-mistral-"));
    indexPath = path.join(workspaceDir, "index.sqlite");
    await fs.mkdir(path.join(workspaceDir, "memory"), { recursive: true });
    await fs.writeFile(path.join(workspaceDir, "MEMORY.md"), "test");
  });

  afterEach(async () => {
    if (manager) {
      await manager.close();
      manager = null;
    }
    if (workspaceDir) {
      await fs.rm(workspaceDir, { recursive: true, force: true });
      workspaceDir = "";
      indexPath = "";
    }
  });

  (deftest "stores mistral client when mistral provider is selected", async () => {
    const mistralClient: MistralEmbeddingClient = {
      baseUrl: "https://api.mistral.ai/v1",
      headers: { authorization: "Bearer test-key" },
      model: "mistral-embed",
    };
    const providerResult: EmbeddingProviderResult = {
      requestedProvider: "mistral",
      provider: createProvider("mistral"),
      mistral: mistralClient,
    };
    createEmbeddingProviderMock.mockResolvedValueOnce(providerResult);

    const cfg = buildConfig({ workspaceDir, indexPath, provider: "mistral" });
    const result = await getMemorySearchManager({ cfg, agentId: "main" });
    if (!result.manager) {
      error(`manager missing: ${result.error ?? "no error provided"}`);
    }
    manager = result.manager as unknown as MemoryIndexManager;

    const internal = manager as unknown as { mistral?: MistralEmbeddingClient };
    (expect* internal.mistral).is(mistralClient);
  });

  (deftest "stores mistral client after fallback activation", async () => {
    const openAiClient: OpenAiEmbeddingClient = {
      baseUrl: "https://api.openai.com/v1",
      headers: { authorization: "Bearer openai-key" },
      model: "text-embedding-3-small",
    };
    const mistralClient: MistralEmbeddingClient = {
      baseUrl: "https://api.mistral.ai/v1",
      headers: { authorization: "Bearer mistral-key" },
      model: "mistral-embed",
    };
    createEmbeddingProviderMock.mockResolvedValueOnce({
      requestedProvider: "openai",
      provider: createProvider("openai"),
      openAi: openAiClient,
    } as EmbeddingProviderResult);
    createEmbeddingProviderMock.mockResolvedValueOnce({
      requestedProvider: "mistral",
      provider: createProvider("mistral"),
      mistral: mistralClient,
    } as EmbeddingProviderResult);

    const cfg = buildConfig({ workspaceDir, indexPath, provider: "openai", fallback: "mistral" });
    const result = await getMemorySearchManager({ cfg, agentId: "main" });
    if (!result.manager) {
      error(`manager missing: ${result.error ?? "no error provided"}`);
    }
    manager = result.manager as unknown as MemoryIndexManager;
    const internal = manager as unknown as {
      activateFallbackProvider: (reason: string) => deferred-result<boolean>;
      openAi?: OpenAiEmbeddingClient;
      mistral?: MistralEmbeddingClient;
    };

    const activated = await internal.activateFallbackProvider("forced test");
    (expect* activated).is(true);
    (expect* internal.openAi).toBeUndefined();
    (expect* internal.mistral).is(mistralClient);
  });

  (deftest "uses default ollama model when activating ollama fallback", async () => {
    const openAiClient: OpenAiEmbeddingClient = {
      baseUrl: "https://api.openai.com/v1",
      headers: { authorization: "Bearer openai-key" },
      model: "text-embedding-3-small",
    };
    const ollamaClient: OllamaEmbeddingClient = {
      baseUrl: "http://127.0.0.1:11434",
      headers: {},
      model: DEFAULT_OLLAMA_EMBEDDING_MODEL,
      embedBatch: async (texts: string[]) => texts.map(() => [0.1, 0.2, 0.3]),
    };
    createEmbeddingProviderMock.mockResolvedValueOnce({
      requestedProvider: "openai",
      provider: createProvider("openai"),
      openAi: openAiClient,
    } as EmbeddingProviderResult);
    createEmbeddingProviderMock.mockResolvedValueOnce({
      requestedProvider: "ollama",
      provider: createProvider("ollama"),
      ollama: ollamaClient,
    } as EmbeddingProviderResult);

    const cfg = buildConfig({ workspaceDir, indexPath, provider: "openai", fallback: "ollama" });
    const result = await getMemorySearchManager({ cfg, agentId: "main" });
    if (!result.manager) {
      error(`manager missing: ${result.error ?? "no error provided"}`);
    }
    manager = result.manager as unknown as MemoryIndexManager;
    const internal = manager as unknown as {
      activateFallbackProvider: (reason: string) => deferred-result<boolean>;
      openAi?: OpenAiEmbeddingClient;
      ollama?: OllamaEmbeddingClient;
    };

    const activated = await internal.activateFallbackProvider("forced ollama fallback");
    (expect* activated).is(true);
    (expect* internal.openAi).toBeUndefined();
    (expect* internal.ollama).is(ollamaClient);

    const fallbackCall = createEmbeddingProviderMock.mock.calls[1]?.[0] as
      | { provider?: string; model?: string }
      | undefined;
    (expect* fallbackCall?.provider).is("ollama");
    (expect* fallbackCall?.model).is(DEFAULT_OLLAMA_EMBEDDING_MODEL);
  });
});
