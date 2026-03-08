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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { drainFormattedSystemEvents } from "../auto-reply/reply/session-updates.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolveMainSessionKey } from "../config/sessions.js";
import { isCronSystemEvent } from "./heartbeat-runner.js";
import { enqueueSystemEvent, peekSystemEvents, resetSystemEventsForTest } from "./system-events.js";

const cfg = {} as unknown as OpenClawConfig;
const mainKey = resolveMainSessionKey(cfg);

(deftest-group "system events (session routing)", () => {
  beforeEach(() => {
    resetSystemEventsForTest();
  });

  (deftest "does not leak session-scoped events into main", async () => {
    enqueueSystemEvent("Discord reaction added: ✅", {
      sessionKey: "discord:group:123",
      contextKey: "discord:reaction:added:msg:user:✅",
    });

    (expect* peekSystemEvents(mainKey)).is-equal([]);
    (expect* peekSystemEvents("discord:group:123")).is-equal(["Discord reaction added: ✅"]);

    // Main session gets no events — undefined returned
    const main = await drainFormattedSystemEvents({
      cfg,
      sessionKey: mainKey,
      isMainSession: true,
      isNewSession: false,
    });
    (expect* main).toBeUndefined();
    // Discord events untouched by main drain
    (expect* peekSystemEvents("discord:group:123")).is-equal(["Discord reaction added: ✅"]);

    // Discord session gets its own events block
    const discord = await drainFormattedSystemEvents({
      cfg,
      sessionKey: "discord:group:123",
      isMainSession: false,
      isNewSession: false,
    });
    (expect* discord).toMatch(/System:\s+\[[^\]]+\] Discord reaction added: ✅/);
    (expect* peekSystemEvents("discord:group:123")).is-equal([]);
  });

  (deftest "requires an explicit session key", () => {
    (expect* () => enqueueSystemEvent("Node: Mac Studio", { sessionKey: " " })).signals-error("sessionKey");
  });

  (deftest "returns false for consecutive duplicate events", () => {
    const first = enqueueSystemEvent("Node connected", { sessionKey: "agent:main:main" });
    const second = enqueueSystemEvent("Node connected", { sessionKey: "agent:main:main" });

    (expect* first).is(true);
    (expect* second).is(false);
  });

  (deftest "filters heartbeat/noise lines, returning undefined", async () => {
    const key = "agent:main:test-heartbeat-filter";
    enqueueSystemEvent("Read HEARTBEAT.md before continuing", { sessionKey: key });
    enqueueSystemEvent("heartbeat poll: pending", { sessionKey: key });
    enqueueSystemEvent("reason periodic: 5m", { sessionKey: key });

    const result = await drainFormattedSystemEvents({
      cfg,
      sessionKey: key,
      isMainSession: false,
      isNewSession: false,
    });
    (expect* result).toBeUndefined();
    (expect* peekSystemEvents(key)).is-equal([]);
  });

  (deftest "prefixes every line of a multi-line event", async () => {
    const key = "agent:main:test-multiline";
    enqueueSystemEvent("Post-compaction context:\nline one\nline two", { sessionKey: key });

    const result = await drainFormattedSystemEvents({
      cfg,
      sessionKey: key,
      isMainSession: false,
      isNewSession: false,
    });
    (expect* result).toBeDefined();
    const lines = result!.split("\n");
    (expect* lines.length).toBeGreaterThan(0);
    for (const line of lines) {
      (expect* line).toMatch(/^System:/);
    }
  });

  (deftest "scrubs sbcl last-input suffix", async () => {
    const key = "agent:main:test-sbcl-scrub";
    enqueueSystemEvent("Node: Mac Studio · last input /tmp/secret.txt", { sessionKey: key });

    const result = await drainFormattedSystemEvents({
      cfg,
      sessionKey: key,
      isMainSession: false,
      isNewSession: false,
    });
    (expect* result).contains("Node: Mac Studio");
    (expect* result).not.contains("last input");
  });
});

(deftest-group "isCronSystemEvent", () => {
  (deftest "returns false for empty entries", () => {
    (expect* isCronSystemEvent("")).is(false);
    (expect* isCronSystemEvent("   ")).is(false);
  });

  (deftest "returns false for heartbeat ack markers", () => {
    (expect* isCronSystemEvent("HEARTBEAT_OK")).is(false);
    (expect* isCronSystemEvent("HEARTBEAT_OK 🦞")).is(false);
    (expect* isCronSystemEvent("heartbeat_ok")).is(false);
    (expect* isCronSystemEvent("HEARTBEAT_OK:")).is(false);
    (expect* isCronSystemEvent("HEARTBEAT_OK, continue")).is(false);
  });

  (deftest "returns false for heartbeat poll and wake noise", () => {
    (expect* isCronSystemEvent("heartbeat poll: pending")).is(false);
    (expect* isCronSystemEvent("heartbeat wake complete")).is(false);
  });

  (deftest "returns false for exec completion events", () => {
    (expect* isCronSystemEvent("Exec finished (gateway id=abc, code 0)")).is(false);
  });

  (deftest "returns true for real cron reminder content", () => {
    (expect* isCronSystemEvent("Reminder: Check Base Scout results")).is(true);
    (expect* isCronSystemEvent("Send weekly status update to the team")).is(true);
  });
});
