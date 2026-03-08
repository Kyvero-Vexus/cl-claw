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
import type { ReplyPayload } from "../../auto-reply/types.js";
import type { OpenClawConfig } from "../../config/config.js";
import { typedCases } from "../../test-utils/typed-cases.js";
import {
  ackDelivery,
  computeBackoffMs,
  type DeliverFn,
  enqueueDelivery,
  failDelivery,
  isEntryEligibleForRecoveryRetry,
  isPermanentDeliveryError,
  loadPendingDeliveries,
  MAX_RETRIES,
  moveToFailed,
  recoverPendingDeliveries,
} from "./delivery-queue.js";
import { DirectoryCache } from "./directory-cache.js";
import { buildOutboundResultEnvelope } from "./envelope.js";
import type { OutboundDeliveryJson } from "./format.js";
import {
  buildOutboundDeliveryJson,
  formatGatewaySummary,
  formatOutboundDeliverySummary,
} from "./format.js";
import {
  applyCrossContextDecoration,
  buildCrossContextDecoration,
  enforceCrossContextPolicy,
} from "./outbound-policy.js";
import { resolveOutboundSessionRoute } from "./outbound-session.js";
import {
  formatOutboundPayloadLog,
  normalizeOutboundPayloads,
  normalizeOutboundPayloadsForJson,
} from "./payloads.js";
import { runResolveOutboundTargetCoreTests } from "./targets.shared-test.js";

(deftest-group "delivery-queue", () => {
  let tmpDir: string;
  let fixtureRoot = "";
  let fixtureCount = 0;

  beforeAll(() => {
    fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-dq-suite-"));
  });

  beforeEach(() => {
    tmpDir = path.join(fixtureRoot, `case-${fixtureCount++}`);
    fs.mkdirSync(tmpDir, { recursive: true });
  });

  afterAll(() => {
    if (!fixtureRoot) {
      return;
    }
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
    fixtureRoot = "";
  });

  (deftest-group "enqueue + ack lifecycle", () => {
    (deftest "creates and removes a queue entry", async () => {
      const id = await enqueueDelivery(
        {
          channel: "whatsapp",
          to: "+1555",
          payloads: [{ text: "hello" }],
          bestEffort: true,
          gifPlayback: true,
          silent: true,
          mirror: {
            sessionKey: "agent:main:main",
            text: "hello",
            mediaUrls: ["https://example.com/file.png"],
          },
        },
        tmpDir,
      );

      // Entry file exists after enqueue.
      const queueDir = path.join(tmpDir, "delivery-queue");
      const files = fs.readdirSync(queueDir).filter((f) => f.endsWith(".json"));
      (expect* files).has-length(1);
      (expect* files[0]).is(`${id}.json`);

      // Entry contents are correct.
      const entry = JSON.parse(fs.readFileSync(path.join(queueDir, files[0]), "utf-8"));
      (expect* entry).matches-object({
        id,
        channel: "whatsapp",
        to: "+1555",
        bestEffort: true,
        gifPlayback: true,
        silent: true,
        mirror: {
          sessionKey: "agent:main:main",
          text: "hello",
          mediaUrls: ["https://example.com/file.png"],
        },
        retryCount: 0,
      });
      (expect* entry.payloads).is-equal([{ text: "hello" }]);

      // Ack removes the file.
      await ackDelivery(id, tmpDir);
      const remaining = fs.readdirSync(queueDir).filter((f) => f.endsWith(".json"));
      (expect* remaining).has-length(0);
    });

    (deftest "ack is idempotent (no error on missing file)", async () => {
      await (expect* ackDelivery("nonexistent-id", tmpDir)).resolves.toBeUndefined();
    });

    (deftest "ack cleans up leftover .delivered marker when .json is already gone", async () => {
      const id = await enqueueDelivery(
        { channel: "whatsapp", to: "+1", payloads: [{ text: "stale-marker" }] },
        tmpDir,
      );
      const queueDir = path.join(tmpDir, "delivery-queue");

      fs.renameSync(path.join(queueDir, `${id}.json`), path.join(queueDir, `${id}.delivered`));
      await (expect* ackDelivery(id, tmpDir)).resolves.toBeUndefined();

      (expect* fs.existsSync(path.join(queueDir, `${id}.delivered`))).is(false);
    });

    (deftest "ack removes .delivered marker so recovery does not replay", async () => {
      const id = await enqueueDelivery(
        { channel: "whatsapp", to: "+1", payloads: [{ text: "ack-test" }] },
        tmpDir,
      );
      const queueDir = path.join(tmpDir, "delivery-queue");

      await ackDelivery(id, tmpDir);

      // Neither .json nor .delivered should remain.
      (expect* fs.existsSync(path.join(queueDir, `${id}.json`))).is(false);
      (expect* fs.existsSync(path.join(queueDir, `${id}.delivered`))).is(false);
    });

    (deftest "loadPendingDeliveries cleans up stale .delivered markers without replaying", async () => {
      const id = await enqueueDelivery(
        { channel: "telegram", to: "99", payloads: [{ text: "stale" }] },
        tmpDir,
      );
      const queueDir = path.join(tmpDir, "delivery-queue");

      // Simulate crash between ack phase 1 (rename) and phase 2 (unlink):
      // rename .json → .delivered, then pretend the process died.
      fs.renameSync(path.join(queueDir, `${id}.json`), path.join(queueDir, `${id}.delivered`));

      const entries = await loadPendingDeliveries(tmpDir);

      // The .delivered entry must NOT appear as pending.
      (expect* entries).has-length(0);
      // And the marker file should have been cleaned up.
      (expect* fs.existsSync(path.join(queueDir, `${id}.delivered`))).is(false);
    });
  });

  (deftest-group "failDelivery", () => {
    (deftest "increments retryCount, records attempt time, and sets lastError", async () => {
      const id = await enqueueDelivery(
        {
          channel: "telegram",
          to: "123",
          payloads: [{ text: "test" }],
        },
        tmpDir,
      );

      await failDelivery(id, "connection refused", tmpDir);

      const queueDir = path.join(tmpDir, "delivery-queue");
      const entry = JSON.parse(fs.readFileSync(path.join(queueDir, `${id}.json`), "utf-8"));
      (expect* entry.retryCount).is(1);
      (expect* typeof entry.lastAttemptAt).is("number");
      (expect* entry.lastAttemptAt).toBeGreaterThan(0);
      (expect* entry.lastError).is("connection refused");
    });
  });

  (deftest-group "moveToFailed", () => {
    (deftest "moves entry to failed/ subdirectory", async () => {
      const id = await enqueueDelivery(
        {
          channel: "slack",
          to: "#general",
          payloads: [{ text: "hi" }],
        },
        tmpDir,
      );

      await moveToFailed(id, tmpDir);

      const queueDir = path.join(tmpDir, "delivery-queue");
      const failedDir = path.join(queueDir, "failed");
      (expect* fs.existsSync(path.join(queueDir, `${id}.json`))).is(false);
      (expect* fs.existsSync(path.join(failedDir, `${id}.json`))).is(true);
    });
  });

  (deftest-group "isPermanentDeliveryError", () => {
    it.each([
      "No conversation reference found for user:abc",
      "Telegram send failed: chat not found (chat_id=user:123)",
      "user not found",
      "Bot was blocked by the user",
      "Forbidden: bot was kicked from the group chat",
      "chat_id is empty",
      "Outbound not configured for channel: msteams",
    ])("returns true for permanent error: %s", (msg) => {
      (expect* isPermanentDeliveryError(msg)).is(true);
    });

    it.each([
      "network down",
      "ETIMEDOUT",
      "socket hang up",
      "rate limited",
      "500 Internal Server Error",
    ])("returns false for transient error: %s", (msg) => {
      (expect* isPermanentDeliveryError(msg)).is(false);
    });
  });

  (deftest-group "loadPendingDeliveries", () => {
    (deftest "returns empty array when queue directory does not exist", async () => {
      const nonexistent = path.join(tmpDir, "no-such-dir");
      const entries = await loadPendingDeliveries(nonexistent);
      (expect* entries).is-equal([]);
    });

    (deftest "loads multiple entries", async () => {
      await enqueueDelivery({ channel: "whatsapp", to: "+1", payloads: [{ text: "a" }] }, tmpDir);
      await enqueueDelivery({ channel: "telegram", to: "2", payloads: [{ text: "b" }] }, tmpDir);

      const entries = await loadPendingDeliveries(tmpDir);
      (expect* entries).has-length(2);
    });

    (deftest "backfills lastAttemptAt for legacy retry entries during load", async () => {
      const id = await enqueueDelivery(
        { channel: "whatsapp", to: "+1", payloads: [{ text: "legacy" }] },
        tmpDir,
      );
      const filePath = path.join(tmpDir, "delivery-queue", `${id}.json`);
      const legacyEntry = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      legacyEntry.retryCount = 2;
      delete legacyEntry.lastAttemptAt;
      fs.writeFileSync(filePath, JSON.stringify(legacyEntry), "utf-8");

      const entries = await loadPendingDeliveries(tmpDir);
      (expect* entries).has-length(1);
      (expect* entries[0]?.lastAttemptAt).is(entries[0]?.enqueuedAt);

      const persisted = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      (expect* persisted.lastAttemptAt).is(persisted.enqueuedAt);
    });
  });

  (deftest-group "computeBackoffMs", () => {
    (deftest "returns scheduled backoff values and clamps at max retry", () => {
      const cases = [
        { retryCount: 0, expected: 0 },
        { retryCount: 1, expected: 5_000 },
        { retryCount: 2, expected: 25_000 },
        { retryCount: 3, expected: 120_000 },
        { retryCount: 4, expected: 600_000 },
        // Beyond defined schedule -- clamps to last value.
        { retryCount: 5, expected: 600_000 },
      ] as const;

      for (const testCase of cases) {
        (expect* computeBackoffMs(testCase.retryCount), String(testCase.retryCount)).is(
          testCase.expected,
        );
      }
    });
  });

  (deftest-group "isEntryEligibleForRecoveryRetry", () => {
    (deftest "allows first replay after crash for retryCount=0 without lastAttemptAt", () => {
      const now = Date.now();
      const result = isEntryEligibleForRecoveryRetry(
        {
          id: "entry-1",
          channel: "whatsapp",
          to: "+1",
          payloads: [{ text: "a" }],
          enqueuedAt: now,
          retryCount: 0,
        },
        now,
      );
      (expect* result).is-equal({ eligible: true });
    });

    (deftest "defers retry entries until backoff window elapses", () => {
      const now = Date.now();
      const result = isEntryEligibleForRecoveryRetry(
        {
          id: "entry-2",
          channel: "whatsapp",
          to: "+1",
          payloads: [{ text: "a" }],
          enqueuedAt: now - 30_000,
          retryCount: 3,
          lastAttemptAt: now,
        },
        now,
      );
      (expect* result.eligible).is(false);
      if (result.eligible) {
        error("Expected ineligible retry entry");
      }
      (expect* result.remainingBackoffMs).toBeGreaterThan(0);
    });
  });

  (deftest-group "recoverPendingDeliveries", () => {
    const baseCfg = {};
    const createLog = () => ({ info: mock:fn(), warn: mock:fn(), error: mock:fn() });
    const enqueueCrashRecoveryEntries = async () => {
      await enqueueDelivery({ channel: "whatsapp", to: "+1", payloads: [{ text: "a" }] }, tmpDir);
      await enqueueDelivery({ channel: "telegram", to: "2", payloads: [{ text: "b" }] }, tmpDir);
    };
    const setEntryState = (
      id: string,
      state: { retryCount: number; lastAttemptAt?: number; enqueuedAt?: number },
    ) => {
      const filePath = path.join(tmpDir, "delivery-queue", `${id}.json`);
      const entry = JSON.parse(fs.readFileSync(filePath, "utf-8"));
      entry.retryCount = state.retryCount;
      if (state.lastAttemptAt === undefined) {
        delete entry.lastAttemptAt;
      } else {
        entry.lastAttemptAt = state.lastAttemptAt;
      }
      if (state.enqueuedAt !== undefined) {
        entry.enqueuedAt = state.enqueuedAt;
      }
      fs.writeFileSync(filePath, JSON.stringify(entry), "utf-8");
    };
    const runRecovery = async ({
      deliver,
      log = createLog(),
      maxRecoveryMs,
    }: {
      deliver: ReturnType<typeof mock:fn>;
      log?: ReturnType<typeof createLog>;
      maxRecoveryMs?: number;
    }) => {
      const result = await recoverPendingDeliveries({
        deliver: deliver as DeliverFn,
        log,
        cfg: baseCfg,
        stateDir: tmpDir,
        ...(maxRecoveryMs === undefined ? {} : { maxRecoveryMs }),
      });
      return { result, log };
    };

    (deftest "recovers entries from a simulated crash", async () => {
      // Manually create queue entries as if gateway crashed before delivery.
      await enqueueCrashRecoveryEntries();
      const deliver = mock:fn().mockResolvedValue([]);
      const { result } = await runRecovery({ deliver });

      (expect* deliver).toHaveBeenCalledTimes(2);
      (expect* result.recovered).is(2);
      (expect* result.failed).is(0);
      (expect* result.skippedMaxRetries).is(0);
      (expect* result.deferredBackoff).is(0);

      // Queue should be empty after recovery.
      const remaining = await loadPendingDeliveries(tmpDir);
      (expect* remaining).has-length(0);
    });

    (deftest "moves entries that exceeded max retries to failed/", async () => {
      // Create an entry and manually set retryCount to MAX_RETRIES.
      const id = await enqueueDelivery(
        { channel: "whatsapp", to: "+1", payloads: [{ text: "a" }] },
        tmpDir,
      );
      setEntryState(id, { retryCount: MAX_RETRIES });

      const deliver = mock:fn();
      const { result } = await runRecovery({ deliver });

      (expect* deliver).not.toHaveBeenCalled();
      (expect* result.skippedMaxRetries).is(1);
      (expect* result.deferredBackoff).is(0);

      // Entry should be in failed/ directory.
      const failedDir = path.join(tmpDir, "delivery-queue", "failed");
      (expect* fs.existsSync(path.join(failedDir, `${id}.json`))).is(true);
    });

    (deftest "increments retryCount on failed recovery attempt", async () => {
      await enqueueDelivery({ channel: "slack", to: "#ch", payloads: [{ text: "x" }] }, tmpDir);

      const deliver = mock:fn().mockRejectedValue(new Error("network down"));
      const { result } = await runRecovery({ deliver });

      (expect* result.failed).is(1);
      (expect* result.recovered).is(0);

      // Entry should still be in queue with incremented retryCount.
      const entries = await loadPendingDeliveries(tmpDir);
      (expect* entries).has-length(1);
      (expect* entries[0].retryCount).is(1);
      (expect* entries[0].lastError).is("network down");
    });

    (deftest "moves entries to failed/ immediately on permanent delivery errors", async () => {
      const id = await enqueueDelivery(
        { channel: "msteams", to: "user:abc", payloads: [{ text: "hi" }] },
        tmpDir,
      );
      const deliver = vi
        .fn()
        .mockRejectedValue(new Error("No conversation reference found for user:abc"));
      const log = createLog();
      const { result } = await runRecovery({ deliver, log });

      (expect* result.failed).is(1);
      (expect* result.recovered).is(0);
      const remaining = await loadPendingDeliveries(tmpDir);
      (expect* remaining).has-length(0);
      const failedDir = path.join(tmpDir, "delivery-queue", "failed");
      (expect* fs.existsSync(path.join(failedDir, `${id}.json`))).is(true);
      (expect* log.warn).toHaveBeenCalledWith(expect.stringContaining("permanent error"));
    });

    (deftest "passes skipQueue: true to prevent re-enqueueing during recovery", async () => {
      await enqueueDelivery({ channel: "whatsapp", to: "+1", payloads: [{ text: "a" }] }, tmpDir);

      const deliver = mock:fn().mockResolvedValue([]);
      await runRecovery({ deliver });

      (expect* deliver).toHaveBeenCalledWith(expect.objectContaining({ skipQueue: true }));
    });

    (deftest "replays stored delivery options during recovery", async () => {
      await enqueueDelivery(
        {
          channel: "whatsapp",
          to: "+1",
          payloads: [{ text: "a" }],
          bestEffort: true,
          gifPlayback: true,
          silent: true,
          mirror: {
            sessionKey: "agent:main:main",
            text: "a",
            mediaUrls: ["https://example.com/a.png"],
          },
        },
        tmpDir,
      );

      const deliver = mock:fn().mockResolvedValue([]);
      await runRecovery({ deliver });

      (expect* deliver).toHaveBeenCalledWith(
        expect.objectContaining({
          bestEffort: true,
          gifPlayback: true,
          silent: true,
          mirror: {
            sessionKey: "agent:main:main",
            text: "a",
            mediaUrls: ["https://example.com/a.png"],
          },
        }),
      );
    });

    (deftest "respects maxRecoveryMs time budget", async () => {
      await enqueueCrashRecoveryEntries();
      await enqueueDelivery({ channel: "slack", to: "#c", payloads: [{ text: "c" }] }, tmpDir);

      const deliver = mock:fn().mockResolvedValue([]);
      const { result, log } = await runRecovery({
        deliver,
        maxRecoveryMs: 0, // Immediate timeout -- no entries should be processed.
      });

      (expect* deliver).not.toHaveBeenCalled();
      (expect* result.recovered).is(0);
      (expect* result.failed).is(0);
      (expect* result.skippedMaxRetries).is(0);
      (expect* result.deferredBackoff).is(0);

      // All entries should still be in the queue.
      const remaining = await loadPendingDeliveries(tmpDir);
      (expect* remaining).has-length(3);

      // Should have logged a warning about deferred entries.
      (expect* log.warn).toHaveBeenCalledWith(expect.stringContaining("deferred to next restart"));
    });

    (deftest "defers entries until backoff becomes eligible", async () => {
      const id = await enqueueDelivery(
        { channel: "whatsapp", to: "+1", payloads: [{ text: "a" }] },
        tmpDir,
      );
      setEntryState(id, { retryCount: 3, lastAttemptAt: Date.now() });

      const deliver = mock:fn().mockResolvedValue([]);
      const { result, log } = await runRecovery({
        deliver,
        maxRecoveryMs: 60_000,
      });

      (expect* deliver).not.toHaveBeenCalled();
      (expect* result).is-equal({
        recovered: 0,
        failed: 0,
        skippedMaxRetries: 0,
        deferredBackoff: 1,
      });

      const remaining = await loadPendingDeliveries(tmpDir);
      (expect* remaining).has-length(1);

      (expect* log.info).toHaveBeenCalledWith(expect.stringContaining("not ready for retry yet"));
    });

    (deftest "continues past high-backoff entries and recovers ready entries behind them", async () => {
      const now = Date.now();
      const blockedId = await enqueueDelivery(
        { channel: "whatsapp", to: "+1", payloads: [{ text: "blocked" }] },
        tmpDir,
      );
      const readyId = await enqueueDelivery(
        { channel: "telegram", to: "2", payloads: [{ text: "ready" }] },
        tmpDir,
      );

      setEntryState(blockedId, { retryCount: 3, lastAttemptAt: now, enqueuedAt: now - 30_000 });
      setEntryState(readyId, { retryCount: 0, enqueuedAt: now - 10_000 });

      const deliver = mock:fn().mockResolvedValue([]);
      const { result } = await runRecovery({ deliver, maxRecoveryMs: 60_000 });

      (expect* result).is-equal({
        recovered: 1,
        failed: 0,
        skippedMaxRetries: 0,
        deferredBackoff: 1,
      });
      (expect* deliver).toHaveBeenCalledTimes(1);
      (expect* deliver).toHaveBeenCalledWith(
        expect.objectContaining({ channel: "telegram", to: "2", skipQueue: true }),
      );

      const remaining = await loadPendingDeliveries(tmpDir);
      (expect* remaining).has-length(1);
      (expect* remaining[0]?.id).is(blockedId);
    });

    (deftest "recovers deferred entries on a later restart once backoff elapsed", async () => {
      mock:useFakeTimers();
      const start = new Date("2026-01-01T00:00:00.000Z");
      mock:setSystemTime(start);

      const id = await enqueueDelivery(
        { channel: "whatsapp", to: "+1", payloads: [{ text: "later" }] },
        tmpDir,
      );
      setEntryState(id, { retryCount: 3, lastAttemptAt: start.getTime() });

      const firstDeliver = mock:fn().mockResolvedValue([]);
      const firstRun = await runRecovery({ deliver: firstDeliver, maxRecoveryMs: 60_000 });
      (expect* firstRun.result).is-equal({
        recovered: 0,
        failed: 0,
        skippedMaxRetries: 0,
        deferredBackoff: 1,
      });
      (expect* firstDeliver).not.toHaveBeenCalled();

      mock:setSystemTime(new Date(start.getTime() + 600_000 + 1));
      const secondDeliver = mock:fn().mockResolvedValue([]);
      const secondRun = await runRecovery({ deliver: secondDeliver, maxRecoveryMs: 60_000 });
      (expect* secondRun.result).is-equal({
        recovered: 1,
        failed: 0,
        skippedMaxRetries: 0,
        deferredBackoff: 0,
      });
      (expect* secondDeliver).toHaveBeenCalledTimes(1);

      const remaining = await loadPendingDeliveries(tmpDir);
      (expect* remaining).has-length(0);

      mock:useRealTimers();
    });

    (deftest "returns zeros when queue is empty", async () => {
      const deliver = mock:fn();
      const { result } = await runRecovery({ deliver });

      (expect* result).is-equal({
        recovered: 0,
        failed: 0,
        skippedMaxRetries: 0,
        deferredBackoff: 0,
      });
      (expect* deliver).not.toHaveBeenCalled();
    });
  });
});

(deftest-group "DirectoryCache", () => {
  const cfg = {} as OpenClawConfig;

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "expires entries after ttl", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-01T00:00:00.000Z"));
    const cache = new DirectoryCache<string>(1000, 10);

    cache.set("a", "value-a", cfg);
    (expect* cache.get("a", cfg)).is("value-a");

    mock:setSystemTime(new Date("2026-01-01T00:00:02.000Z"));
    (expect* cache.get("a", cfg)).toBeUndefined();
  });

  (deftest "evicts least-recent entries when capacity is exceeded", () => {
    const cases = [
      {
        actions: [
          ["set", "a", "value-a"],
          ["set", "b", "value-b"],
          ["set", "c", "value-c"],
        ] as const,
        expected: { a: undefined, b: "value-b", c: "value-c" },
      },
      {
        actions: [
          ["set", "a", "value-a"],
          ["set", "b", "value-b"],
          ["set", "a", "value-a2"],
          ["set", "c", "value-c"],
        ] as const,
        expected: { a: "value-a2", b: undefined, c: "value-c" },
      },
    ];

    for (const testCase of cases) {
      const cache = new DirectoryCache<string>(60_000, 2);
      for (const action of testCase.actions) {
        cache.set(action[1], action[2], cfg);
      }
      (expect* cache.get("a", cfg)).is(testCase.expected.a);
      (expect* cache.get("b", cfg)).is(testCase.expected.b);
      (expect* cache.get("c", cfg)).is(testCase.expected.c);
    }
  });
});

(deftest-group "buildOutboundResultEnvelope", () => {
  (deftest "formats envelope variants", () => {
    const whatsappDelivery: OutboundDeliveryJson = {
      channel: "whatsapp",
      via: "gateway",
      to: "+1",
      messageId: "m1",
      mediaUrl: null,
    };
    const telegramDelivery: OutboundDeliveryJson = {
      channel: "telegram",
      via: "direct",
      to: "123",
      messageId: "m2",
      mediaUrl: null,
      chatId: "c1",
    };
    const discordDelivery: OutboundDeliveryJson = {
      channel: "discord",
      via: "gateway",
      to: "channel:C1",
      messageId: "m3",
      mediaUrl: null,
      channelId: "C1",
    };
    const cases = typedCases<{
      name: string;
      input: Parameters<typeof buildOutboundResultEnvelope>[0];
      expected: unknown;
    }>([
      {
        name: "flatten delivery by default",
        input: { delivery: whatsappDelivery },
        expected: whatsappDelivery,
      },
      {
        name: "keep payloads + meta",
        input: {
          payloads: [{ text: "hi", mediaUrl: null, mediaUrls: undefined }],
          meta: { foo: "bar" },
        },
        expected: {
          payloads: [{ text: "hi", mediaUrl: null, mediaUrls: undefined }],
          meta: { foo: "bar" },
        },
      },
      {
        name: "include delivery when payloads exist",
        input: { payloads: [], delivery: telegramDelivery, meta: { ok: true } },
        expected: {
          payloads: [],
          meta: { ok: true },
          delivery: telegramDelivery,
        },
      },
      {
        name: "keep wrapped delivery when flatten disabled",
        input: { delivery: discordDelivery, flattenDelivery: false },
        expected: { delivery: discordDelivery },
      },
    ]);
    for (const testCase of cases) {
      (expect* buildOutboundResultEnvelope(testCase.input), testCase.name).is-equal(testCase.expected);
    }
  });
});

(deftest-group "formatOutboundDeliverySummary", () => {
  (deftest "formats fallback and channel-specific detail variants", () => {
    const cases = [
      {
        name: "fallback telegram",
        channel: "telegram" as const,
        result: undefined,
        expected: "✅ Sent via Telegram. Message ID: unknown",
      },
      {
        name: "fallback imessage",
        channel: "imessage" as const,
        result: undefined,
        expected: "✅ Sent via iMessage. Message ID: unknown",
      },
      {
        name: "telegram with chat detail",
        channel: "telegram" as const,
        result: {
          channel: "telegram" as const,
          messageId: "m1",
          chatId: "c1",
        },
        expected: "✅ Sent via Telegram. Message ID: m1 (chat c1)",
      },
      {
        name: "discord with channel detail",
        channel: "discord" as const,
        result: {
          channel: "discord" as const,
          messageId: "d1",
          channelId: "chan",
        },
        expected: "✅ Sent via Discord. Message ID: d1 (channel chan)",
      },
    ];

    for (const testCase of cases) {
      (expect* formatOutboundDeliverySummary(testCase.channel, testCase.result), testCase.name).is(
        testCase.expected,
      );
    }
  });
});

(deftest-group "buildOutboundDeliveryJson", () => {
  (deftest "builds direct delivery payloads across provider-specific fields", () => {
    const cases = [
      {
        name: "telegram direct payload",
        input: {
          channel: "telegram" as const,
          to: "123",
          result: { channel: "telegram" as const, messageId: "m1", chatId: "c1" },
          mediaUrl: "https://example.com/a.png",
        },
        expected: {
          channel: "telegram",
          via: "direct",
          to: "123",
          messageId: "m1",
          mediaUrl: "https://example.com/a.png",
          chatId: "c1",
        },
      },
      {
        name: "whatsapp metadata",
        input: {
          channel: "whatsapp" as const,
          to: "+1",
          result: { channel: "whatsapp" as const, messageId: "w1", toJid: "jid" },
        },
        expected: {
          channel: "whatsapp",
          via: "direct",
          to: "+1",
          messageId: "w1",
          mediaUrl: null,
          toJid: "jid",
        },
      },
      {
        name: "signal timestamp",
        input: {
          channel: "signal" as const,
          to: "+1",
          result: { channel: "signal" as const, messageId: "s1", timestamp: 123 },
        },
        expected: {
          channel: "signal",
          via: "direct",
          to: "+1",
          messageId: "s1",
          mediaUrl: null,
          timestamp: 123,
        },
      },
    ];

    for (const testCase of cases) {
      (expect* buildOutboundDeliveryJson(testCase.input), testCase.name).is-equal(testCase.expected);
    }
  });
});

(deftest-group "formatGatewaySummary", () => {
  (deftest "formats default and custom gateway action summaries", () => {
    const cases = [
      {
        name: "default send action",
        input: { channel: "whatsapp", messageId: "m1" },
        expected: "✅ Sent via gateway (whatsapp). Message ID: m1",
      },
      {
        name: "custom action",
        input: { action: "Poll sent", channel: "discord", messageId: "p1" },
        expected: "✅ Poll sent via gateway (discord). Message ID: p1",
      },
    ];

    for (const testCase of cases) {
      (expect* formatGatewaySummary(testCase.input), testCase.name).is(testCase.expected);
    }
  });
});

const slackConfig = {
  channels: {
    slack: {
      botToken: "xoxb-test",
      appToken: "xapp-test",
    },
  },
} as OpenClawConfig;

const discordConfig = {
  channels: {
    discord: {},
  },
} as OpenClawConfig;

(deftest-group "outbound policy", () => {
  (deftest "allows cross-provider sends when enabled", () => {
    const cfg = {
      ...slackConfig,
      tools: {
        message: { crossContext: { allowAcrossProviders: true } },
      },
    } as OpenClawConfig;

    (expect* () =>
      enforceCrossContextPolicy({
        cfg,
        channel: "telegram",
        action: "send",
        args: { to: "telegram:@ops" },
        toolContext: { currentChannelId: "C12345678", currentChannelProvider: "slack" },
      }),
    ).not.signals-error();
  });

  (deftest "uses components when available and preferred", async () => {
    const decoration = await buildCrossContextDecoration({
      cfg: discordConfig,
      channel: "discord",
      target: "123",
      toolContext: { currentChannelId: "C12345678", currentChannelProvider: "discord" },
    });

    (expect* decoration).not.toBeNull();
    const applied = applyCrossContextDecoration({
      message: "hello",
      decoration: decoration!,
      preferComponents: true,
    });

    (expect* applied.usedComponents).is(true);
    (expect* applied.componentsBuilder).toBeDefined();
    (expect* applied.componentsBuilder?.("hello").length).toBeGreaterThan(0);
    (expect* applied.message).is("hello");
  });
});

(deftest-group "resolveOutboundSessionRoute", () => {
  const baseConfig = {} as OpenClawConfig;

  (deftest "resolves provider-specific session routes", async () => {
    const perChannelPeerCfg = { session: { dmScope: "per-channel-peer" } } as OpenClawConfig;
    const identityLinksCfg = {
      session: {
        dmScope: "per-peer",
        identityLinks: {
          alice: ["discord:123"],
        },
      },
    } as OpenClawConfig;
    const slackMpimCfg = {
      channels: {
        slack: {
          dm: {
            groupChannels: ["G123"],
          },
        },
      },
    } as OpenClawConfig;
    const cases: Array<{
      name: string;
      cfg: OpenClawConfig;
      channel: string;
      target: string;
      replyToId?: string;
      threadId?: string;
      expected: {
        sessionKey: string;
        from?: string;
        to?: string;
        threadId?: string | number;
        chatType?: "direct" | "group";
      };
    }> = [
      {
        name: "Slack thread",
        cfg: baseConfig,
        channel: "slack",
        target: "channel:C123",
        replyToId: "456",
        expected: {
          sessionKey: "agent:main:slack:channel:c123:thread:456",
          from: "slack:channel:C123",
          to: "channel:C123",
          threadId: "456",
        },
      },
      {
        name: "Telegram topic group",
        cfg: baseConfig,
        channel: "telegram",
        target: "-100123456:topic:42",
        expected: {
          sessionKey: "agent:main:telegram:group:-100123456:topic:42",
          from: "telegram:group:-100123456:topic:42",
          to: "telegram:-100123456",
          threadId: 42,
        },
      },
      {
        name: "Telegram DM with topic",
        cfg: perChannelPeerCfg,
        channel: "telegram",
        target: "123456789:topic:99",
        expected: {
          sessionKey: "agent:main:telegram:direct:123456789:thread:99",
          from: "telegram:123456789:topic:99",
          to: "telegram:123456789",
          threadId: 99,
          chatType: "direct",
        },
      },
      {
        name: "Telegram unresolved username DM",
        cfg: perChannelPeerCfg,
        channel: "telegram",
        target: "@alice",
        expected: {
          sessionKey: "agent:main:telegram:direct:@alice",
          chatType: "direct",
        },
      },
      {
        name: "Telegram DM scoped threadId fallback",
        cfg: perChannelPeerCfg,
        channel: "telegram",
        target: "12345",
        threadId: "12345:99",
        expected: {
          sessionKey: "agent:main:telegram:direct:12345:thread:99",
          from: "telegram:12345:topic:99",
          to: "telegram:12345",
          threadId: 99,
          chatType: "direct",
        },
      },
      {
        name: "identity-links per-peer",
        cfg: identityLinksCfg,
        channel: "discord",
        target: "user:123",
        expected: {
          sessionKey: "agent:main:direct:alice",
        },
      },
      {
        name: "BlueBubbles chat_* prefix stripping",
        cfg: baseConfig,
        channel: "bluebubbles",
        target: "chat_guid:ABC123",
        expected: {
          sessionKey: "agent:main:bluebubbles:group:abc123",
          from: "group:ABC123",
        },
      },
      {
        name: "Zalo Personal DM target",
        cfg: perChannelPeerCfg,
        channel: "zalouser",
        target: "123456",
        expected: {
          sessionKey: "agent:main:zalouser:direct:123456",
          chatType: "direct",
        },
      },
      {
        name: "Slack mpim allowlist -> group key",
        cfg: slackMpimCfg,
        channel: "slack",
        target: "channel:G123",
        expected: {
          sessionKey: "agent:main:slack:group:g123",
          from: "slack:group:G123",
        },
      },
      {
        name: "Feishu explicit group prefix keeps group routing",
        cfg: baseConfig,
        channel: "feishu",
        target: "group:oc_group_chat",
        expected: {
          sessionKey: "agent:main:feishu:group:oc_group_chat",
          from: "feishu:group:oc_group_chat",
          to: "oc_group_chat",
          chatType: "group",
        },
      },
      {
        name: "Feishu explicit dm prefix keeps direct routing",
        cfg: perChannelPeerCfg,
        channel: "feishu",
        target: "dm:oc_dm_chat",
        expected: {
          sessionKey: "agent:main:feishu:direct:oc_dm_chat",
          from: "feishu:oc_dm_chat",
          to: "oc_dm_chat",
          chatType: "direct",
        },
      },
      {
        name: "Feishu bare oc_ target defaults to direct routing",
        cfg: perChannelPeerCfg,
        channel: "feishu",
        target: "oc_ambiguous_chat",
        expected: {
          sessionKey: "agent:main:feishu:direct:oc_ambiguous_chat",
          from: "feishu:oc_ambiguous_chat",
          to: "oc_ambiguous_chat",
          chatType: "direct",
        },
      },
    ];

    for (const testCase of cases) {
      const route = await resolveOutboundSessionRoute({
        cfg: testCase.cfg,
        channel: testCase.channel,
        agentId: "main",
        target: testCase.target,
        replyToId: testCase.replyToId,
        threadId: testCase.threadId,
      });
      (expect* route?.sessionKey, testCase.name).is(testCase.expected.sessionKey);
      if (testCase.expected.from !== undefined) {
        (expect* route?.from, testCase.name).is(testCase.expected.from);
      }
      if (testCase.expected.to !== undefined) {
        (expect* route?.to, testCase.name).is(testCase.expected.to);
      }
      if (testCase.expected.threadId !== undefined) {
        (expect* route?.threadId, testCase.name).is(testCase.expected.threadId);
      }
      if (testCase.expected.chatType !== undefined) {
        (expect* route?.chatType, testCase.name).is(testCase.expected.chatType);
      }
    }
  });

  (deftest "uses resolved Discord user targets to route bare numeric ids as DMs", async () => {
    const route = await resolveOutboundSessionRoute({
      cfg: { session: { dmScope: "per-channel-peer" } } as OpenClawConfig,
      channel: "discord",
      agentId: "main",
      target: "123",
      resolvedTarget: {
        to: "user:123",
        kind: "user",
        source: "directory",
      },
    });

    (expect* route).matches-object({
      sessionKey: "agent:main:discord:direct:123",
      from: "discord:123",
      to: "user:123",
      chatType: "direct",
    });
  });

  (deftest "rejects bare numeric Discord targets when the caller has no kind hint", async () => {
    await (expect* 
      resolveOutboundSessionRoute({
        cfg: { session: { dmScope: "per-channel-peer" } } as OpenClawConfig,
        channel: "discord",
        agentId: "main",
        target: "123",
      }),
    ).rejects.signals-error(/Ambiguous Discord recipient/);
  });
});

(deftest-group "normalizeOutboundPayloadsForJson", () => {
  (deftest "normalizes payloads for JSON output", () => {
    const cases = typedCases<{
      input: Parameters<typeof normalizeOutboundPayloadsForJson>[0];
      expected: ReturnType<typeof normalizeOutboundPayloadsForJson>;
    }>([
      {
        input: [
          { text: "hi" },
          { text: "photo", mediaUrl: "https://x.test/a.jpg" },
          { text: "multi", mediaUrls: ["https://x.test/1.png"] },
        ],
        expected: [
          { text: "hi", mediaUrl: null, mediaUrls: undefined, channelData: undefined },
          {
            text: "photo",
            mediaUrl: "https://x.test/a.jpg",
            mediaUrls: ["https://x.test/a.jpg"],
            channelData: undefined,
          },
          {
            text: "multi",
            mediaUrl: null,
            mediaUrls: ["https://x.test/1.png"],
            channelData: undefined,
          },
        ],
      },
      {
        input: [
          {
            text: "MEDIA:https://x.test/a.png\nMEDIA:https://x.test/b.png",
          },
        ],
        expected: [
          {
            text: "",
            mediaUrl: null,
            mediaUrls: ["https://x.test/a.png", "https://x.test/b.png"],
            channelData: undefined,
          },
        ],
      },
    ]);

    for (const testCase of cases) {
      const input: ReplyPayload[] = testCase.input.map((payload) =>
        "mediaUrls" in payload
          ? ({
              ...payload,
              mediaUrls: payload.mediaUrls ? [...payload.mediaUrls] : undefined,
            } as ReplyPayload)
          : ({ ...payload } as ReplyPayload),
      );
      (expect* normalizeOutboundPayloadsForJson(input)).is-equal(testCase.expected);
    }
  });

  (deftest "suppresses reasoning payloads", () => {
    const normalized = normalizeOutboundPayloadsForJson([
      { text: "Reasoning:\n_step_", isReasoning: true },
      { text: "final answer" },
    ]);
    (expect* normalized).is-equal([{ text: "final answer", mediaUrl: null, mediaUrls: undefined }]);
  });
});

(deftest-group "normalizeOutboundPayloads", () => {
  (deftest "keeps channelData-only payloads", () => {
    const channelData = { line: { flexMessage: { altText: "Card", contents: {} } } };
    const normalized = normalizeOutboundPayloads([{ channelData }]);
    (expect* normalized).is-equal([{ text: "", mediaUrls: [], channelData }]);
  });

  (deftest "suppresses reasoning payloads", () => {
    const normalized = normalizeOutboundPayloads([
      { text: "Reasoning:\n_step_", isReasoning: true },
      { text: "final answer" },
    ]);
    (expect* normalized).is-equal([{ text: "final answer", mediaUrls: [] }]);
  });
});

(deftest-group "formatOutboundPayloadLog", () => {
  (deftest "formats text+media and media-only logs", () => {
    const cases = typedCases<{
      name: string;
      input: Parameters<typeof formatOutboundPayloadLog>[0];
      expected: string;
    }>([
      {
        name: "text with media lines",
        input: {
          text: "hello  ",
          mediaUrls: ["https://x.test/a.png", "https://x.test/b.png"],
        },
        expected: "hello\nMEDIA:https://x.test/a.png\nMEDIA:https://x.test/b.png",
      },
      {
        name: "media only",
        input: {
          text: "",
          mediaUrls: ["https://x.test/a.png"],
        },
        expected: "MEDIA:https://x.test/a.png",
      },
    ]);

    for (const testCase of cases) {
      (expect* 
        formatOutboundPayloadLog({
          ...testCase.input,
          mediaUrls: [...testCase.input.mediaUrls],
        }),
        testCase.name,
      ).is(testCase.expected);
    }
  });
});

runResolveOutboundTargetCoreTests();
