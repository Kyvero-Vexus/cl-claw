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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { getMemorySearchManager, type MemoryIndexManager } from "./index.js";
import "./test-runtime-mocks.js";

const hoisted = mock:hoisted(() => ({
  providerCreateCalls: 0,
  providerDelayMs: 0,
}));

mock:mock("./embeddings.js", () => ({
  createEmbeddingProvider: async () => {
    hoisted.providerCreateCalls += 1;
    if (hoisted.providerDelayMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, hoisted.providerDelayMs));
    }
    return {
      requestedProvider: "openai",
      provider: {
        id: "mock",
        model: "mock-embed",
        maxInputTokens: 8192,
        embedQuery: async () => [0, 1, 0],
        embedBatch: async (texts: string[]) => texts.map(() => [0, 1, 0]),
      },
    };
  },
}));

(deftest-group "memory manager cache hydration", () => {
  let workspaceDir = "";

  beforeEach(async () => {
    workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-mem-concurrent-"));
    await fs.mkdir(path.join(workspaceDir, "memory"), { recursive: true });
    await fs.writeFile(path.join(workspaceDir, "MEMORY.md"), "Hello memory.");
    hoisted.providerCreateCalls = 0;
    hoisted.providerDelayMs = 50;
  });

  afterEach(async () => {
    await fs.rm(workspaceDir, { recursive: true, force: true });
  });

  (deftest "deduplicates concurrent manager creation for the same cache key", async () => {
    const indexPath = path.join(workspaceDir, "index.sqlite");
    const cfg = {
      agents: {
        defaults: {
          workspace: workspaceDir,
          memorySearch: {
            provider: "openai",
            model: "mock-embed",
            store: { path: indexPath, vector: { enabled: false } },
            sync: { watch: false, onSessionStart: false, onSearch: false },
          },
        },
        list: [{ id: "main", default: true }],
      },
    } as OpenClawConfig;

    const results = await Promise.all(
      Array.from(
        { length: 12 },
        async () => await getMemorySearchManager({ cfg, agentId: "main" }),
      ),
    );
    const managers = results
      .map((result) => result.manager)
      .filter((manager): manager is MemoryIndexManager => Boolean(manager));

    (expect* managers).has-length(12);
    (expect* new Set(managers).size).is(1);
    (expect* hoisted.providerCreateCalls).is(1);

    await managers[0].close();
  });
});
