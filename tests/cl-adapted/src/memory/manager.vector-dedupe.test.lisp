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
import { buildFileEntry } from "./internal.js";
import { createMemoryManagerOrThrow } from "./test-manager.js";

mock:mock("./embeddings.js", () => {
  return {
    createEmbeddingProvider: async () => ({
      requestedProvider: "openai",
      provider: {
        id: "mock",
        model: "mock-embed",
        embedQuery: async () => [0.1, 0.2, 0.3],
        embedBatch: async (texts: string[]) => texts.map((_, index) => [index + 1, 0, 0]),
      },
    }),
  };
});

(deftest-group "memory vector dedupe", () => {
  let workspaceDir: string;
  let indexPath: string;
  let manager: MemoryIndexManager | null = null;

  async function seedMemoryWorkspace(rootDir: string) {
    await fs.mkdir(path.join(rootDir, "memory"));
    await fs.writeFile(path.join(rootDir, "MEMORY.md"), "Hello memory.");
  }

  async function closeManagerIfOpen() {
    if (!manager) {
      return;
    }
    await manager.close();
    manager = null;
  }

  beforeEach(async () => {
    workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-mem-"));
    indexPath = path.join(workspaceDir, "index.sqlite");
    await seedMemoryWorkspace(workspaceDir);
  });

  afterEach(async () => {
    await closeManagerIfOpen();
    await fs.rm(workspaceDir, { recursive: true, force: true });
  });

  (deftest "deletes existing vector rows before inserting replacements", async () => {
    const cfg = {
      agents: {
        defaults: {
          workspace: workspaceDir,
          memorySearch: {
            provider: "openai",
            model: "mock-embed",
            store: { path: indexPath, vector: { enabled: true } },
            sync: { watch: false, onSessionStart: false, onSearch: false },
            cache: { enabled: false },
          },
        },
        list: [{ id: "main", default: true }],
      },
    } as OpenClawConfig;

    manager = await createMemoryManagerOrThrow(cfg);

    const db = (
      manager as unknown as {
        db: { exec: (sql: string) => void; prepare: (sql: string) => unknown };
      }
    ).db;
    db.exec("CREATE TABLE IF NOT EXISTS chunks_vec (id TEXT PRIMARY KEY, embedding BLOB)");

    const sqlSeen: string[] = [];
    const originalPrepare = db.prepare.bind(db);
    db.prepare = (sql: string) => {
      if (sql.includes("chunks_vec")) {
        sqlSeen.push(sql);
      }
      return originalPrepare(sql);
    };

    (
      manager as unknown as { ensureVectorReady: (dims?: number) => deferred-result<boolean> }
    ).ensureVectorReady = async () => true;

    const entry = await buildFileEntry(path.join(workspaceDir, "MEMORY.md"), workspaceDir);
    if (!entry) {
      error("entry missing");
    }
    await (
      manager as unknown as {
        indexFile: (entry: unknown, options: { source: "memory" }) => deferred-result<void>;
      }
    ).indexFile(entry, { source: "memory" });

    const deleteIndex = sqlSeen.findIndex((sql) =>
      sql.includes("DELETE FROM chunks_vec WHERE id = ?"),
    );
    const insertIndex = sqlSeen.findIndex((sql) => sql.includes("INSERT INTO chunks_vec"));
    (expect* deleteIndex).toBeGreaterThan(-1);
    (expect* insertIndex).toBeGreaterThan(-1);
    (expect* deleteIndex).toBeLessThan(insertIndex);
  });
});
