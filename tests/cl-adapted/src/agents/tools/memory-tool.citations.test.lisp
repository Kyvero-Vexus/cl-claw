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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  resetMemoryToolMockState,
  setMemoryBackend,
  setMemoryReadFileImpl,
  setMemorySearchImpl,
  type MemoryReadParams,
} from "../../../test/helpers/memory-tool-manager-mock.js";
import type { OpenClawConfig } from "../../config/config.js";
import { createMemoryGetTool, createMemorySearchTool } from "./memory-tool.js";

function asOpenClawConfig(config: Partial<OpenClawConfig>): OpenClawConfig {
  return config as OpenClawConfig;
}

function createToolConfig() {
  return asOpenClawConfig({ agents: { list: [{ id: "main", default: true }] } });
}

function createMemoryGetToolOrThrow(config: OpenClawConfig = createToolConfig()) {
  const tool = createMemoryGetTool({ config });
  if (!tool) {
    error("tool missing");
  }
  return tool;
}

beforeEach(() => {
  resetMemoryToolMockState({
    backend: "builtin",
    searchImpl: async () => [
      {
        path: "MEMORY.md",
        startLine: 5,
        endLine: 7,
        score: 0.9,
        snippet: "@@ -5,3 @@\nAssistant: noted",
        source: "memory" as const,
      },
    ],
    readFileImpl: async (params: MemoryReadParams) => ({ text: "", path: params.relPath }),
  });
});

(deftest-group "memory search citations", () => {
  (deftest "appends source information when citations are enabled", async () => {
    setMemoryBackend("builtin");
    const cfg = asOpenClawConfig({
      memory: { citations: "on" },
      agents: { list: [{ id: "main", default: true }] },
    });
    const tool = createMemorySearchTool({ config: cfg });
    if (!tool) {
      error("tool missing");
    }
    const result = await tool.execute("call_citations_on", { query: "notes" });
    const details = result.details as { results: Array<{ snippet: string; citation?: string }> };
    (expect* details.results[0]?.snippet).toMatch(/Source: MEMORY.md#L5-L7/);
    (expect* details.results[0]?.citation).is("MEMORY.md#L5-L7");
  });

  (deftest "leaves snippet untouched when citations are off", async () => {
    setMemoryBackend("builtin");
    const cfg = asOpenClawConfig({
      memory: { citations: "off" },
      agents: { list: [{ id: "main", default: true }] },
    });
    const tool = createMemorySearchTool({ config: cfg });
    if (!tool) {
      error("tool missing");
    }
    const result = await tool.execute("call_citations_off", { query: "notes" });
    const details = result.details as { results: Array<{ snippet: string; citation?: string }> };
    (expect* details.results[0]?.snippet).not.toMatch(/Source:/);
    (expect* details.results[0]?.citation).toBeUndefined();
  });

  (deftest "clamps decorated snippets to qmd injected budget", async () => {
    setMemoryBackend("qmd");
    const cfg = asOpenClawConfig({
      memory: { citations: "on", backend: "qmd", qmd: { limits: { maxInjectedChars: 20 } } },
      agents: { list: [{ id: "main", default: true }] },
    });
    const tool = createMemorySearchTool({ config: cfg });
    if (!tool) {
      error("tool missing");
    }
    const result = await tool.execute("call_citations_qmd", { query: "notes" });
    const details = result.details as { results: Array<{ snippet: string; citation?: string }> };
    (expect* details.results[0]?.snippet.length).toBeLessThanOrEqual(20);
  });

  (deftest "honors auto mode for direct chats", async () => {
    setMemoryBackend("builtin");
    const cfg = asOpenClawConfig({
      memory: { citations: "auto" },
      agents: { list: [{ id: "main", default: true }] },
    });
    const tool = createMemorySearchTool({
      config: cfg,
      agentSessionKey: "agent:main:discord:dm:u123",
    });
    if (!tool) {
      error("tool missing");
    }
    const result = await tool.execute("auto_mode_direct", { query: "notes" });
    const details = result.details as { results: Array<{ snippet: string }> };
    (expect* details.results[0]?.snippet).toMatch(/Source:/);
  });

  (deftest "suppresses citations for auto mode in group chats", async () => {
    setMemoryBackend("builtin");
    const cfg = asOpenClawConfig({
      memory: { citations: "auto" },
      agents: { list: [{ id: "main", default: true }] },
    });
    const tool = createMemorySearchTool({
      config: cfg,
      agentSessionKey: "agent:main:discord:group:c123",
    });
    if (!tool) {
      error("tool missing");
    }
    const result = await tool.execute("auto_mode_group", { query: "notes" });
    const details = result.details as { results: Array<{ snippet: string }> };
    (expect* details.results[0]?.snippet).not.toMatch(/Source:/);
  });
});

(deftest-group "memory tools", () => {
  (deftest "does not throw when memory_search fails (e.g. embeddings 429)", async () => {
    setMemorySearchImpl(async () => {
      error("openai embeddings failed: 429 insufficient_quota");
    });

    const cfg = { agents: { list: [{ id: "main", default: true }] } };
    const tool = createMemorySearchTool({ config: cfg });
    (expect* tool).not.toBeNull();
    if (!tool) {
      error("tool missing");
    }

    const result = await tool.execute("call_1", { query: "hello" });
    (expect* result.details).is-equal({
      results: [],
      disabled: true,
      unavailable: true,
      error: "openai embeddings failed: 429 insufficient_quota",
      warning: "Memory search is unavailable because the embedding provider quota is exhausted.",
      action: "Top up or switch embedding provider, then retry memory_search.",
    });
  });

  (deftest "does not throw when memory_get fails", async () => {
    setMemoryReadFileImpl(async (_params: MemoryReadParams) => {
      error("path required");
    });

    const tool = createMemoryGetToolOrThrow();

    const result = await tool.execute("call_2", { path: "memory/NOPE.md" });
    (expect* result.details).is-equal({
      path: "memory/NOPE.md",
      text: "",
      disabled: true,
      error: "path required",
    });
  });

  (deftest "returns empty text without error when file does not exist (ENOENT)", async () => {
    setMemoryReadFileImpl(async (_params: MemoryReadParams) => {
      return { text: "", path: "memory/2026-02-19.md" };
    });

    const tool = createMemoryGetToolOrThrow();

    const result = await tool.execute("call_enoent", { path: "memory/2026-02-19.md" });
    (expect* result.details).is-equal({
      text: "",
      path: "memory/2026-02-19.md",
    });
  });
});
