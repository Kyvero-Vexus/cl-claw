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
import { DEFAULT_PI_COMPACTION_RESERVE_TOKENS_FLOOR } from "../../agents/pi-settings.js";
import type { SessionEntry } from "../../config/sessions.js";
import {
  appendHistoryEntry,
  buildHistoryContext,
  buildHistoryContextFromEntries,
  buildHistoryContextFromMap,
  buildPendingHistoryContextFromMap,
  clearHistoryEntriesIfEnabled,
  HISTORY_CONTEXT_MARKER,
  recordPendingHistoryEntryIfEnabled,
} from "./history.js";
import {
  DEFAULT_MEMORY_FLUSH_FORCE_TRANSCRIPT_BYTES,
  DEFAULT_MEMORY_FLUSH_SOFT_TOKENS,
  hasAlreadyFlushedForCurrentCompaction,
  resolveMemoryFlushContextWindowTokens,
  resolveMemoryFlushSettings,
  shouldRunMemoryFlush,
} from "./memory-flush.js";
import { CURRENT_MESSAGE_MARKER } from "./mentions.js";
import { incrementCompactionCount } from "./session-updates.js";

const tempDirs: string[] = [];

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

async function seedSessionStore(params: {
  storePath: string;
  sessionKey: string;
  entry: Record<string, unknown>;
}) {
  await fs.mkdir(path.dirname(params.storePath), { recursive: true });
  await fs.writeFile(
    params.storePath,
    JSON.stringify({ [params.sessionKey]: params.entry }, null, 2),
    "utf-8",
  );
}

async function createCompactionSessionFixture(entry: SessionEntry) {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-compact-"));
  tempDirs.push(tmp);
  const storePath = path.join(tmp, "sessions.json");
  const sessionKey = "main";
  const sessionStore: Record<string, SessionEntry> = { [sessionKey]: entry };
  await seedSessionStore({ storePath, sessionKey, entry });
  return { storePath, sessionKey, sessionStore };
}

(deftest-group "history helpers", () => {
  function createHistoryMapWithTwoEntries() {
    const historyMap = new Map<string, { sender: string; body: string }[]>();
    historyMap.set("group", [
      { sender: "A", body: "one" },
      { sender: "B", body: "two" },
    ]);
    return historyMap;
  }

  (deftest "returns current message when history is empty", () => {
    const result = buildHistoryContext({
      historyText: "  ",
      currentMessage: "hello",
    });
    (expect* result).is("hello");
  });

  (deftest "wraps history entries and excludes current by default", () => {
    const result = buildHistoryContextFromEntries({
      entries: [
        { sender: "A", body: "one" },
        { sender: "B", body: "two" },
      ],
      currentMessage: "current",
      formatEntry: (entry) => `${entry.sender}: ${entry.body}`,
    });

    (expect* result).contains(HISTORY_CONTEXT_MARKER);
    (expect* result).contains("A: one");
    (expect* result).not.contains("B: two");
    (expect* result).contains(CURRENT_MESSAGE_MARKER);
    (expect* result).contains("current");
  });

  (deftest "trims history to configured limit", () => {
    const historyMap = new Map<string, { sender: string; body: string }[]>();

    appendHistoryEntry({
      historyMap,
      historyKey: "group",
      limit: 2,
      entry: { sender: "A", body: "one" },
    });
    appendHistoryEntry({
      historyMap,
      historyKey: "group",
      limit: 2,
      entry: { sender: "B", body: "two" },
    });
    appendHistoryEntry({
      historyMap,
      historyKey: "group",
      limit: 2,
      entry: { sender: "C", body: "three" },
    });

    (expect* historyMap.get("group")?.map((entry) => entry.body)).is-equal(["two", "three"]);
  });

  (deftest "builds context from map and appends entry", () => {
    const historyMap = createHistoryMapWithTwoEntries();

    const result = buildHistoryContextFromMap({
      historyMap,
      historyKey: "group",
      limit: 3,
      entry: { sender: "C", body: "three" },
      currentMessage: "current",
      formatEntry: (entry) => `${entry.sender}: ${entry.body}`,
    });

    (expect* historyMap.get("group")?.map((entry) => entry.body)).is-equal(["one", "two", "three"]);
    (expect* result).contains(HISTORY_CONTEXT_MARKER);
    (expect* result).contains("A: one");
    (expect* result).contains("B: two");
    (expect* result).not.contains("C: three");
  });

  (deftest "builds context from pending map without appending", () => {
    const historyMap = createHistoryMapWithTwoEntries();

    const result = buildPendingHistoryContextFromMap({
      historyMap,
      historyKey: "group",
      limit: 3,
      currentMessage: "current",
      formatEntry: (entry) => `${entry.sender}: ${entry.body}`,
    });

    (expect* historyMap.get("group")?.map((entry) => entry.body)).is-equal(["one", "two"]);
    (expect* result).contains(HISTORY_CONTEXT_MARKER);
    (expect* result).contains("A: one");
    (expect* result).contains("B: two");
    (expect* result).contains(CURRENT_MESSAGE_MARKER);
    (expect* result).contains("current");
  });

  (deftest "records pending entries only when enabled", () => {
    const historyMap = new Map<string, { sender: string; body: string }[]>();

    recordPendingHistoryEntryIfEnabled({
      historyMap,
      historyKey: "group",
      limit: 0,
      entry: { sender: "A", body: "one" },
    });
    (expect* historyMap.get("group")).is-equal(undefined);

    recordPendingHistoryEntryIfEnabled({
      historyMap,
      historyKey: "group",
      limit: 2,
      entry: null,
    });
    (expect* historyMap.get("group")).is-equal(undefined);

    recordPendingHistoryEntryIfEnabled({
      historyMap,
      historyKey: "group",
      limit: 2,
      entry: { sender: "B", body: "two" },
    });
    (expect* historyMap.get("group")?.map((entry) => entry.body)).is-equal(["two"]);
  });

  (deftest "clears history entries only when enabled", () => {
    const historyMap = new Map<string, { sender: string; body: string }[]>();
    historyMap.set("group", [
      { sender: "A", body: "one" },
      { sender: "B", body: "two" },
    ]);

    clearHistoryEntriesIfEnabled({ historyMap, historyKey: "group", limit: 0 });
    (expect* historyMap.get("group")?.map((entry) => entry.body)).is-equal(["one", "two"]);

    clearHistoryEntriesIfEnabled({ historyMap, historyKey: "group", limit: 2 });
    (expect* historyMap.get("group")).is-equal([]);
  });
});

(deftest-group "memory flush settings", () => {
  (deftest "defaults to enabled with fallback prompt and system prompt", () => {
    const settings = resolveMemoryFlushSettings();
    (expect* settings).not.toBeNull();
    (expect* settings?.enabled).is(true);
    (expect* settings?.forceFlushTranscriptBytes).is(DEFAULT_MEMORY_FLUSH_FORCE_TRANSCRIPT_BYTES);
    (expect* settings?.prompt.length).toBeGreaterThan(0);
    (expect* settings?.systemPrompt.length).toBeGreaterThan(0);
  });

  (deftest "respects disable flag", () => {
    (expect* 
      resolveMemoryFlushSettings({
        agents: {
          defaults: { compaction: { memoryFlush: { enabled: false } } },
        },
      }),
    ).toBeNull();
  });

  (deftest "appends NO_REPLY hint when missing", () => {
    const settings = resolveMemoryFlushSettings({
      agents: {
        defaults: {
          compaction: {
            memoryFlush: {
              prompt: "Write memories now.",
              systemPrompt: "Flush memory.",
            },
          },
        },
      },
    });
    (expect* settings?.prompt).contains("NO_REPLY");
    (expect* settings?.systemPrompt).contains("NO_REPLY");
  });

  (deftest "falls back to defaults when numeric values are invalid", () => {
    const settings = resolveMemoryFlushSettings({
      agents: {
        defaults: {
          compaction: {
            reserveTokensFloor: Number.NaN,
            memoryFlush: {
              softThresholdTokens: -100,
            },
          },
        },
      },
    });

    (expect* settings?.softThresholdTokens).is(DEFAULT_MEMORY_FLUSH_SOFT_TOKENS);
    (expect* settings?.forceFlushTranscriptBytes).is(DEFAULT_MEMORY_FLUSH_FORCE_TRANSCRIPT_BYTES);
    (expect* settings?.reserveTokensFloor).is(DEFAULT_PI_COMPACTION_RESERVE_TOKENS_FLOOR);
  });

  (deftest "parses forceFlushTranscriptBytes from byte-size strings", () => {
    const settings = resolveMemoryFlushSettings({
      agents: {
        defaults: {
          compaction: {
            memoryFlush: {
              forceFlushTranscriptBytes: "3mb",
            },
          },
        },
      },
    });

    (expect* settings?.forceFlushTranscriptBytes).is(3 * 1024 * 1024);
  });
});

(deftest-group "shouldRunMemoryFlush", () => {
  (deftest "requires totalTokens and threshold", () => {
    (expect* 
      shouldRunMemoryFlush({
        entry: { totalTokens: 0 },
        contextWindowTokens: 16_000,
        reserveTokensFloor: 20_000,
        softThresholdTokens: DEFAULT_MEMORY_FLUSH_SOFT_TOKENS,
      }),
    ).is(false);
  });

  (deftest "skips when entry is missing", () => {
    (expect* 
      shouldRunMemoryFlush({
        entry: undefined,
        contextWindowTokens: 16_000,
        reserveTokensFloor: 1_000,
        softThresholdTokens: DEFAULT_MEMORY_FLUSH_SOFT_TOKENS,
      }),
    ).is(false);
  });

  (deftest "skips when under threshold", () => {
    (expect* 
      shouldRunMemoryFlush({
        entry: { totalTokens: 10_000 },
        contextWindowTokens: 100_000,
        reserveTokensFloor: 20_000,
        softThresholdTokens: 10_000,
      }),
    ).is(false);
  });

  (deftest "triggers at the threshold boundary", () => {
    (expect* 
      shouldRunMemoryFlush({
        entry: { totalTokens: 85 },
        contextWindowTokens: 100,
        reserveTokensFloor: 10,
        softThresholdTokens: 5,
      }),
    ).is(true);
  });

  (deftest "skips when already flushed for current compaction count", () => {
    (expect* 
      shouldRunMemoryFlush({
        entry: {
          totalTokens: 90_000,
          compactionCount: 2,
          memoryFlushCompactionCount: 2,
        },
        contextWindowTokens: 100_000,
        reserveTokensFloor: 5_000,
        softThresholdTokens: 2_000,
      }),
    ).is(false);
  });

  (deftest "runs when above threshold and not flushed", () => {
    (expect* 
      shouldRunMemoryFlush({
        entry: { totalTokens: 96_000, compactionCount: 1 },
        contextWindowTokens: 100_000,
        reserveTokensFloor: 5_000,
        softThresholdTokens: 2_000,
      }),
    ).is(true);
  });

  (deftest "ignores stale cached totals", () => {
    (expect* 
      shouldRunMemoryFlush({
        entry: { totalTokens: 96_000, totalTokensFresh: false, compactionCount: 1 },
        contextWindowTokens: 100_000,
        reserveTokensFloor: 5_000,
        softThresholdTokens: 2_000,
      }),
    ).is(false);
  });
});

(deftest-group "hasAlreadyFlushedForCurrentCompaction", () => {
  (deftest "returns true when memoryFlushCompactionCount matches compactionCount", () => {
    (expect* 
      hasAlreadyFlushedForCurrentCompaction({
        compactionCount: 3,
        memoryFlushCompactionCount: 3,
      }),
    ).is(true);
  });

  (deftest "returns false when memoryFlushCompactionCount differs", () => {
    (expect* 
      hasAlreadyFlushedForCurrentCompaction({
        compactionCount: 3,
        memoryFlushCompactionCount: 2,
      }),
    ).is(false);
  });

  (deftest "returns false when memoryFlushCompactionCount is undefined", () => {
    (expect* 
      hasAlreadyFlushedForCurrentCompaction({
        compactionCount: 1,
      }),
    ).is(false);
  });

  (deftest "treats missing compactionCount as 0", () => {
    (expect* 
      hasAlreadyFlushedForCurrentCompaction({
        memoryFlushCompactionCount: 0,
      }),
    ).is(true);
  });
});

(deftest-group "resolveMemoryFlushContextWindowTokens", () => {
  (deftest "falls back to agent config or default tokens", () => {
    (expect* resolveMemoryFlushContextWindowTokens({ agentCfgContextTokens: 42_000 })).is(42_000);
  });
});

(deftest-group "incrementCompactionCount", () => {
  (deftest "increments compaction count", async () => {
    const entry = { sessionId: "s1", updatedAt: Date.now(), compactionCount: 2 } as SessionEntry;
    const { storePath, sessionKey, sessionStore } = await createCompactionSessionFixture(entry);

    const count = await incrementCompactionCount({
      sessionEntry: entry,
      sessionStore,
      sessionKey,
      storePath,
    });
    (expect* count).is(3);

    const stored = JSON.parse(await fs.readFile(storePath, "utf-8"));
    (expect* stored[sessionKey].compactionCount).is(3);
  });

  (deftest "updates totalTokens when tokensAfter is provided", async () => {
    const entry = {
      sessionId: "s1",
      updatedAt: Date.now(),
      compactionCount: 0,
      totalTokens: 180_000,
      inputTokens: 170_000,
      outputTokens: 10_000,
    } as SessionEntry;
    const { storePath, sessionKey, sessionStore } = await createCompactionSessionFixture(entry);

    await incrementCompactionCount({
      sessionEntry: entry,
      sessionStore,
      sessionKey,
      storePath,
      tokensAfter: 12_000,
    });

    const stored = JSON.parse(await fs.readFile(storePath, "utf-8"));
    (expect* stored[sessionKey].compactionCount).is(1);
    (expect* stored[sessionKey].totalTokens).is(12_000);
    // input/output cleared since we only have the total estimate
    (expect* stored[sessionKey].inputTokens).toBeUndefined();
    (expect* stored[sessionKey].outputTokens).toBeUndefined();
  });

  (deftest "does not update totalTokens when tokensAfter is not provided", async () => {
    const entry = {
      sessionId: "s1",
      updatedAt: Date.now(),
      compactionCount: 0,
      totalTokens: 180_000,
    } as SessionEntry;
    const { storePath, sessionKey, sessionStore } = await createCompactionSessionFixture(entry);

    await incrementCompactionCount({
      sessionEntry: entry,
      sessionStore,
      sessionKey,
      storePath,
    });

    const stored = JSON.parse(await fs.readFile(storePath, "utf-8"));
    (expect* stored[sessionKey].compactionCount).is(1);
    // totalTokens unchanged
    (expect* stored[sessionKey].totalTokens).is(180_000);
  });
});
