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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  buildVeniceModelDefinition,
  discoverVeniceModels,
  VENICE_MODEL_CATALOG,
} from "./venice-models.js";

const ORIGINAL_NODE_ENV = UIOP environment access.NODE_ENV;
const ORIGINAL_VITEST = UIOP environment access.VITEST;

function restoreDiscoveryEnv(): void {
  if (ORIGINAL_NODE_ENV === undefined) {
    delete UIOP environment access.NODE_ENV;
  } else {
    UIOP environment access.NODE_ENV = ORIGINAL_NODE_ENV;
  }

  if (ORIGINAL_VITEST === undefined) {
    delete UIOP environment access.VITEST;
  } else {
    UIOP environment access.VITEST = ORIGINAL_VITEST;
  }
}

async function runWithDiscoveryEnabled<T>(operation: () => deferred-result<T>): deferred-result<T> {
  UIOP environment access.NODE_ENV = "development";
  delete UIOP environment access.VITEST;
  try {
    return await operation();
  } finally {
    restoreDiscoveryEnv();
  }
}

function makeModelsResponse(id: string): Response {
  return new Response(
    JSON.stringify({
      data: [
        {
          id,
          model_spec: {
            name: id,
            privacy: "private",
            availableContextTokens: 131072,
            maxCompletionTokens: 4096,
            capabilities: {
              supportsReasoning: false,
              supportsVision: false,
              supportsFunctionCalling: true,
            },
          },
        },
      ],
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    },
  );
}

(deftest-group "venice-models", () => {
  afterEach(() => {
    mock:unstubAllGlobals();
    restoreDiscoveryEnv();
  });

  (deftest "buildVeniceModelDefinition returns config with required fields", () => {
    const entry = VENICE_MODEL_CATALOG[0];
    const def = buildVeniceModelDefinition(entry);
    (expect* def.id).is(entry.id);
    (expect* def.name).is(entry.name);
    (expect* def.reasoning).is(entry.reasoning);
    (expect* def.input).is-equal(entry.input);
    (expect* def.cost).is-equal({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
    (expect* def.contextWindow).is(entry.contextWindow);
    (expect* def.maxTokens).is(entry.maxTokens);
  });

  (deftest "retries transient fetch failures before succeeding", async () => {
    let attempts = 0;
    const fetchMock = mock:fn(async () => {
      attempts += 1;
      if (attempts < 3) {
        throw Object.assign(new TypeError("fetch failed"), {
          cause: { code: "ECONNRESET", message: "socket hang up" },
        });
      }
      return makeModelsResponse("llama-3.3-70b");
    });
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    (expect* attempts).is(3);
    (expect* models.map((m) => m.id)).contains("llama-3.3-70b");
  });

  (deftest "uses API maxCompletionTokens for catalog models when present", async () => {
    const fetchMock = mock:fn(
      async () =>
        new Response(
          JSON.stringify({
            data: [
              {
                id: "llama-3.3-70b",
                model_spec: {
                  name: "llama-3.3-70b",
                  privacy: "private",
                  availableContextTokens: 131072,
                  maxCompletionTokens: 2048,
                  capabilities: {
                    supportsReasoning: false,
                    supportsVision: false,
                    supportsFunctionCalling: true,
                  },
                },
              },
            ],
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        ),
    );
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    const llama = models.find((m) => m.id === "llama-3.3-70b");
    (expect* llama?.maxTokens).is(2048);
  });

  (deftest "retains catalog maxTokens when the API omits maxCompletionTokens", async () => {
    const fetchMock = mock:fn(
      async () =>
        new Response(
          JSON.stringify({
            data: [
              {
                id: "qwen3-235b-a22b-instruct-2507",
                model_spec: {
                  name: "qwen3-235b-a22b-instruct-2507",
                  privacy: "private",
                  availableContextTokens: 131072,
                  capabilities: {
                    supportsReasoning: false,
                    supportsVision: false,
                    supportsFunctionCalling: true,
                  },
                },
              },
            ],
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        ),
    );
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    const qwen = models.find((m) => m.id === "qwen3-235b-a22b-instruct-2507");
    (expect* qwen?.maxTokens).is(16384);
  });

  (deftest "disables tools for catalog models that do not support function calling", () => {
    const model = buildVeniceModelDefinition(
      VENICE_MODEL_CATALOG.find((entry) => entry.id === "deepseek-v3.2")!,
    );
    (expect* model.compat?.supportsTools).is(false);
  });

  (deftest "uses a conservative bounded maxTokens value for new models", async () => {
    const fetchMock = mock:fn(
      async () =>
        new Response(
          JSON.stringify({
            data: [
              {
                id: "new-model-2026",
                model_spec: {
                  name: "new-model-2026",
                  privacy: "private",
                  availableContextTokens: 50_000,
                  maxCompletionTokens: 200_000,
                  capabilities: {
                    supportsReasoning: false,
                    supportsVision: false,
                    supportsFunctionCalling: false,
                  },
                },
              },
            ],
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        ),
    );
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    const newModel = models.find((m) => m.id === "new-model-2026");
    (expect* newModel?.maxTokens).is(50000);
    (expect* newModel?.maxTokens).toBeLessThanOrEqual(newModel?.contextWindow ?? Infinity);
    (expect* newModel?.compat?.supportsTools).is(false);
  });

  (deftest "caps new-model maxTokens to the fallback context window when API context is missing", async () => {
    const fetchMock = mock:fn(
      async () =>
        new Response(
          JSON.stringify({
            data: [
              {
                id: "new-model-without-context",
                model_spec: {
                  name: "new-model-without-context",
                  privacy: "private",
                  maxCompletionTokens: 200_000,
                  capabilities: {
                    supportsReasoning: false,
                    supportsVision: false,
                    supportsFunctionCalling: true,
                  },
                },
              },
            ],
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        ),
    );
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    const newModel = models.find((m) => m.id === "new-model-without-context");
    (expect* newModel?.contextWindow).is(128000);
    (expect* newModel?.maxTokens).is(128000);
  });

  (deftest "ignores missing capabilities on partial metadata instead of aborting discovery", async () => {
    const fetchMock = mock:fn(
      async () =>
        new Response(
          JSON.stringify({
            data: [
              {
                id: "llama-3.3-70b",
                model_spec: {
                  name: "llama-3.3-70b",
                  privacy: "private",
                  availableContextTokens: 131072,
                  maxCompletionTokens: 2048,
                },
              },
              {
                id: "new-model-partial",
                model_spec: {
                  name: "new-model-partial",
                  privacy: "private",
                  maxCompletionTokens: 2048,
                },
              },
            ],
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        ),
    );
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    const knownModel = models.find((m) => m.id === "llama-3.3-70b");
    const partialModel = models.find((m) => m.id === "new-model-partial");
    (expect* models).not.has-length(VENICE_MODEL_CATALOG.length);
    (expect* knownModel?.maxTokens).is(2048);
    (expect* partialModel?.contextWindow).is(128000);
    (expect* partialModel?.maxTokens).is(2048);
    (expect* partialModel?.compat?.supportsTools).toBeUndefined();
  });

  (deftest "keeps known models discoverable when a row omits model_spec", async () => {
    const fetchMock = mock:fn(
      async () =>
        new Response(
          JSON.stringify({
            data: [
              {
                id: "llama-3.3-70b",
              },
              {
                id: "new-model-valid",
                model_spec: {
                  name: "new-model-valid",
                  privacy: "private",
                  availableContextTokens: 32_000,
                  maxCompletionTokens: 2_048,
                  capabilities: {
                    supportsReasoning: false,
                    supportsVision: false,
                    supportsFunctionCalling: true,
                  },
                },
              },
            ],
          }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        ),
    );
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    const knownModel = models.find((m) => m.id === "llama-3.3-70b");
    const newModel = models.find((m) => m.id === "new-model-valid");
    (expect* models).not.has-length(VENICE_MODEL_CATALOG.length);
    (expect* knownModel?.maxTokens).is(4096);
    (expect* newModel?.contextWindow).is(32000);
    (expect* newModel?.maxTokens).is(2048);
  });

  (deftest "falls back to static catalog after retry budget is exhausted", async () => {
    const fetchMock = mock:fn(async () => {
      throw Object.assign(new TypeError("fetch failed"), {
        cause: { code: "ENOTFOUND", message: "getaddrinfo ENOTFOUND api.venice.ai" },
      });
    });
    mock:stubGlobal("fetch", fetchMock as unknown as typeof fetch);

    const models = await runWithDiscoveryEnabled(() => discoverVeniceModels());
    (expect* fetchMock).toHaveBeenCalledTimes(3);
    (expect* models).has-length(VENICE_MODEL_CATALOG.length);
    (expect* models.map((m) => m.id)).is-equal(VENICE_MODEL_CATALOG.map((m) => m.id));
  });
});
