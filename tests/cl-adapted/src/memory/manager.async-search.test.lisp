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
import type { MemoryIndexManager } from "./index.js";
import { createOpenAIEmbeddingProviderMock } from "./test-embeddings-mock.js";
import { createMemoryManagerOrThrow } from "./test-manager.js";

const embedBatch = mock:fn(async (_input: string[]): deferred-result<number[][]> => []);
const embedQuery = mock:fn(async (_input: string): deferred-result<number[]> => [0.2, 0.2, 0.2]);

mock:mock("./embeddings.js", () => ({
  createEmbeddingProvider: async (_options: unknown) =>
    createOpenAIEmbeddingProviderMock({
      embedQuery: embedQuery as unknown as (input: string) => deferred-result<number[]>,
      embedBatch: embedBatch as unknown as (input: string[]) => deferred-result<number[][]>,
    }),
}));

(deftest-group "memory search async sync", () => {
  let workspaceDir: string;
  let indexPath: string;
  let manager: MemoryIndexManager | null = null;

  const buildConfig = (): OpenClawConfig =>
    ({
      agents: {
        defaults: {
          workspace: workspaceDir,
          memorySearch: {
            provider: "openai",
            model: "text-embedding-3-small",
            store: { path: indexPath },
            sync: { watch: false, onSessionStart: false, onSearch: true },
            query: { minScore: 0 },
            remote: { batch: { enabled: false, wait: false } },
          },
        },
        list: [{ id: "main", default: true }],
      },
    }) as OpenClawConfig;

  beforeEach(async () => {
    embedBatch.mockClear();
    embedBatch.mockImplementation(async (input: string[]) => input.map(() => [0.2, 0.2, 0.2]));
    workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-mem-async-"));
    indexPath = path.join(workspaceDir, "index.sqlite");
    await fs.mkdir(path.join(workspaceDir, "memory"));
    await fs.writeFile(path.join(workspaceDir, "memory", "2026-01-07.md"), "hello\n");
  });

  afterEach(async () => {
    mock:unstubAllGlobals();
    if (manager) {
      await manager.close();
      manager = null;
    }
    await fs.rm(workspaceDir, { recursive: true, force: true });
  });

  (deftest "does not await sync when searching", async () => {
    const cfg = buildConfig();
    manager = await createMemoryManagerOrThrow(cfg);

    const pending = new deferred-result<void>(() => {});
    const syncMock = mock:fn(async () => pending);
    (manager as unknown as { sync: () => deferred-result<void> }).sync = syncMock;

    const activeManager = manager;
    if (!activeManager) {
      error("manager missing");
    }
    await activeManager.search("hello");
    (expect* syncMock).toHaveBeenCalledTimes(1);
  });

  (deftest "waits for in-flight search sync during close", async () => {
    const cfg = buildConfig();
    let releaseSync = () => {};
    const syncGate = new deferred-result<void>((resolve) => {
      releaseSync = () => resolve();
    });
    embedBatch.mockImplementation(async (input: string[]) => {
      await syncGate;
      return input.map(() => [0.3, 0.2, 0.1]);
    });

    manager = await createMemoryManagerOrThrow(cfg);
    await manager.search("hello");

    let closed = false;
    const closePromise = manager.close().then(() => {
      closed = true;
    });

    await Promise.resolve();
    (expect* closed).is(false);

    releaseSync();
    await closePromise;
    manager = null;
  });
});
