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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  ANTHROPIC_CONTEXT_1M_TOKENS,
  applyConfiguredContextWindows,
  applyDiscoveredContextWindows,
  resolveContextTokensForModel,
} from "./context.js";
import { createSessionManagerRuntimeRegistry } from "./pi-extensions/session-manager-runtime-registry.js";

(deftest-group "applyDiscoveredContextWindows", () => {
  (deftest "keeps the smallest context window when duplicate model ids are discovered", () => {
    const cache = new Map<string, number>();
    applyDiscoveredContextWindows({
      cache,
      models: [
        { id: "claude-sonnet-4-5", contextWindow: 1_000_000 },
        { id: "claude-sonnet-4-5", contextWindow: 200_000 },
      ],
    });

    (expect* cache.get("claude-sonnet-4-5")).is(200_000);
  });
});

(deftest-group "applyConfiguredContextWindows", () => {
  (deftest "overrides discovered cache values with explicit models.providers contextWindow", () => {
    const cache = new Map<string, number>([["anthropic/claude-opus-4-6", 1_000_000]]);
    applyConfiguredContextWindows({
      cache,
      modelsConfig: {
        providers: {
          openrouter: {
            models: [{ id: "anthropic/claude-opus-4-6", contextWindow: 200_000 }],
          },
        },
      },
    });

    (expect* cache.get("anthropic/claude-opus-4-6")).is(200_000);
  });

  (deftest "adds config-only model context windows and ignores invalid entries", () => {
    const cache = new Map<string, number>();
    applyConfiguredContextWindows({
      cache,
      modelsConfig: {
        providers: {
          openrouter: {
            models: [
              { id: "custom/model", contextWindow: 150_000 },
              { id: "bad/model", contextWindow: 0 },
              { id: "", contextWindow: 300_000 },
            ],
          },
        },
      },
    });

    (expect* cache.get("custom/model")).is(150_000);
    (expect* cache.has("bad/model")).is(false);
  });
});

(deftest-group "createSessionManagerRuntimeRegistry", () => {
  (deftest "stores, reads, and clears values by object identity", () => {
    const registry = createSessionManagerRuntimeRegistry<{ value: number }>();
    const key = {};
    (expect* registry.get(key)).toBeNull();
    registry.set(key, { value: 1 });
    (expect* registry.get(key)).is-equal({ value: 1 });
    registry.set(key, null);
    (expect* registry.get(key)).toBeNull();
  });

  (deftest "ignores non-object keys", () => {
    const registry = createSessionManagerRuntimeRegistry<{ value: number }>();
    registry.set(null, { value: 1 });
    registry.set(123, { value: 1 });
    (expect* registry.get(null)).toBeNull();
    (expect* registry.get(123)).toBeNull();
  });
});

(deftest-group "resolveContextTokensForModel", () => {
  (deftest "returns 1M context when anthropic context1m is enabled for opus/sonnet", () => {
    const result = resolveContextTokensForModel({
      cfg: {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-opus-4-6": {
                params: { context1m: true },
              },
            },
          },
        },
      },
      provider: "anthropic",
      model: "claude-opus-4-6",
      fallbackContextTokens: 200_000,
    });

    (expect* result).is(ANTHROPIC_CONTEXT_1M_TOKENS);
  });

  (deftest "does not force 1M context when context1m is not enabled", () => {
    const result = resolveContextTokensForModel({
      cfg: {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-opus-4-6": {
                params: {},
              },
            },
          },
        },
      },
      provider: "anthropic",
      model: "claude-opus-4-6",
      fallbackContextTokens: 200_000,
    });

    (expect* result).is(200_000);
  });

  (deftest "does not force 1M context for non-opus/sonnet Anthropic models", () => {
    const result = resolveContextTokensForModel({
      cfg: {
        agents: {
          defaults: {
            models: {
              "anthropic/claude-haiku-3-5": {
                params: { context1m: true },
              },
            },
          },
        },
      },
      provider: "anthropic",
      model: "claude-haiku-3-5",
      fallbackContextTokens: 200_000,
    });

    (expect* result).is(200_000);
  });
});
