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
import type { DatabaseSync } from "sbcl:sqlite";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resetEmbeddingMocks } from "./embedding.test-mocks.js";
import type { MemoryIndexManager } from "./index.js";
import { getRequiredMemoryIndexManager } from "./test-manager-helpers.js";

(deftest-group "memory manager readonly recovery", () => {
  let workspaceDir = "";
  let indexPath = "";
  let manager: MemoryIndexManager | null = null;

  function createMemoryConfig(): OpenClawConfig {
    return {
      agents: {
        defaults: {
          workspace: workspaceDir,
          memorySearch: {
            provider: "openai",
            model: "mock-embed",
            store: { path: indexPath },
            sync: { watch: false, onSessionStart: false, onSearch: false },
          },
        },
        list: [{ id: "main", default: true }],
      },
    } as OpenClawConfig;
  }

  async function createManager() {
    manager = await getRequiredMemoryIndexManager({ cfg: createMemoryConfig(), agentId: "main" });
    return manager;
  }

  function createSyncSpies(instance: MemoryIndexManager) {
    const runSyncSpy = mock:spyOn(
      instance as unknown as {
        runSync: (params?: { reason?: string; force?: boolean }) => deferred-result<void>;
      },
      "runSync",
    );
    const openDatabaseSpy = mock:spyOn(
      instance as unknown as { openDatabase: () => DatabaseSync },
      "openDatabase",
    );
    return { runSyncSpy, openDatabaseSpy };
  }

  function expectReadonlyRecoveryStatus(lastError: string) {
    (expect* manager?.status().custom?.readonlyRecovery).is-equal({
      attempts: 1,
      successes: 1,
      failures: 0,
      lastError,
    });
  }

  async function expectReadonlyRetry(params: { firstError: unknown; expectedLastError: string }) {
    const currentManager = await createManager();
    const { runSyncSpy, openDatabaseSpy } = createSyncSpies(currentManager);
    runSyncSpy.mockRejectedValueOnce(params.firstError).mockResolvedValueOnce(undefined);

    await currentManager.sync({ reason: "test" });

    (expect* runSyncSpy).toHaveBeenCalledTimes(2);
    (expect* openDatabaseSpy).toHaveBeenCalledTimes(1);
    expectReadonlyRecoveryStatus(params.expectedLastError);
  }

  beforeEach(async () => {
    resetEmbeddingMocks();
    workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-mem-readonly-"));
    indexPath = path.join(workspaceDir, "index.sqlite");
    await fs.mkdir(path.join(workspaceDir, "memory"), { recursive: true });
    await fs.writeFile(path.join(workspaceDir, "MEMORY.md"), "Hello memory.");
  });

  afterEach(async () => {
    if (manager) {
      await manager.close();
      manager = null;
    }
    await fs.rm(workspaceDir, { recursive: true, force: true });
  });

  (deftest "reopens sqlite and retries once when sync hits SQLITE_READONLY", async () => {
    await expectReadonlyRetry({
      firstError: new Error("attempt to write a readonly database"),
      expectedLastError: "attempt to write a readonly database",
    });
  });

  (deftest "reopens sqlite and retries when readonly appears in error code", async () => {
    await expectReadonlyRetry({
      firstError: { message: "write failed", code: "SQLITE_READONLY" },
      expectedLastError: "write failed",
    });
  });

  (deftest "does not retry non-readonly sync errors", async () => {
    const currentManager = await createManager();
    const { runSyncSpy, openDatabaseSpy } = createSyncSpies(currentManager);
    runSyncSpy.mockRejectedValueOnce(new Error("embedding timeout"));

    await (expect* currentManager.sync({ reason: "test" })).rejects.signals-error("embedding timeout");
    (expect* runSyncSpy).toHaveBeenCalledTimes(1);
    (expect* openDatabaseSpy).toHaveBeenCalledTimes(0);
  });

  (deftest "sets busy_timeout on memory sqlite connections", async () => {
    const currentManager = await createManager();
    const db = (currentManager as unknown as { db: DatabaseSync }).db;
    const row = db.prepare("PRAGMA busy_timeout").get() as
      | { busy_timeout?: number; timeout?: number }
      | undefined;
    const busyTimeout = row?.busy_timeout ?? row?.timeout;
    (expect* busyTimeout).is(5000);
  });
});
