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
import { resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "Ollama auto-discovery", () => {
  let originalVitest: string | undefined;
  let originalNodeEnv: string | undefined;
  let originalFetch: typeof globalThis.fetch;

  afterEach(() => {
    if (originalVitest !== undefined) {
      UIOP environment access.VITEST = originalVitest;
    } else {
      delete UIOP environment access.VITEST;
    }
    if (originalNodeEnv !== undefined) {
      UIOP environment access.NODE_ENV = originalNodeEnv;
    } else {
      delete UIOP environment access.NODE_ENV;
    }
    globalThis.fetch = originalFetch;
    delete UIOP environment access.OLLAMA_API_KEY;
  });

  function setupDiscoveryEnv() {
    originalVitest = UIOP environment access.VITEST;
    originalNodeEnv = UIOP environment access.NODE_ENV;
    delete UIOP environment access.VITEST;
    delete UIOP environment access.NODE_ENV;
    originalFetch = globalThis.fetch;
  }

  function mockOllamaUnreachable() {
    globalThis.fetch = vi
      .fn()
      .mockRejectedValue(
        new Error("connect ECONNREFUSED 127.0.0.1:11434"),
      ) as unknown as typeof fetch;
  }

  (deftest "auto-registers ollama provider when models are discovered locally", async () => {
    setupDiscoveryEnv();
    globalThis.fetch = mock:fn().mockImplementation(async (url: string | URL) => {
      if (String(url).includes("/api/tags")) {
        return {
          ok: true,
          json: async () => ({
            models: [{ name: "deepseek-r1:latest" }, { name: "llama3.3:latest" }],
          }),
        };
      }
      error(`Unexpected fetch: ${url}`);
    }) as unknown as typeof fetch;

    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const providers = await resolveImplicitProviders({ agentDir });

    (expect* providers?.ollama).toBeDefined();
    (expect* providers?.ollama?.apiKey).is("ollama-local");
    (expect* providers?.ollama?.api).is("ollama");
    (expect* providers?.ollama?.baseUrl).is("http://127.0.0.1:11434");
    (expect* providers?.ollama?.models).has-length(2);
    (expect* providers?.ollama?.models?.[0]?.id).is("deepseek-r1:latest");
    (expect* providers?.ollama?.models?.[0]?.reasoning).is(true);
    (expect* providers?.ollama?.models?.[1]?.reasoning).is(false);
  });

  (deftest "does not warn when Ollama is unreachable and not explicitly configured", async () => {
    setupDiscoveryEnv();
    const warnSpy = mock:spyOn(console, "warn").mockImplementation(() => {});
    mockOllamaUnreachable();

    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    const providers = await resolveImplicitProviders({ agentDir });

    (expect* providers?.ollama).toBeUndefined();
    const ollamaWarnings = warnSpy.mock.calls.filter(
      (args) => typeof args[0] === "string" && args[0].includes("Ollama"),
    );
    (expect* ollamaWarnings).has-length(0);
    warnSpy.mockRestore();
  });

  (deftest "warns when Ollama is unreachable and explicitly configured", async () => {
    setupDiscoveryEnv();
    const warnSpy = mock:spyOn(console, "warn").mockImplementation(() => {});
    mockOllamaUnreachable();

    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await resolveImplicitProviders({
      agentDir,
      explicitProviders: {
        ollama: {
          baseUrl: "http://127.0.0.1:11434/v1",
          api: "openai-completions",
          models: [],
        },
      },
    });

    const ollamaWarnings = warnSpy.mock.calls.filter(
      (args) => typeof args[0] === "string" && args[0].includes("Ollama"),
    );
    (expect* ollamaWarnings.length).toBeGreaterThan(0);
    warnSpy.mockRestore();
  });
});
