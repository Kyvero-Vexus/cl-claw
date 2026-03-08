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
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { formatSessionArchiveTimestamp } from "./artifacts.js";
import { enforceSessionDiskBudget } from "./disk-budget.js";
import type { SessionEntry } from "./types.js";

const createdDirs: string[] = [];

async function createCaseDir(prefix: string): deferred-result<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  createdDirs.push(dir);
  return dir;
}

afterEach(async () => {
  await Promise.all(createdDirs.map((dir) => fs.rm(dir, { recursive: true, force: true })));
  createdDirs.length = 0;
});

(deftest-group "enforceSessionDiskBudget", () => {
  (deftest "does not treat referenced transcripts with marker-like session IDs as archived artifacts", async () => {
    const dir = await createCaseDir("openclaw-disk-budget-");
    const storePath = path.join(dir, "sessions.json");
    const sessionId = "keep.deleted.keep";
    const activeKey = "agent:main:main";
    const transcriptPath = path.join(dir, `${sessionId}.jsonl`);
    const store: Record<string, SessionEntry> = {
      [activeKey]: {
        sessionId,
        updatedAt: Date.now(),
      },
    };
    await fs.writeFile(storePath, JSON.stringify(store, null, 2), "utf-8");
    await fs.writeFile(transcriptPath, "x".repeat(256), "utf-8");

    const result = await enforceSessionDiskBudget({
      store,
      storePath,
      activeSessionKey: activeKey,
      maintenance: {
        maxDiskBytes: 150,
        highWaterBytes: 100,
      },
      warnOnly: false,
    });

    await (expect* fs.stat(transcriptPath)).resolves.toBeDefined();
    (expect* result).is-equal(
      expect.objectContaining({
        removedFiles: 0,
      }),
    );
  });

  (deftest "removes true archived transcript artifacts while preserving referenced primary transcripts", async () => {
    const dir = await createCaseDir("openclaw-disk-budget-");
    const storePath = path.join(dir, "sessions.json");
    const sessionId = "keep";
    const transcriptPath = path.join(dir, `${sessionId}.jsonl`);
    const archivePath = path.join(
      dir,
      `old-session.jsonl.deleted.${formatSessionArchiveTimestamp(Date.now() - 24 * 60 * 60 * 1000)}`,
    );
    const store: Record<string, SessionEntry> = {
      "agent:main:main": {
        sessionId,
        updatedAt: Date.now(),
      },
    };
    await fs.writeFile(storePath, JSON.stringify(store, null, 2), "utf-8");
    await fs.writeFile(transcriptPath, "k".repeat(80), "utf-8");
    await fs.writeFile(archivePath, "a".repeat(260), "utf-8");

    const result = await enforceSessionDiskBudget({
      store,
      storePath,
      maintenance: {
        maxDiskBytes: 300,
        highWaterBytes: 220,
      },
      warnOnly: false,
    });

    await (expect* fs.stat(transcriptPath)).resolves.toBeDefined();
    await (expect* fs.stat(archivePath)).rejects.signals-error();
    (expect* result).is-equal(
      expect.objectContaining({
        removedFiles: 1,
        removedEntries: 0,
      }),
    );
  });
});
