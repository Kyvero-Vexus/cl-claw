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
import type { OpenClawConfig } from "../config/config.js";
import { resolveEntriesWithActiveFallback, resolveModelEntries } from "./resolve.js";
import type { MediaUnderstandingCapability } from "./types.js";

const providerRegistry = new Map<string, { capabilities: MediaUnderstandingCapability[] }>([
  ["openai", { capabilities: ["image"] }],
  ["groq", { capabilities: ["audio"] }],
]);

(deftest-group "resolveModelEntries", () => {
  (deftest "uses provider capabilities for shared entries without explicit caps", () => {
    const cfg: OpenClawConfig = {
      tools: {
        media: {
          models: [{ provider: "openai", model: "gpt-5.2" }],
        },
      },
    };

    const imageEntries = resolveModelEntries({
      cfg,
      capability: "image",
      providerRegistry,
    });
    (expect* imageEntries).has-length(1);

    const audioEntries = resolveModelEntries({
      cfg,
      capability: "audio",
      providerRegistry,
    });
    (expect* audioEntries).has-length(0);
  });

  (deftest "keeps per-capability entries even without explicit caps", () => {
    const cfg: OpenClawConfig = {
      tools: {
        media: {
          image: {
            models: [{ provider: "openai", model: "gpt-5.2" }],
          },
        },
      },
    };

    const imageEntries = resolveModelEntries({
      cfg,
      capability: "image",
      config: cfg.tools?.media?.image,
      providerRegistry,
    });
    (expect* imageEntries).has-length(1);
  });

  (deftest "skips shared CLI entries without capabilities", () => {
    const cfg: OpenClawConfig = {
      tools: {
        media: {
          models: [{ type: "cli", command: "gemini", args: ["--file", "{{MediaPath}}"] }],
        },
      },
    };

    const entries = resolveModelEntries({
      cfg,
      capability: "image",
      providerRegistry,
    });
    (expect* entries).has-length(0);
  });
});

(deftest-group "resolveEntriesWithActiveFallback", () => {
  type ResolveWithFallbackInput = Parameters<typeof resolveEntriesWithActiveFallback>[0];
  const defaultActiveModel = { provider: "groq", model: "whisper-large-v3" } as const;

  function resolveWithActiveFallback(params: {
    cfg: ResolveWithFallbackInput["cfg"];
    capability: ResolveWithFallbackInput["capability"];
    config: ResolveWithFallbackInput["config"];
  }) {
    return resolveEntriesWithActiveFallback({
      cfg: params.cfg,
      capability: params.capability,
      config: params.config,
      providerRegistry,
      activeModel: defaultActiveModel,
    });
  }

  function expectResolvedProviders(params: {
    cfg: OpenClawConfig;
    capability: ResolveWithFallbackInput["capability"];
    config: ResolveWithFallbackInput["config"];
    providers: string[];
  }) {
    const entries = resolveWithActiveFallback({
      cfg: params.cfg,
      capability: params.capability,
      config: params.config,
    });
    (expect* entries).has-length(params.providers.length);
    (expect* entries.map((entry) => entry.provider)).is-equal(params.providers);
  }

  (deftest "uses active model when enabled and no models are configured", () => {
    const cfg: OpenClawConfig = {
      tools: {
        media: {
          audio: { enabled: true },
        },
      },
    };

    expectResolvedProviders({
      cfg,
      capability: "audio",
      config: cfg.tools?.media?.audio,
      providers: ["groq"],
    });
  });

  (deftest "ignores active model when configured entries exist", () => {
    const cfg: OpenClawConfig = {
      tools: {
        media: {
          audio: { enabled: true, models: [{ provider: "openai", model: "whisper-1" }] },
        },
      },
    };

    expectResolvedProviders({
      cfg,
      capability: "audio",
      config: cfg.tools?.media?.audio,
      providers: ["openai"],
    });
  });

  (deftest "skips active model when provider lacks capability", () => {
    const cfg: OpenClawConfig = {
      tools: {
        media: {
          video: { enabled: true },
        },
      },
    };

    const entries = resolveWithActiveFallback({
      cfg,
      capability: "video",
      config: cfg.tools?.media?.video,
    });
    (expect* entries).has-length(0);
  });
});
