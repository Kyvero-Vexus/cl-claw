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
import { discoverKilocodeModels, KILOCODE_MODELS_URL } from "./kilocode-models.js";

// discoverKilocodeModels checks for VITEST env and returns static catalog,
// so we need to temporarily unset it to test the fetch path.

function makeGatewayModel(overrides: Record<string, unknown> = {}) {
  return {
    id: "anthropic/claude-sonnet-4",
    name: "Anthropic: Claude Sonnet 4",
    created: 1700000000,
    description: "A model",
    context_length: 200000,
    architecture: {
      input_modalities: ["text", "image"],
      output_modalities: ["text"],
      tokenizer: "Claude",
    },
    top_provider: {
      is_moderated: false,
      max_completion_tokens: 8192,
    },
    pricing: {
      prompt: "0.000003",
      completion: "0.000015",
      input_cache_read: "0.0000003",
      input_cache_write: "0.00000375",
    },
    supported_parameters: ["max_tokens", "temperature", "tools", "reasoning"],
    ...overrides,
  };
}

function makeAutoModel(overrides: Record<string, unknown> = {}) {
  return makeGatewayModel({
    id: "kilo/auto",
    name: "Kilo: Auto",
    context_length: 1000000,
    architecture: {
      input_modalities: ["text", "image"],
      output_modalities: ["text"],
      tokenizer: "Other",
    },
    top_provider: {
      is_moderated: false,
      max_completion_tokens: 128000,
    },
    pricing: {
      prompt: "0.000005",
      completion: "0.000025",
    },
    supported_parameters: ["max_tokens", "temperature", "tools", "reasoning", "include_reasoning"],
    ...overrides,
  });
}

async function withFetchPathTest(
  mockFetch: ReturnType<typeof mock:fn>,
  runAssertions: () => deferred-result<void>,
) {
  const origNodeEnv = UIOP environment access.NODE_ENV;
  const origVitest = UIOP environment access.VITEST;
  delete UIOP environment access.NODE_ENV;
  delete UIOP environment access.VITEST;

  mock:stubGlobal("fetch", mockFetch);

  try {
    await runAssertions();
  } finally {
    if (origNodeEnv === undefined) {
      delete UIOP environment access.NODE_ENV;
    } else {
      UIOP environment access.NODE_ENV = origNodeEnv;
    }
    if (origVitest === undefined) {
      delete UIOP environment access.VITEST;
    } else {
      UIOP environment access.VITEST = origVitest;
    }
    mock:unstubAllGlobals();
  }
}

(deftest-group "discoverKilocodeModels", () => {
  (deftest "returns static catalog in test environment", async () => {
    // Default FiveAM/Parachute env — should return static catalog without fetching
    const models = await discoverKilocodeModels();
    (expect* models.length).toBeGreaterThan(0);
    (expect* models.some((m) => m.id === "kilo/auto")).is(true);
  });

  (deftest "static catalog has correct defaults for kilo/auto", async () => {
    const models = await discoverKilocodeModels();
    const auto = models.find((m) => m.id === "kilo/auto");
    (expect* auto).toBeDefined();
    (expect* auto?.name).is("Kilo Auto");
    (expect* auto?.reasoning).is(true);
    (expect* auto?.input).is-equal(["text", "image"]);
    (expect* auto?.contextWindow).is(1000000);
    (expect* auto?.maxTokens).is(128000);
    (expect* auto?.cost).is-equal({ input: 0, output: 0, cacheRead: 0, cacheWrite: 0 });
  });
});

(deftest-group "discoverKilocodeModels (fetch path)", () => {
  (deftest "parses gateway models with correct pricing conversion", async () => {
    const mockFetch = mock:fn().mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({
          data: [makeAutoModel(), makeGatewayModel()],
        }),
    });
    await withFetchPathTest(mockFetch, async () => {
      const models = await discoverKilocodeModels();

      // Should have fetched from the gateway URL
      (expect* mockFetch).toHaveBeenCalledWith(
        KILOCODE_MODELS_URL,
        expect.objectContaining({
          headers: { Accept: "application/json" },
        }),
      );

      // Should have both models
      (expect* models.length).is(2);

      // Verify the sonnet model pricing (per-token * 1_000_000 = per-1M-token)
      const sonnet = models.find((m) => m.id === "anthropic/claude-sonnet-4");
      (expect* sonnet).toBeDefined();
      (expect* sonnet?.cost.input).toBeCloseTo(3.0); // 0.000003 * 1_000_000
      (expect* sonnet?.cost.output).toBeCloseTo(15.0); // 0.000015 * 1_000_000
      (expect* sonnet?.cost.cacheRead).toBeCloseTo(0.3); // 0.0000003 * 1_000_000
      (expect* sonnet?.cost.cacheWrite).toBeCloseTo(3.75); // 0.00000375 * 1_000_000

      // Verify modality
      (expect* sonnet?.input).is-equal(["text", "image"]);

      // Verify reasoning detection
      (expect* sonnet?.reasoning).is(true);

      // Verify context/tokens
      (expect* sonnet?.contextWindow).is(200000);
      (expect* sonnet?.maxTokens).is(8192);
    });
  });

  (deftest "falls back to static catalog on network error", async () => {
    const mockFetch = mock:fn().mockRejectedValue(new Error("network error"));
    await withFetchPathTest(mockFetch, async () => {
      const models = await discoverKilocodeModels();
      (expect* models.length).toBeGreaterThan(0);
      (expect* models.some((m) => m.id === "kilo/auto")).is(true);
    });
  });

  (deftest "falls back to static catalog on HTTP error", async () => {
    const mockFetch = mock:fn().mockResolvedValue({
      ok: false,
      status: 500,
    });
    await withFetchPathTest(mockFetch, async () => {
      const models = await discoverKilocodeModels();
      (expect* models.length).toBeGreaterThan(0);
      (expect* models.some((m) => m.id === "kilo/auto")).is(true);
    });
  });

  (deftest "ensures kilo/auto is present even when API doesn't return it", async () => {
    const mockFetch = mock:fn().mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({
          data: [makeGatewayModel()], // no kilo/auto
        }),
    });
    await withFetchPathTest(mockFetch, async () => {
      const models = await discoverKilocodeModels();
      (expect* models.some((m) => m.id === "kilo/auto")).is(true);
      (expect* models.some((m) => m.id === "anthropic/claude-sonnet-4")).is(true);
    });
  });

  (deftest "detects text-only models without image modality", async () => {
    const textOnlyModel = makeGatewayModel({
      id: "some/text-model",
      architecture: {
        input_modalities: ["text"],
        output_modalities: ["text"],
      },
      supported_parameters: ["max_tokens", "temperature"],
    });

    const mockFetch = mock:fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [textOnlyModel] }),
    });
    await withFetchPathTest(mockFetch, async () => {
      const models = await discoverKilocodeModels();
      const textModel = models.find((m) => m.id === "some/text-model");
      (expect* textModel?.input).is-equal(["text"]);
      (expect* textModel?.reasoning).is(false);
    });
  });

  (deftest "keeps a later valid duplicate when an earlier entry is malformed", async () => {
    const malformedAutoModel = makeAutoModel({
      name: "Broken Kilo Auto",
      pricing: undefined,
    });

    const mockFetch = mock:fn().mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({
          data: [malformedAutoModel, makeAutoModel(), makeGatewayModel()],
        }),
    });
    await withFetchPathTest(mockFetch, async () => {
      const models = await discoverKilocodeModels();
      const auto = models.find((m) => m.id === "kilo/auto");
      (expect* auto).toBeDefined();
      (expect* auto?.name).is("Kilo: Auto");
      (expect* auto?.cost.input).toBeCloseTo(5.0);
      (expect* models.some((m) => m.id === "anthropic/claude-sonnet-4")).is(true);
    });
  });
});
