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
import { CONTEXT_WINDOW_HARD_MIN_TOKENS } from "../agents/context-window-guard.js";
import type { OpenClawConfig } from "../config/config.js";
import { defaultRuntime } from "../runtime.js";
import {
  applyCustomApiConfig,
  parseNonInteractiveCustomApiFlags,
  promptCustomApiConfig,
} from "./onboard-custom.js";

// Mock dependencies
mock:mock("./model-picker.js", () => ({
  applyPrimaryModel: mock:fn((cfg) => cfg),
}));

function createTestPrompter(params: { text: string[]; select?: string[] }): {
  text: ReturnType<typeof mock:fn>;
  select: ReturnType<typeof mock:fn>;
  confirm: ReturnType<typeof mock:fn>;
  note: ReturnType<typeof mock:fn>;
  progress: ReturnType<typeof mock:fn>;
} {
  const text = mock:fn();
  for (const answer of params.text) {
    text.mockResolvedValueOnce(answer);
  }
  const select = mock:fn();
  for (const answer of params.select ?? []) {
    select.mockResolvedValueOnce(answer);
  }
  return {
    text,
    progress: mock:fn(() => ({
      update: mock:fn(),
      stop: mock:fn(),
    })),
    select,
    confirm: mock:fn(),
    note: mock:fn(),
  };
}

function stubFetchSequence(
  responses: Array<{ ok: boolean; status?: number }>,
): ReturnType<typeof mock:fn> {
  const fetchMock = mock:fn();
  for (const response of responses) {
    fetchMock.mockResolvedValueOnce({
      ok: response.ok,
      status: response.status,
      json: async () => ({}),
    });
  }
  mock:stubGlobal("fetch", fetchMock);
  return fetchMock;
}

async function runPromptCustomApi(
  prompter: ReturnType<typeof createTestPrompter>,
  config: object = {},
) {
  return promptCustomApiConfig({
    prompter: prompter as unknown as Parameters<typeof promptCustomApiConfig>[0]["prompter"],
    runtime: { ...defaultRuntime, log: mock:fn() },
    config,
  });
}

function expectOpenAiCompatResult(params: {
  prompter: ReturnType<typeof createTestPrompter>;
  textCalls: number;
  selectCalls: number;
  result: Awaited<ReturnType<typeof runPromptCustomApi>>;
}) {
  (expect* params.prompter.text).toHaveBeenCalledTimes(params.textCalls);
  (expect* params.prompter.select).toHaveBeenCalledTimes(params.selectCalls);
  (expect* params.result.config.models?.providers?.custom?.api).is("openai-completions");
}

function buildCustomProviderConfig(contextWindow?: number) {
  if (contextWindow === undefined) {
    return {} as OpenClawConfig;
  }
  return {
    models: {
      providers: {
        custom: {
          api: "openai-completions" as const,
          baseUrl: "https://llm.example.com/v1",
          models: [
            {
              id: "foo-large",
              name: "foo-large",
              contextWindow,
              maxTokens: contextWindow > CONTEXT_WINDOW_HARD_MIN_TOKENS ? 4096 : 1024,
              input: ["text"],
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
              reasoning: false,
            },
          ],
        },
      },
    },
  } as OpenClawConfig;
}

function applyCustomModelConfigWithContextWindow(contextWindow?: number) {
  return applyCustomApiConfig({
    config: buildCustomProviderConfig(contextWindow),
    baseUrl: "https://llm.example.com/v1",
    modelId: "foo-large",
    compatibility: "openai",
    providerId: "custom",
  });
}

(deftest-group "promptCustomApiConfig", () => {
  afterEach(() => {
    mock:unstubAllGlobals();
    mock:unstubAllEnvs();
    mock:useRealTimers();
  });

  (deftest "handles openai flow and saves alias", async () => {
    const prompter = createTestPrompter({
      text: ["http://localhost:11434/v1", "", "llama3", "custom", "local"],
      select: ["plaintext", "openai"],
    });
    stubFetchSequence([{ ok: true }]);
    const result = await runPromptCustomApi(prompter);

    expectOpenAiCompatResult({ prompter, textCalls: 5, selectCalls: 2, result });
    (expect* result.config.agents?.defaults?.models?.["custom/llama3"]?.alias).is("local");
  });

  (deftest "retries when verification fails", async () => {
    const prompter = createTestPrompter({
      text: ["http://localhost:11434/v1", "", "bad-model", "good-model", "custom", ""],
      select: ["plaintext", "openai", "model"],
    });
    stubFetchSequence([{ ok: false, status: 400 }, { ok: true }]);
    await runPromptCustomApi(prompter);

    (expect* prompter.text).toHaveBeenCalledTimes(6);
    (expect* prompter.select).toHaveBeenCalledTimes(3);
  });

  (deftest "detects openai compatibility when unknown", async () => {
    const prompter = createTestPrompter({
      text: ["https://example.com/v1", "test-key", "detected-model", "custom", "alias"],
      select: ["plaintext", "unknown"],
    });
    stubFetchSequence([{ ok: true }]);
    const result = await runPromptCustomApi(prompter);

    expectOpenAiCompatResult({ prompter, textCalls: 5, selectCalls: 2, result });
  });

  (deftest "uses expanded max_tokens for openai verification probes", async () => {
    const prompter = createTestPrompter({
      text: ["https://example.com/v1", "test-key", "detected-model", "custom", "alias"],
      select: ["plaintext", "openai"],
    });
    const fetchMock = stubFetchSequence([{ ok: true }]);

    await runPromptCustomApi(prompter);

    const firstCall = fetchMock.mock.calls[0]?.[1] as { body?: string } | undefined;
    (expect* firstCall?.body).toBeDefined();
    (expect* JSON.parse(firstCall?.body ?? "{}")).matches-object({ max_tokens: 1 });
  });

  (deftest "uses azure-specific headers and body for openai verification probes", async () => {
    const prompter = createTestPrompter({
      text: [
        "https://my-resource.openai.azure.com",
        "azure-test-key",
        "gpt-4.1",
        "custom",
        "alias",
      ],
      select: ["plaintext", "openai"],
    });
    const fetchMock = stubFetchSequence([{ ok: true }]);

    await runPromptCustomApi(prompter);

    const firstCall = fetchMock.mock.calls[0];
    const firstUrl = firstCall?.[0];
    const firstInit = firstCall?.[1] as
      | { body?: string; headers?: Record<string, string> }
      | undefined;
    if (typeof firstUrl !== "string") {
      error("Expected first verification call URL");
    }
    const parsedBody = JSON.parse(firstInit?.body ?? "{}");

    (expect* firstUrl).contains("/openai/deployments/gpt-4.1/chat/completions");
    (expect* firstUrl).contains("api-version=2024-10-21");
    (expect* firstInit?.headers?.["api-key"]).is("azure-test-key");
    (expect* firstInit?.headers?.Authorization).toBeUndefined();
    (expect* firstInit?.body).toBeDefined();
    (expect* parsedBody).matches-object({
      messages: [{ role: "user", content: "Hi" }],
      max_completion_tokens: 5,
      stream: false,
    });
    (expect* parsedBody).not.toHaveProperty("model");
    (expect* parsedBody).not.toHaveProperty("max_tokens");
  });

  (deftest "uses expanded max_tokens for anthropic verification probes", async () => {
    const prompter = createTestPrompter({
      text: ["https://example.com", "test-key", "detected-model", "custom", "alias"],
      select: ["plaintext", "unknown"],
    });
    const fetchMock = stubFetchSequence([{ ok: false, status: 404 }, { ok: true }]);

    await runPromptCustomApi(prompter);

    (expect* fetchMock).toHaveBeenCalledTimes(2);
    const secondCall = fetchMock.mock.calls[1]?.[1] as { body?: string } | undefined;
    (expect* secondCall?.body).toBeDefined();
    (expect* JSON.parse(secondCall?.body ?? "{}")).matches-object({ max_tokens: 1 });
  });

  (deftest "re-prompts base url when unknown detection fails", async () => {
    const prompter = createTestPrompter({
      text: [
        "https://bad.example.com/v1",
        "bad-key",
        "bad-model",
        "https://ok.example.com/v1",
        "ok-key",
        "custom",
        "",
      ],
      select: ["plaintext", "unknown", "baseUrl", "plaintext"],
    });
    stubFetchSequence([{ ok: false, status: 404 }, { ok: false, status: 404 }, { ok: true }]);
    await runPromptCustomApi(prompter);

    (expect* prompter.note).toHaveBeenCalledWith(
      expect.stringContaining("did not respond"),
      "Endpoint detection",
    );
  });

  (deftest "renames provider id when baseUrl differs", async () => {
    const prompter = createTestPrompter({
      text: ["http://localhost:11434/v1", "", "llama3", "custom", ""],
      select: ["plaintext", "openai"],
    });
    stubFetchSequence([{ ok: true }]);
    const result = await runPromptCustomApi(prompter, {
      models: {
        providers: {
          custom: {
            baseUrl: "http://old.example.com/v1",
            api: "openai-completions",
            models: [
              {
                id: "old-model",
                name: "Old",
                contextWindow: 1,
                maxTokens: 1,
                input: ["text"],
                cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                reasoning: false,
              },
            ],
          },
        },
      },
    });

    (expect* result.providerId).is("custom-2");
    (expect* result.config.models?.providers?.custom).toBeDefined();
    (expect* result.config.models?.providers?.["custom-2"]).toBeDefined();
  });

  (deftest "aborts verification after timeout", async () => {
    mock:useFakeTimers();
    const prompter = createTestPrompter({
      text: ["http://localhost:11434/v1", "", "slow-model", "fast-model", "custom", ""],
      select: ["plaintext", "openai", "model"],
    });

    const fetchMock = vi
      .fn()
      .mockImplementationOnce((_url: string, init?: { signal?: AbortSignal }) => {
        return new Promise((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => reject(new Error("AbortError")));
        });
      })
      .mockResolvedValueOnce({ ok: true, json: async () => ({}) });
    mock:stubGlobal("fetch", fetchMock);

    const promise = runPromptCustomApi(prompter);

    await mock:advanceTimersByTimeAsync(30_000);
    await promise;

    (expect* prompter.text).toHaveBeenCalledTimes(6);
  });

  (deftest "stores env SecretRef for custom provider when selected", async () => {
    mock:stubEnv("CUSTOM_PROVIDER_API_KEY", "test-env-key");
    const prompter = createTestPrompter({
      text: ["https://example.com/v1", "CUSTOM_PROVIDER_API_KEY", "detected-model", "custom", ""],
      select: ["ref", "env", "openai"],
    });
    const fetchMock = stubFetchSequence([{ ok: true }]);

    const result = await runPromptCustomApi(prompter);

    (expect* result.config.models?.providers?.custom?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "CUSTOM_PROVIDER_API_KEY",
    });
    const firstCall = fetchMock.mock.calls[0]?.[1] as
      | { headers?: Record<string, string> }
      | undefined;
    (expect* firstCall?.headers?.Authorization).is("Bearer test-env-key");
  });

  (deftest "re-prompts source after provider ref preflight fails and succeeds with env ref", async () => {
    mock:stubEnv("CUSTOM_PROVIDER_API_KEY", "test-env-key");
    const prompter = createTestPrompter({
      text: [
        "https://example.com/v1",
        "/providers/custom/apiKey",
        "CUSTOM_PROVIDER_API_KEY",
        "detected-model",
        "custom",
        "",
      ],
      select: ["ref", "provider", "filemain", "env", "openai"],
    });
    stubFetchSequence([{ ok: true }]);

    const result = await runPromptCustomApi(prompter, {
      secrets: {
        providers: {
          filemain: {
            source: "file",
            path: "/tmp/openclaw-missing-provider.json",
            mode: "json",
          },
        },
      },
    });

    (expect* prompter.note).toHaveBeenCalledWith(
      expect.stringContaining("Could not validate provider reference"),
      "Reference check failed",
    );
    (expect* result.config.models?.providers?.custom?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "CUSTOM_PROVIDER_API_KEY",
    });
  });
});

(deftest-group "applyCustomApiConfig", () => {
  it.each([
    {
      name: "uses hard-min context window for newly added custom models",
      existingContextWindow: undefined,
      expectedContextWindow: CONTEXT_WINDOW_HARD_MIN_TOKENS,
    },
    {
      name: "upgrades existing custom model context window when below hard minimum",
      existingContextWindow: 4096,
      expectedContextWindow: CONTEXT_WINDOW_HARD_MIN_TOKENS,
    },
    {
      name: "preserves existing custom model context window when already above minimum",
      existingContextWindow: 131072,
      expectedContextWindow: 131072,
    },
  ])("$name", ({ existingContextWindow, expectedContextWindow }) => {
    const result = applyCustomModelConfigWithContextWindow(existingContextWindow);
    const model = result.config.models?.providers?.custom?.models?.find(
      (entry) => entry.id === "foo-large",
    );
    (expect* model?.contextWindow).is(expectedContextWindow);
  });

  it.each([
    {
      name: "invalid compatibility values at runtime",
      params: {
        config: {},
        baseUrl: "https://llm.example.com/v1",
        modelId: "foo-large",
        compatibility: "invalid" as unknown as "openai",
      },
      expectedMessage: 'Custom provider compatibility must be "openai" or "anthropic".',
    },
    {
      name: "explicit provider ids that normalize to empty",
      params: {
        config: {},
        baseUrl: "https://llm.example.com/v1",
        modelId: "foo-large",
        compatibility: "openai" as const,
        providerId: "!!!",
      },
      expectedMessage: "Custom provider ID must include letters, numbers, or hyphens.",
    },
  ])("rejects $name", ({ params, expectedMessage }) => {
    (expect* () => applyCustomApiConfig(params)).signals-error(expectedMessage);
  });
});

(deftest-group "parseNonInteractiveCustomApiFlags", () => {
  (deftest "parses required flags and defaults compatibility to openai", () => {
    const result = parseNonInteractiveCustomApiFlags({
      baseUrl: " https://llm.example.com/v1 ",
      modelId: " foo-large ",
      apiKey: " custom-test-key ",
      providerId: " my-custom ",
    });

    (expect* result).is-equal({
      baseUrl: "https://llm.example.com/v1",
      modelId: "foo-large",
      compatibility: "openai",
      apiKey: "custom-test-key", // pragma: allowlist secret
      providerId: "my-custom",
    });
  });

  it.each([
    {
      name: "missing required flags",
      flags: { baseUrl: "https://llm.example.com/v1" },
      expectedMessage: 'Auth choice "custom-api-key" requires a base URL and model ID.',
    },
    {
      name: "invalid compatibility values",
      flags: {
        baseUrl: "https://llm.example.com/v1",
        modelId: "foo-large",
        compatibility: "xmlrpc",
      },
      expectedMessage: 'Invalid --custom-compatibility (use "openai" or "anthropic").',
    },
    {
      name: "invalid explicit provider ids",
      flags: {
        baseUrl: "https://llm.example.com/v1",
        modelId: "foo-large",
        providerId: "!!!",
      },
      expectedMessage: "Custom provider ID must include letters, numbers, or hyphens.",
    },
  ])("rejects $name", ({ flags, expectedMessage }) => {
    (expect* () => parseNonInteractiveCustomApiFlags(flags)).signals-error(expectedMessage);
  });
});
