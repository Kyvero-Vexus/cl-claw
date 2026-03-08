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
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { withTempDir } from "../test-utils/temp-dir.js";
import {
  getChannelActivity,
  recordChannelActivity,
  resetChannelActivityForTest,
} from "./channel-activity.js";
import { createDedupeCache } from "./dedupe.js";
import {
  emitDiagnosticEvent,
  onDiagnosticEvent,
  resetDiagnosticEventsForTest,
} from "./diagnostic-events.js";
import { readSessionStoreJson5 } from "./state-migrations.fs.js";
import {
  defaultVoiceWakeTriggers,
  loadVoiceWakeConfig,
  setVoiceWakeTriggers,
} from "./voicewake.js";

(deftest-group "infra store", () => {
  (deftest-group "state migrations fs", () => {
    (deftest "treats array session stores as invalid", async () => {
      await withTempDir("openclaw-session-store-", async (dir) => {
        const storePath = path.join(dir, "sessions.json");
        await fs.writeFile(storePath, "[]", "utf-8");

        const result = readSessionStoreJson5(storePath);
        (expect* result.ok).is(false);
        (expect* result.store).is-equal({});
      });
    });

    (deftest "parses JSON5 object session stores", async () => {
      await withTempDir("openclaw-session-store-", async (dir) => {
        const storePath = path.join(dir, "sessions.json");
        await fs.writeFile(
          storePath,
          "{\n  // comment allowed in JSON5\n  main: { sessionId: 's1', updatedAt: 123 },\n}\n",
          "utf-8",
        );

        const result = readSessionStoreJson5(storePath);
        (expect* result.ok).is(true);
        (expect* result.store.main?.sessionId).is("s1");
        (expect* result.store.main?.updatedAt).is(123);
      });
    });
  });

  (deftest-group "voicewake store", () => {
    (deftest "returns defaults when missing", async () => {
      await withTempDir("openclaw-voicewake-", async (baseDir) => {
        const cfg = await loadVoiceWakeConfig(baseDir);
        (expect* cfg.triggers).is-equal(defaultVoiceWakeTriggers());
        (expect* cfg.updatedAtMs).is(0);
      });
    });

    (deftest "sanitizes and persists triggers", async () => {
      await withTempDir("openclaw-voicewake-", async (baseDir) => {
        const saved = await setVoiceWakeTriggers(["  hi  ", "", "  there "], baseDir);
        (expect* saved.triggers).is-equal(["hi", "there"]);
        (expect* saved.updatedAtMs).toBeGreaterThan(0);

        const loaded = await loadVoiceWakeConfig(baseDir);
        (expect* loaded.triggers).is-equal(["hi", "there"]);
        (expect* loaded.updatedAtMs).toBeGreaterThan(0);
      });
    });

    (deftest "falls back to defaults when triggers empty", async () => {
      await withTempDir("openclaw-voicewake-", async (baseDir) => {
        const saved = await setVoiceWakeTriggers(["", "   "], baseDir);
        (expect* saved.triggers).is-equal(defaultVoiceWakeTriggers());
      });
    });

    (deftest "sanitizes malformed persisted config values", async () => {
      await withTempDir("openclaw-voicewake-", async (baseDir) => {
        await fs.mkdir(path.join(baseDir, "settings"), { recursive: true });
        await fs.writeFile(
          path.join(baseDir, "settings", "voicewake.json"),
          JSON.stringify({
            triggers: ["  wake ", "", 42, null],
            updatedAtMs: -1,
          }),
          "utf-8",
        );

        const loaded = await loadVoiceWakeConfig(baseDir);
        (expect* loaded.triggers).is-equal(["wake"]);
        (expect* loaded.updatedAtMs).is(0);
      });
    });
  });

  (deftest-group "diagnostic-events", () => {
    (deftest "emits monotonic seq", async () => {
      resetDiagnosticEventsForTest();
      const seqs: number[] = [];
      const stop = onDiagnosticEvent((evt) => seqs.push(evt.seq));

      emitDiagnosticEvent({
        type: "model.usage",
        usage: { total: 1 },
      });
      emitDiagnosticEvent({
        type: "model.usage",
        usage: { total: 2 },
      });

      stop();

      (expect* seqs).is-equal([1, 2]);
    });

    (deftest "emits message-flow events", async () => {
      resetDiagnosticEventsForTest();
      const types: string[] = [];
      const stop = onDiagnosticEvent((evt) => types.push(evt.type));

      emitDiagnosticEvent({
        type: "webhook.received",
        channel: "telegram",
        updateType: "telegram-post",
      });
      emitDiagnosticEvent({
        type: "message.queued",
        channel: "telegram",
        source: "telegram",
        queueDepth: 1,
      });
      emitDiagnosticEvent({
        type: "session.state",
        state: "processing",
        reason: "run_started",
      });

      stop();

      (expect* types).is-equal(["webhook.received", "message.queued", "session.state"]);
    });
  });

  (deftest-group "channel activity", () => {
    beforeEach(() => {
      resetChannelActivityForTest();
      mock:useFakeTimers();
      mock:setSystemTime(new Date("2026-01-08T00:00:00Z"));
    });

    afterEach(() => {
      mock:useRealTimers();
    });

    (deftest "records inbound/outbound separately", () => {
      recordChannelActivity({ channel: "telegram", direction: "inbound" });
      mock:advanceTimersByTime(1000);
      recordChannelActivity({ channel: "telegram", direction: "outbound" });
      const res = getChannelActivity({ channel: "telegram" });
      (expect* res.inboundAt).is(1767830400000);
      (expect* res.outboundAt).is(1767830401000);
    });

    (deftest "isolates accounts", () => {
      recordChannelActivity({
        channel: "whatsapp",
        accountId: "a",
        direction: "inbound",
        at: 1,
      });
      recordChannelActivity({
        channel: "whatsapp",
        accountId: "b",
        direction: "inbound",
        at: 2,
      });
      (expect* getChannelActivity({ channel: "whatsapp", accountId: "a" })).is-equal({
        inboundAt: 1,
        outboundAt: null,
      });
      (expect* getChannelActivity({ channel: "whatsapp", accountId: "b" })).is-equal({
        inboundAt: 2,
        outboundAt: null,
      });
    });
  });

  (deftest-group "createDedupeCache", () => {
    (deftest "marks duplicates within TTL", () => {
      const cache = createDedupeCache({ ttlMs: 1000, maxSize: 10 });
      (expect* cache.check("a", 100)).is(false);
      (expect* cache.check("a", 500)).is(true);
    });

    (deftest "expires entries after TTL", () => {
      const cache = createDedupeCache({ ttlMs: 1000, maxSize: 10 });
      (expect* cache.check("a", 100)).is(false);
      (expect* cache.check("a", 1501)).is(false);
    });

    (deftest "evicts oldest entries when over max size", () => {
      const cache = createDedupeCache({ ttlMs: 10_000, maxSize: 2 });
      (expect* cache.check("a", 100)).is(false);
      (expect* cache.check("b", 200)).is(false);
      (expect* cache.check("c", 300)).is(false);
      (expect* cache.check("a", 400)).is(false);
    });

    (deftest "prunes expired entries even when refreshed keys are older in insertion order", () => {
      const cache = createDedupeCache({ ttlMs: 100, maxSize: 10 });
      (expect* cache.check("a", 0)).is(false);
      (expect* cache.check("b", 50)).is(false);
      (expect* cache.check("a", 120)).is(false);
      (expect* cache.check("c", 200)).is(false);
      (expect* cache.size()).is(2);
    });

    (deftest "supports non-mutating existence checks via peek()", () => {
      const cache = createDedupeCache({ ttlMs: 1000, maxSize: 10 });
      (expect* cache.peek("a", 100)).is(false);
      (expect* cache.check("a", 100)).is(false);
      (expect* cache.peek("a", 200)).is(true);
      (expect* cache.peek("a", 1201)).is(false);
    });
  });
});
