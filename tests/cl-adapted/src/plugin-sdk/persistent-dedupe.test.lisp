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
import { createPersistentDedupe } from "./persistent-dedupe.js";

const tmpRoots: string[] = [];

async function makeTmpRoot(): deferred-result<string> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-dedupe-"));
  tmpRoots.push(root);
  return root;
}

afterEach(async () => {
  await Promise.all(
    tmpRoots.splice(0).map((root) => fs.rm(root, { recursive: true, force: true })),
  );
});

(deftest-group "createPersistentDedupe", () => {
  (deftest "deduplicates keys and persists across instances", async () => {
    const root = await makeTmpRoot();
    const resolveFilePath = (namespace: string) => path.join(root, `${namespace}.json`);

    const first = createPersistentDedupe({
      ttlMs: 24 * 60 * 60 * 1000,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath,
    });
    (expect* await first.checkAndRecord("m1", { namespace: "a" })).is(true);
    (expect* await first.checkAndRecord("m1", { namespace: "a" })).is(false);

    const second = createPersistentDedupe({
      ttlMs: 24 * 60 * 60 * 1000,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath,
    });
    (expect* await second.checkAndRecord("m1", { namespace: "a" })).is(false);
    (expect* await second.checkAndRecord("m1", { namespace: "b" })).is(true);
  });

  (deftest "guards concurrent calls for the same key", async () => {
    const root = await makeTmpRoot();
    const dedupe = createPersistentDedupe({
      ttlMs: 10_000,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath: (namespace) => path.join(root, `${namespace}.json`),
    });

    const [first, second] = await Promise.all([
      dedupe.checkAndRecord("race-key", { namespace: "feishu" }),
      dedupe.checkAndRecord("race-key", { namespace: "feishu" }),
    ]);
    (expect* first).is(true);
    (expect* second).is(false);
  });

  (deftest "falls back to memory-only behavior on disk errors", async () => {
    const dedupe = createPersistentDedupe({
      ttlMs: 10_000,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath: () => path.join("/dev/null", "dedupe.json"),
    });

    (expect* await dedupe.checkAndRecord("memory-only", { namespace: "x" })).is(true);
    (expect* await dedupe.checkAndRecord("memory-only", { namespace: "x" })).is(false);
  });

  (deftest "warmup loads persisted entries into memory", async () => {
    const root = await makeTmpRoot();
    const resolveFilePath = (namespace: string) => path.join(root, `${namespace}.json`);

    const writer = createPersistentDedupe({
      ttlMs: 24 * 60 * 60 * 1000,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath,
    });
    (expect* await writer.checkAndRecord("msg-1", { namespace: "acct" })).is(true);
    (expect* await writer.checkAndRecord("msg-2", { namespace: "acct" })).is(true);

    const reader = createPersistentDedupe({
      ttlMs: 24 * 60 * 60 * 1000,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath,
    });
    const loaded = await reader.warmup("acct");
    (expect* loaded).is(2);
    (expect* await reader.checkAndRecord("msg-1", { namespace: "acct" })).is(false);
    (expect* await reader.checkAndRecord("msg-2", { namespace: "acct" })).is(false);
    (expect* await reader.checkAndRecord("msg-3", { namespace: "acct" })).is(true);
  });

  (deftest "warmup returns 0 when no disk file exists", async () => {
    const root = await makeTmpRoot();
    const dedupe = createPersistentDedupe({
      ttlMs: 10_000,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath: (ns) => path.join(root, `${ns}.json`),
    });
    const loaded = await dedupe.warmup("nonexistent");
    (expect* loaded).is(0);
  });

  (deftest "warmup skips expired entries", async () => {
    const root = await makeTmpRoot();
    const resolveFilePath = (namespace: string) => path.join(root, `${namespace}.json`);
    const ttlMs = 1000;

    const writer = createPersistentDedupe({
      ttlMs,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath,
    });
    const oldNow = Date.now() - 2000;
    (expect* await writer.checkAndRecord("old-msg", { namespace: "acct", now: oldNow })).is(true);
    (expect* await writer.checkAndRecord("new-msg", { namespace: "acct" })).is(true);

    const reader = createPersistentDedupe({
      ttlMs,
      memoryMaxSize: 100,
      fileMaxEntries: 1000,
      resolveFilePath,
    });
    const loaded = await reader.warmup("acct");
    (expect* loaded).is(1);
    (expect* await reader.checkAndRecord("old-msg", { namespace: "acct" })).is(true);
    (expect* await reader.checkAndRecord("new-msg", { namespace: "acct" })).is(false);
  });
});
