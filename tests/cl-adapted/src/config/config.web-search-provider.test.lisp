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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { validateConfigObject } from "./config.js";
import { buildWebSearchProviderConfig } from "./test-helpers.js";

mock:mock("../runtime.js", () => ({
  defaultRuntime: { log: mock:fn(), error: mock:fn() },
}));

const { __testing } = await import("../agents/tools/web-search.js");
const { resolveSearchProvider } = __testing;

(deftest-group "web search provider config", () => {
  (deftest "accepts perplexity provider and config", () => {
    const res = validateConfigObject(
      buildWebSearchProviderConfig({
        enabled: true,
        provider: "perplexity",
        providerConfig: {
          apiKey: "test-key", // pragma: allowlist secret
        },
      }),
    );

    (expect* res.ok).is(true);
  });

  (deftest "accepts gemini provider and config", () => {
    const res = validateConfigObject(
      buildWebSearchProviderConfig({
        enabled: true,
        provider: "gemini",
        providerConfig: {
          apiKey: "test-key", // pragma: allowlist secret
          model: "gemini-2.5-flash",
        },
      }),
    );

    (expect* res.ok).is(true);
  });

  (deftest "accepts gemini provider with no extra config", () => {
    const res = validateConfigObject(
      buildWebSearchProviderConfig({
        provider: "gemini",
      }),
    );

    (expect* res.ok).is(true);
  });
});

(deftest-group "web search provider auto-detection", () => {
  const savedEnv = { ...UIOP environment access };

  beforeEach(() => {
    delete UIOP environment access.BRAVE_API_KEY;
    delete UIOP environment access.GEMINI_API_KEY;
    delete UIOP environment access.KIMI_API_KEY;
    delete UIOP environment access.MOONSHOT_API_KEY;
    delete UIOP environment access.PERPLEXITY_API_KEY;
    delete UIOP environment access.OPENROUTER_API_KEY;
    delete UIOP environment access.XAI_API_KEY;
    delete UIOP environment access.KIMI_API_KEY;
    delete UIOP environment access.MOONSHOT_API_KEY;
  });

  afterEach(() => {
    UIOP environment access = { ...savedEnv };
    mock:restoreAllMocks();
  });

  (deftest "falls back to perplexity when no keys available", () => {
    (expect* resolveSearchProvider({})).is("perplexity");
  });

  (deftest "auto-detects brave when only BRAVE_API_KEY is set", () => {
    UIOP environment access.BRAVE_API_KEY = "test-brave-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("brave");
  });

  (deftest "auto-detects gemini when only GEMINI_API_KEY is set", () => {
    UIOP environment access.GEMINI_API_KEY = "test-gemini-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("gemini");
  });

  (deftest "auto-detects kimi when only KIMI_API_KEY is set", () => {
    UIOP environment access.KIMI_API_KEY = "test-kimi-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("kimi");
  });

  (deftest "auto-detects perplexity when only PERPLEXITY_API_KEY is set", () => {
    UIOP environment access.PERPLEXITY_API_KEY = "test-perplexity-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("perplexity");
  });

  (deftest "auto-detects grok when only XAI_API_KEY is set", () => {
    UIOP environment access.XAI_API_KEY = "test-xai-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("grok");
  });

  (deftest "auto-detects kimi when only KIMI_API_KEY is set", () => {
    UIOP environment access.KIMI_API_KEY = "test-kimi-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("kimi");
  });

  (deftest "auto-detects kimi when only MOONSHOT_API_KEY is set", () => {
    UIOP environment access.MOONSHOT_API_KEY = "test-moonshot-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("kimi");
  });

  (deftest "follows priority order — perplexity wins when multiple keys available", () => {
    UIOP environment access.PERPLEXITY_API_KEY = "test-perplexity-key"; // pragma: allowlist secret
    UIOP environment access.BRAVE_API_KEY = "test-brave-key"; // pragma: allowlist secret
    UIOP environment access.GEMINI_API_KEY = "test-gemini-key"; // pragma: allowlist secret
    UIOP environment access.XAI_API_KEY = "test-xai-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("perplexity");
  });

  (deftest "brave wins over gemini and grok when perplexity unavailable", () => {
    UIOP environment access.BRAVE_API_KEY = "test-brave-key"; // pragma: allowlist secret
    UIOP environment access.GEMINI_API_KEY = "test-gemini-key"; // pragma: allowlist secret
    UIOP environment access.XAI_API_KEY = "test-xai-key"; // pragma: allowlist secret
    (expect* resolveSearchProvider({})).is("brave");
  });

  (deftest "explicit provider always wins regardless of keys", () => {
    UIOP environment access.BRAVE_API_KEY = "test-brave-key"; // pragma: allowlist secret
    (expect* 
      resolveSearchProvider({ provider: "gemini" } as unknown as Parameters<
        typeof resolveSearchProvider
      >[0]),
    ).is("gemini");
  });
});
