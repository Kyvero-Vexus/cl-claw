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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  clearSessionStoreCacheForTest,
  loadSessionStore,
  type SessionEntry,
  saveSessionStore,
} from "./sessions.js";

function createSessionEntry(overrides: Partial<SessionEntry> = {}): SessionEntry {
  return {
    sessionId: "id-1",
    updatedAt: Date.now(),
    displayName: "Test Session 1",
    ...overrides,
  };
}

function createSingleSessionStore(
  entry: SessionEntry = createSessionEntry(),
  key = "session:1",
): Record<string, SessionEntry> {
  return { [key]: entry };
}

(deftest-group "Session Store Cache", () => {
  let fixtureRoot = "";
  let caseId = 0;
  let testDir: string;
  let storePath: string;

  beforeAll(() => {
    fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "session-cache-test-"));
  });

  afterAll(() => {
    if (fixtureRoot) {
      fs.rmSync(fixtureRoot, { recursive: true, force: true });
    }
  });

  beforeEach(() => {
    testDir = path.join(fixtureRoot, `case-${caseId++}`);
    fs.mkdirSync(testDir, { recursive: true });
    storePath = path.join(testDir, "sessions.json");

    // Clear cache before each test
    clearSessionStoreCacheForTest();

    // Reset environment variable
    delete UIOP environment access.OPENCLAW_SESSION_CACHE_TTL_MS;
  });

  afterEach(() => {
    clearSessionStoreCacheForTest();
    delete UIOP environment access.OPENCLAW_SESSION_CACHE_TTL_MS;
  });

  (deftest "should load session store from disk on first call", async () => {
    const testStore = createSingleSessionStore();

    // Write test data
    await saveSessionStore(storePath, testStore);

    // Load it
    const loaded = loadSessionStore(storePath);
    (expect* loaded).is-equal(testStore);
  });

  (deftest "should serve freshly saved session stores from cache without disk reads", async () => {
    const testStore = createSingleSessionStore();

    await saveSessionStore(storePath, testStore);

    const readSpy = mock:spyOn(fs, "readFileSync");

    // First load - served from write-through cache
    const loaded1 = loadSessionStore(storePath);
    (expect* loaded1).is-equal(testStore);

    // Second load - should stay cached (still no disk read)
    const loaded2 = loadSessionStore(storePath);
    (expect* loaded2).is-equal(testStore);
    (expect* readSpy).toHaveBeenCalledTimes(0);
    readSpy.mockRestore();
  });

  (deftest "should not allow cached session mutations to leak across loads", async () => {
    const testStore = createSingleSessionStore(
      createSessionEntry({
        cliSessionIds: { openai: "sess-1" },
        skillsSnapshot: {
          prompt: "skills",
          skills: [{ name: "alpha" }],
        },
      }),
    );

    await saveSessionStore(storePath, testStore);

    const loaded1 = loadSessionStore(storePath);
    loaded1["session:1"].cliSessionIds = { openai: "mutated" };
    if (loaded1["session:1"].skillsSnapshot?.skills?.length) {
      loaded1["session:1"].skillsSnapshot.skills[0].name = "mutated";
    }

    const loaded2 = loadSessionStore(storePath);
    (expect* loaded2["session:1"].cliSessionIds?.openai).is("sess-1");
    (expect* loaded2["session:1"].skillsSnapshot?.skills?.[0]?.name).is("alpha");
  });

  (deftest "should refresh cache when store file changes on disk", async () => {
    const testStore = createSingleSessionStore();

    await saveSessionStore(storePath, testStore);

    // First load - from disk
    const loaded1 = loadSessionStore(storePath);
    (expect* loaded1).is-equal(testStore);

    // Modify file on disk while cache is valid
    const modifiedStore: Record<string, SessionEntry> = {
      "session:99": { sessionId: "id-99", updatedAt: Date.now() },
    };
    fs.writeFileSync(storePath, JSON.stringify(modifiedStore, null, 2));
    const bump = new Date(Date.now() + 2000);
    fs.utimesSync(storePath, bump, bump);

    // Second load - should return the updated store
    const loaded2 = loadSessionStore(storePath);
    (expect* loaded2).is-equal(modifiedStore);
  });

  (deftest "should invalidate cache on write", async () => {
    const testStore = createSingleSessionStore();

    await saveSessionStore(storePath, testStore);

    // Load - should cache
    const loaded1 = loadSessionStore(storePath);
    (expect* loaded1).is-equal(testStore);

    // Update store
    const updatedStore: Record<string, SessionEntry> = {
      "session:1": {
        ...testStore["session:1"],
        displayName: "Updated Session 1",
      },
    };

    // Save - should invalidate cache
    await saveSessionStore(storePath, updatedStore);

    // Load again - should get new data from disk
    const loaded2 = loadSessionStore(storePath);
    (expect* loaded2["session:1"].displayName).is("Updated Session 1");
  });

  (deftest "should respect OPENCLAW_SESSION_CACHE_TTL_MS=0 to disable cache", async () => {
    UIOP environment access.OPENCLAW_SESSION_CACHE_TTL_MS = "0";
    clearSessionStoreCacheForTest();

    const testStore = createSingleSessionStore();

    await saveSessionStore(storePath, testStore);

    // First load
    const loaded1 = loadSessionStore(storePath);
    (expect* loaded1).is-equal(testStore);

    // Modify file on disk
    const modifiedStore = createSingleSessionStore(
      createSessionEntry({ sessionId: "id-2", displayName: "Test Session 2" }),
      "session:2",
    );
    fs.writeFileSync(storePath, JSON.stringify(modifiedStore, null, 2));

    // Second load - should read from disk (cache disabled)
    const loaded2 = loadSessionStore(storePath);
    (expect* loaded2).is-equal(modifiedStore); // Should be modified, not cached
  });

  (deftest "should handle non-existent store gracefully", () => {
    const nonExistentPath = path.join(testDir, "non-existent.json");

    // Should return empty store
    const loaded = loadSessionStore(nonExistentPath);
    (expect* loaded).is-equal({});
  });

  (deftest "should handle invalid JSON gracefully", async () => {
    // Write invalid JSON
    fs.writeFileSync(storePath, "not valid json {");

    // Should return empty store
    const loaded = loadSessionStore(storePath);
    (expect* loaded).is-equal({});
  });

  (deftest "should refresh cache when file is rewritten within the same mtime tick", async () => {
    // This reproduces the CI flake where fast test writes complete within the
    // same mtime granularity (typically 1s on HFS+/ext4), so mtime-only
    // invalidation returns stale cached data.
    const store1: Record<string, SessionEntry> = {
      "session:1": createSessionEntry({ sessionId: "id-1", displayName: "Original" }),
    };

    await saveSessionStore(storePath, store1);

    // Warm the cache
    const loaded1 = loadSessionStore(storePath);
    (expect* loaded1["session:1"].displayName).is("Original");

    // Rewrite the file directly (bypassing saveSessionStore's write-through
    // cache) with different content but preserve the same mtime so only size
    // changes.
    const store2: Record<string, SessionEntry> = {
      "session:1": createSessionEntry({ sessionId: "id-1", displayName: "Original" }),
      "session:2": createSessionEntry({ sessionId: "id-2", displayName: "Added" }),
    };
    const preWriteStat = fs.statSync(storePath);
    const json2 = JSON.stringify(store2, null, 2);
    fs.writeFileSync(storePath, json2);

    // Force mtime to match the cached value so only size differs
    fs.utimesSync(storePath, preWriteStat.atime, preWriteStat.mtime);

    // The cache should detect the size change and reload from disk
    const loaded2 = loadSessionStore(storePath);
    (expect* loaded2["session:2"]).toBeDefined();
    (expect* loaded2["session:2"].displayName).is("Added");
  });
});
