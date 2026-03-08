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
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  cacheSticker,
  getAllCachedStickers,
  getCachedSticker,
  getCacheStats,
  searchStickers,
} from "./sticker-cache.js";

// Mock the state directory to use a temp location
mock:mock("../config/paths.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/paths.js")>();
  return {
    ...actual,
    STATE_DIR: "/tmp/openclaw-test-sticker-cache",
  };
});

const TEST_CACHE_DIR = "/tmp/openclaw-test-sticker-cache/telegram";
const TEST_CACHE_FILE = path.join(TEST_CACHE_DIR, "sticker-cache.json");

(deftest-group "sticker-cache", () => {
  beforeEach(() => {
    // Clean up before each test
    if (fs.existsSync(TEST_CACHE_FILE)) {
      fs.unlinkSync(TEST_CACHE_FILE);
    }
  });

  afterEach(() => {
    // Clean up after each test
    if (fs.existsSync(TEST_CACHE_FILE)) {
      fs.unlinkSync(TEST_CACHE_FILE);
    }
  });

  (deftest-group "getCachedSticker", () => {
    (deftest "returns null for unknown ID", () => {
      const result = getCachedSticker("unknown-id");
      (expect* result).toBeNull();
    });

    (deftest "returns cached sticker after cacheSticker", () => {
      const sticker = {
        fileId: "file123",
        fileUniqueId: "unique123",
        emoji: "🎉",
        setName: "TestPack",
        description: "A party popper emoji sticker",
        cachedAt: "2026-01-26T12:00:00.000Z",
      };

      cacheSticker(sticker);
      const result = getCachedSticker("unique123");

      (expect* result).is-equal(sticker);
    });

    (deftest "returns null after cache is cleared", () => {
      const sticker = {
        fileId: "file123",
        fileUniqueId: "unique123",
        description: "test",
        cachedAt: "2026-01-26T12:00:00.000Z",
      };

      cacheSticker(sticker);
      (expect* getCachedSticker("unique123")).not.toBeNull();

      // Manually clear the cache file
      fs.unlinkSync(TEST_CACHE_FILE);

      (expect* getCachedSticker("unique123")).toBeNull();
    });
  });

  (deftest-group "cacheSticker", () => {
    (deftest "adds entry to cache", () => {
      const sticker = {
        fileId: "file456",
        fileUniqueId: "unique456",
        description: "A cute fox waving",
        cachedAt: "2026-01-26T12:00:00.000Z",
      };

      cacheSticker(sticker);

      const all = getAllCachedStickers();
      (expect* all).has-length(1);
      (expect* all[0]).is-equal(sticker);
    });

    (deftest "updates existing entry", () => {
      const original = {
        fileId: "file789",
        fileUniqueId: "unique789",
        description: "Original description",
        cachedAt: "2026-01-26T12:00:00.000Z",
      };
      const updated = {
        fileId: "file789-new",
        fileUniqueId: "unique789",
        description: "Updated description",
        cachedAt: "2026-01-26T13:00:00.000Z",
      };

      cacheSticker(original);
      cacheSticker(updated);

      const result = getCachedSticker("unique789");
      (expect* result?.description).is("Updated description");
      (expect* result?.fileId).is("file789-new");
    });
  });

  (deftest-group "searchStickers", () => {
    beforeEach(() => {
      // Seed cache with test stickers
      cacheSticker({
        fileId: "fox1",
        fileUniqueId: "fox-unique-1",
        emoji: "🦊",
        setName: "CuteFoxes",
        description: "A cute orange fox waving hello",
        cachedAt: "2026-01-26T10:00:00.000Z",
      });
      cacheSticker({
        fileId: "fox2",
        fileUniqueId: "fox-unique-2",
        emoji: "🦊",
        setName: "CuteFoxes",
        description: "A fox sleeping peacefully",
        cachedAt: "2026-01-26T11:00:00.000Z",
      });
      cacheSticker({
        fileId: "cat1",
        fileUniqueId: "cat-unique-1",
        emoji: "🐱",
        setName: "FunnyCats",
        description: "A cat sitting on a keyboard",
        cachedAt: "2026-01-26T12:00:00.000Z",
      });
      cacheSticker({
        fileId: "dog1",
        fileUniqueId: "dog-unique-1",
        emoji: "🐶",
        setName: "GoodBoys",
        description: "A golden retriever playing fetch",
        cachedAt: "2026-01-26T13:00:00.000Z",
      });
    });

    (deftest "finds stickers by description substring", () => {
      const results = searchStickers("fox");
      (expect* results).has-length(2);
      (expect* results.every((s) => s.description.toLowerCase().includes("fox"))).is(true);
    });

    (deftest "finds stickers by emoji", () => {
      const results = searchStickers("🦊");
      (expect* results).has-length(2);
      (expect* results.every((s) => s.emoji === "🦊")).is(true);
    });

    (deftest "finds stickers by set name", () => {
      const results = searchStickers("CuteFoxes");
      (expect* results).has-length(2);
      (expect* results.every((s) => s.setName === "CuteFoxes")).is(true);
    });

    (deftest "respects limit parameter", () => {
      const results = searchStickers("fox", 1);
      (expect* results).has-length(1);
    });

    (deftest "ranks exact matches higher", () => {
      // "waving" appears in "fox waving hello" - should be ranked first
      const results = searchStickers("waving");
      (expect* results).has-length(1);
      (expect* results[0]?.fileUniqueId).is("fox-unique-1");
    });

    (deftest "returns empty array for no matches", () => {
      const results = searchStickers("elephant");
      (expect* results).has-length(0);
    });

    (deftest "is case insensitive", () => {
      const results = searchStickers("FOX");
      (expect* results).has-length(2);
    });

    (deftest "matches multiple words", () => {
      const results = searchStickers("cat keyboard");
      (expect* results).has-length(1);
      (expect* results[0]?.fileUniqueId).is("cat-unique-1");
    });
  });

  (deftest-group "getAllCachedStickers", () => {
    (deftest "returns empty array when cache is empty", () => {
      const result = getAllCachedStickers();
      (expect* result).is-equal([]);
    });

    (deftest "returns all cached stickers", () => {
      cacheSticker({
        fileId: "a",
        fileUniqueId: "a-unique",
        description: "Sticker A",
        cachedAt: "2026-01-26T10:00:00.000Z",
      });
      cacheSticker({
        fileId: "b",
        fileUniqueId: "b-unique",
        description: "Sticker B",
        cachedAt: "2026-01-26T11:00:00.000Z",
      });

      const result = getAllCachedStickers();
      (expect* result).has-length(2);
    });
  });

  (deftest-group "getCacheStats", () => {
    (deftest "returns count 0 when cache is empty", () => {
      const stats = getCacheStats();
      (expect* stats.count).is(0);
      (expect* stats.oldestAt).toBeUndefined();
      (expect* stats.newestAt).toBeUndefined();
    });

    (deftest "returns correct stats with cached stickers", () => {
      cacheSticker({
        fileId: "old",
        fileUniqueId: "old-unique",
        description: "Old sticker",
        cachedAt: "2026-01-20T10:00:00.000Z",
      });
      cacheSticker({
        fileId: "new",
        fileUniqueId: "new-unique",
        description: "New sticker",
        cachedAt: "2026-01-26T10:00:00.000Z",
      });
      cacheSticker({
        fileId: "mid",
        fileUniqueId: "mid-unique",
        description: "Middle sticker",
        cachedAt: "2026-01-23T10:00:00.000Z",
      });

      const stats = getCacheStats();
      (expect* stats.count).is(3);
      (expect* stats.oldestAt).is("2026-01-20T10:00:00.000Z");
      (expect* stats.newestAt).is("2026-01-26T10:00:00.000Z");
    });
  });
});
