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
import { writeFile } from "sbcl:fs/promises";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import { resolveApiKeyForProvider } from "./model-auth.js";
import { buildNvidiaProvider, resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "NVIDIA provider", () => {
  (deftest "should include nvidia when NVIDIA_API_KEY is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await withEnvAsync({ NVIDIA_API_KEY: "test-key" }, async () => {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.nvidia).toBeDefined();
      (expect* providers?.nvidia?.models?.length).toBeGreaterThan(0);
    });
  });

  (deftest "resolves the nvidia api key value from env", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await withEnvAsync({ NVIDIA_API_KEY: "nvidia-test-api-key" }, async () => {
      const auth = await resolveApiKeyForProvider({
        provider: "nvidia",
        agentDir,
      });

      (expect* auth.apiKey).is("nvidia-test-api-key");
      (expect* auth.mode).is("api-key");
      (expect* auth.source).contains("NVIDIA_API_KEY");
    });
  });

  (deftest "should build nvidia provider with correct configuration", () => {
    const provider = buildNvidiaProvider();
    (expect* provider.baseUrl).is("https://integrate.api.nvidia.com/v1");
    (expect* provider.api).is("openai-completions");
    (expect* provider.models).toBeDefined();
    (expect* provider.models.length).toBeGreaterThan(0);
  });

  (deftest "should include default nvidia models", () => {
    const provider = buildNvidiaProvider();
    const modelIds = provider.models.map((m) => m.id);
    (expect* modelIds).contains("nvidia/llama-3.1-nemotron-70b-instruct");
    (expect* modelIds).contains("meta/llama-3.3-70b-instruct");
    (expect* modelIds).contains("nvidia/mistral-nemo-minitron-8b-8k-instruct");
  });
});

(deftest-group "MiniMax implicit provider (#15275)", () => {
  (deftest "should use anthropic-messages API for API-key provider", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await withEnvAsync({ MINIMAX_API_KEY: "test-key" }, async () => {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.minimax).toBeDefined();
      (expect* providers?.minimax?.api).is("anthropic-messages");
      (expect* providers?.minimax?.authHeader).is(true);
      (expect* providers?.minimax?.baseUrl).is("https://api.minimax.io/anthropic");
    });
  });

  (deftest "should set authHeader for minimax portal provider", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "minimax-portal:default": {
              type: "oauth",
              provider: "minimax-portal",
              access: "token",
              refresh: "refresh-token",
              expires: Date.now() + 60_000,
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const providers = await resolveImplicitProviders({ agentDir });
    (expect* providers?.["minimax-portal"]?.authHeader).is(true);
  });

  (deftest "should include minimax portal provider when MINIMAX_OAUTH_TOKEN is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await withEnvAsync({ MINIMAX_OAUTH_TOKEN: "portal-token" }, async () => {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.["minimax-portal"]).toBeDefined();
      (expect* providers?.["minimax-portal"]?.authHeader).is(true);
      (expect* providers?.["minimax-portal"]?.models?.some((m) => m.id === "MiniMax-VL-01")).is(
        true,
      );
    });
  });
});

(deftest-group "vLLM provider", () => {
  (deftest "should not include vllm when no API key is configured", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await withEnvAsync({ VLLM_API_KEY: undefined }, async () => {
      const providers = await resolveImplicitProviders({ agentDir });
      (expect* providers?.vllm).toBeUndefined();
    });
  });

  (deftest "should include vllm when VLLM_API_KEY is set", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await withEnvAsync({ VLLM_API_KEY: "test-key" }, async () => {
      const providers = await resolveImplicitProviders({ agentDir });

      (expect* providers?.vllm).toBeDefined();
      (expect* providers?.vllm?.apiKey).is("VLLM_API_KEY");
      (expect* providers?.vllm?.baseUrl).is("http://127.0.0.1:8000/v1");
      (expect* providers?.vllm?.api).is("openai-completions");

      // Note: discovery is disabled in test environments (VITEST check)
      (expect* providers?.vllm?.models).is-equal([]);
    });
  });
});
