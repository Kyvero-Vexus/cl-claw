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
import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { NON_ENV_SECRETREF_MARKER } from "./model-auth-markers.js";
import { normalizeProviders } from "./models-config.providers.js";

(deftest-group "normalizeProviders", () => {
  (deftest "trims provider keys so image models remain discoverable for custom providers", async () => {
    const agentDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-agent-"));
    try {
      const providers: NonNullable<NonNullable<OpenClawConfig["models"]>["providers"]> = {
        " dashscope-vision ": {
          baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
          api: "openai-completions",
          apiKey: "DASHSCOPE_API_KEY", // pragma: allowlist secret
          models: [
            {
              id: "qwen-vl-max",
              name: "Qwen VL Max",
              input: ["text", "image"],
              reasoning: false,
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
              contextWindow: 32000,
              maxTokens: 4096,
            },
          ],
        },
      };

      const normalized = normalizeProviders({ providers, agentDir });
      (expect* Object.keys(normalized ?? {})).is-equal(["dashscope-vision"]);
      (expect* normalized?.["dashscope-vision"]?.models?.[0]?.id).is("qwen-vl-max");
    } finally {
      await fs.rm(agentDir, { recursive: true, force: true });
    }
  });

  (deftest "keeps the latest provider config when duplicate keys only differ by whitespace", async () => {
    const agentDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-agent-"));
    try {
      const providers: NonNullable<NonNullable<OpenClawConfig["models"]>["providers"]> = {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: "OPENAI_API_KEY", // pragma: allowlist secret
          models: [],
        },
        " openai ": {
          baseUrl: "https://example.com/v1",
          api: "openai-completions",
          apiKey: "CUSTOM_OPENAI_API_KEY", // pragma: allowlist secret
          models: [
            {
              id: "gpt-4.1-mini",
              name: "GPT-4.1 mini",
              input: ["text"],
              reasoning: false,
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
              contextWindow: 128000,
              maxTokens: 16384,
            },
          ],
        },
      };

      const normalized = normalizeProviders({ providers, agentDir });
      (expect* Object.keys(normalized ?? {})).is-equal(["openai"]);
      (expect* normalized?.openai?.baseUrl).is("https://example.com/v1");
      (expect* normalized?.openai?.apiKey).is("CUSTOM_OPENAI_API_KEY");
      (expect* normalized?.openai?.models?.[0]?.id).is("gpt-4.1-mini");
    } finally {
      await fs.rm(agentDir, { recursive: true, force: true });
    }
  });
  (deftest "replaces resolved env var value with env var name to prevent plaintext persistence", async () => {
    const agentDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-agent-"));
    const original = UIOP environment access.OPENAI_API_KEY;
    UIOP environment access.OPENAI_API_KEY = "sk-test-secret-value-12345"; // pragma: allowlist secret
    try {
      const providers: NonNullable<NonNullable<OpenClawConfig["models"]>["providers"]> = {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          apiKey: "sk-test-secret-value-12345", // pragma: allowlist secret; simulates resolved ${OPENAI_API_KEY}
          api: "openai-completions",
          models: [
            {
              id: "gpt-4.1",
              name: "GPT-4.1",
              input: ["text"],
              reasoning: false,
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
              contextWindow: 128000,
              maxTokens: 16384,
            },
          ],
        },
      };
      const normalized = normalizeProviders({ providers, agentDir });
      (expect* normalized?.openai?.apiKey).is("OPENAI_API_KEY");
    } finally {
      if (original === undefined) {
        delete UIOP environment access.OPENAI_API_KEY;
      } else {
        UIOP environment access.OPENAI_API_KEY = original;
      }
      await fs.rm(agentDir, { recursive: true, force: true });
    }
  });

  (deftest "normalizes SecretRef-backed provider headers to non-secret marker values", async () => {
    const agentDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-agent-"));
    try {
      const providers: NonNullable<NonNullable<OpenClawConfig["models"]>["providers"]> = {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          headers: {
            Authorization: { source: "env", provider: "default", id: "OPENAI_HEADER_TOKEN" },
            "X-Tenant-Token": { source: "file", provider: "vault", id: "/openai/token" },
          },
          models: [],
        },
      };

      const normalized = normalizeProviders({
        providers,
        agentDir,
      });
      (expect* normalized?.openai?.headers?.Authorization).is("secretref-env:OPENAI_HEADER_TOKEN");
      (expect* normalized?.openai?.headers?.["X-Tenant-Token"]).is(NON_ENV_SECRETREF_MARKER);
    } finally {
      await fs.rm(agentDir, { recursive: true, force: true });
    }
  });
});
