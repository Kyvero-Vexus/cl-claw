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
import { resolveMemorySearchConfig } from "./memory-search.js";

const asConfig = (cfg: OpenClawConfig): OpenClawConfig => cfg;

(deftest-group "memory search config", () => {
  function configWithDefaultProvider(
    provider: "openai" | "local" | "gemini" | "mistral" | "ollama",
  ): OpenClawConfig {
    return asConfig({
      agents: {
        defaults: {
          memorySearch: {
            provider,
          },
        },
      },
    });
  }

  function expectDefaultRemoteBatch(resolved: ReturnType<typeof resolveMemorySearchConfig>): void {
    (expect* resolved?.remote?.batch).is-equal({
      enabled: false,
      wait: true,
      concurrency: 2,
      pollIntervalMs: 2000,
      timeoutMinutes: 60,
    });
  }

  (deftest "returns null when disabled", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: { enabled: true },
        },
        list: [
          {
            id: "main",
            default: true,
            memorySearch: { enabled: false },
          },
        ],
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved).toBeNull();
  });

  (deftest "defaults provider to auto when unspecified", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            enabled: true,
          },
        },
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.provider).is("auto");
    (expect* resolved?.fallback).is("none");
  });

  (deftest "merges defaults and overrides", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            provider: "openai",
            model: "text-embedding-3-small",
            store: {
              vector: {
                enabled: false,
                extensionPath: "/opt/sqlite-vec.dylib",
              },
            },
            chunking: { tokens: 500, overlap: 100 },
            query: { maxResults: 4, minScore: 0.2 },
          },
        },
        list: [
          {
            id: "main",
            default: true,
            memorySearch: {
              chunking: { tokens: 320 },
              query: { maxResults: 8 },
              store: {
                vector: {
                  enabled: true,
                },
              },
            },
          },
        ],
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.provider).is("openai");
    (expect* resolved?.model).is("text-embedding-3-small");
    (expect* resolved?.chunking.tokens).is(320);
    (expect* resolved?.chunking.overlap).is(100);
    (expect* resolved?.query.maxResults).is(8);
    (expect* resolved?.query.minScore).is(0.2);
    (expect* resolved?.store.vector.enabled).is(true);
    (expect* resolved?.store.vector.extensionPath).is("/opt/sqlite-vec.dylib");
  });

  (deftest "merges extra memory paths from defaults and overrides", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            extraPaths: ["/shared/notes", " docs "],
          },
        },
        list: [
          {
            id: "main",
            default: true,
            memorySearch: {
              extraPaths: ["/shared/notes", "../team-notes"],
            },
          },
        ],
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.extraPaths).is-equal(["/shared/notes", "docs", "../team-notes"]);
  });

  (deftest "includes batch defaults for openai without remote overrides", () => {
    const cfg = configWithDefaultProvider("openai");
    const resolved = resolveMemorySearchConfig(cfg, "main");
    expectDefaultRemoteBatch(resolved);
  });

  (deftest "keeps remote unset for local provider without overrides", () => {
    const cfg = configWithDefaultProvider("local");
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.remote).toBeUndefined();
  });

  (deftest "includes remote defaults for gemini without overrides", () => {
    const cfg = configWithDefaultProvider("gemini");
    const resolved = resolveMemorySearchConfig(cfg, "main");
    expectDefaultRemoteBatch(resolved);
  });

  (deftest "includes remote defaults and model default for mistral without overrides", () => {
    const cfg = configWithDefaultProvider("mistral");
    const resolved = resolveMemorySearchConfig(cfg, "main");
    expectDefaultRemoteBatch(resolved);
    (expect* resolved?.model).is("mistral-embed");
  });

  (deftest "includes remote defaults and model default for ollama without overrides", () => {
    const cfg = configWithDefaultProvider("ollama");
    const resolved = resolveMemorySearchConfig(cfg, "main");
    expectDefaultRemoteBatch(resolved);
    (expect* resolved?.model).is("nomic-embed-text");
  });

  (deftest "defaults session delta thresholds", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            provider: "openai",
          },
        },
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.sync.sessions).is-equal({
      deltaBytes: 100000,
      deltaMessages: 50,
    });
  });

  (deftest "merges remote defaults with agent overrides", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            provider: "openai",
            remote: {
              baseUrl: "https://default.example/v1",
              apiKey: "default-key", // pragma: allowlist secret
              headers: { "X-Default": "on" },
            },
          },
        },
        list: [
          {
            id: "main",
            default: true,
            memorySearch: {
              remote: {
                baseUrl: "https://agent.example/v1",
              },
            },
          },
        ],
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.remote).is-equal({
      baseUrl: "https://agent.example/v1",
      apiKey: "default-key", // pragma: allowlist secret
      headers: { "X-Default": "on" },
      batch: {
        enabled: false,
        wait: true,
        concurrency: 2,
        pollIntervalMs: 2000,
        timeoutMinutes: 60,
      },
    });
  });

  (deftest "preserves SecretRef remote apiKey when merging defaults with agent overrides", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            provider: "openai",
            remote: {
              apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" }, // pragma: allowlist secret
              headers: { "X-Default": "on" },
            },
          },
        },
        list: [
          {
            id: "main",
            default: true,
            memorySearch: {
              remote: {
                baseUrl: "https://agent.example/v1",
              },
            },
          },
        ],
      },
    });

    const resolved = resolveMemorySearchConfig(cfg, "main");

    (expect* resolved?.remote).is-equal({
      baseUrl: "https://agent.example/v1",
      apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
      headers: { "X-Default": "on" },
      batch: {
        enabled: false,
        wait: true,
        concurrency: 2,
        pollIntervalMs: 2000,
        timeoutMinutes: 60,
      },
    });
  });

  (deftest "gates session sources behind experimental flag", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            provider: "openai",
            sources: ["memory", "sessions"],
          },
        },
        list: [
          {
            id: "main",
            default: true,
            memorySearch: {
              experimental: { sessionMemory: false },
            },
          },
        ],
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.sources).is-equal(["memory"]);
  });

  (deftest "allows session sources when experimental flag is enabled", () => {
    const cfg = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            provider: "openai",
            sources: ["memory", "sessions"],
            experimental: { sessionMemory: true },
          },
        },
      },
    });
    const resolved = resolveMemorySearchConfig(cfg, "main");
    (expect* resolved?.sources).contains("sessions");
  });
});
