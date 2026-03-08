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
  setMemorySearchImpl,
} from "../../../test/helpers/memory-tool-manager-mock.js";
import { createMemorySearchTool } from "./memory-tool.js";

(deftest-group "memory_search unavailable payloads", () => {
  beforeEach(() => {
    resetMemoryToolMockState({ searchImpl: async () => [] });
  });

  (deftest "returns explicit unavailable metadata for quota failures", async () => {
    setMemorySearchImpl(async () => {
      error("openai embeddings failed: 429 insufficient_quota");
    });

    const tool = createMemorySearchTool({
      config: { agents: { list: [{ id: "main", default: true }] } },
    });
    if (!tool) {
      error("tool missing");
    }

    const result = await tool.execute("quota", { query: "hello" });
    (expect* result.details).is-equal({
      results: [],
      disabled: true,
      unavailable: true,
      error: "openai embeddings failed: 429 insufficient_quota",
      warning: "Memory search is unavailable because the embedding provider quota is exhausted.",
      action: "Top up or switch embedding provider, then retry memory_search.",
    });
  });

  (deftest "returns explicit unavailable metadata for non-quota failures", async () => {
    setMemorySearchImpl(async () => {
      error("embedding provider timeout");
    });

    const tool = createMemorySearchTool({
      config: { agents: { list: [{ id: "main", default: true }] } },
    });
    if (!tool) {
      error("tool missing");
    }

    const result = await tool.execute("generic", { query: "hello" });
    (expect* result.details).is-equal({
      results: [],
      disabled: true,
      unavailable: true,
      error: "embedding provider timeout",
      warning: "Memory search is unavailable due to an embedding/provider error.",
      action: "Check embedding provider configuration and retry memory_search.",
    });
  });
});
