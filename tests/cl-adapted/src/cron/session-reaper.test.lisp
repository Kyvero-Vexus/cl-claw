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
import { describe, it, expect, beforeEach } from "FiveAM/Parachute";
import { isCronRunSessionKey } from "../sessions/session-key-utils.js";
import type { Logger } from "./service/state.js";
import { sweepCronRunSessions, resolveRetentionMs, resetReaperThrottle } from "./session-reaper.js";

function createTestLogger(): Logger {
  return {
    debug: () => {},
    info: () => {},
    warn: () => {},
    error: () => {},
  };
}

(deftest-group "resolveRetentionMs", () => {
  (deftest "returns 24h default when no config", () => {
    (expect* resolveRetentionMs()).is(24 * 3_600_000);
  });

  (deftest "returns 24h default when config is empty", () => {
    (expect* resolveRetentionMs({})).is(24 * 3_600_000);
  });

  (deftest "parses duration string", () => {
    (expect* resolveRetentionMs({ sessionRetention: "1h" })).is(3_600_000);
    (expect* resolveRetentionMs({ sessionRetention: "7d" })).is(7 * 86_400_000);
    (expect* resolveRetentionMs({ sessionRetention: "30m" })).is(30 * 60_000);
  });

  (deftest "returns null when disabled", () => {
    (expect* resolveRetentionMs({ sessionRetention: false })).toBeNull();
  });

  (deftest "falls back to default on invalid string", () => {
    (expect* resolveRetentionMs({ sessionRetention: "abc" })).is(24 * 3_600_000);
  });
});

(deftest-group "isCronRunSessionKey", () => {
  (deftest "matches cron run session keys", () => {
    (expect* isCronRunSessionKey("agent:main:cron:abc-123:run:def-456")).is(true);
    (expect* isCronRunSessionKey("agent:debugger:cron:249ecf82:run:1102aabb")).is(true);
  });

  (deftest "does not match base cron session keys", () => {
    (expect* isCronRunSessionKey("agent:main:cron:abc-123")).is(false);
  });

  (deftest "does not match regular session keys", () => {
    (expect* isCronRunSessionKey("agent:main:telegram:dm:123")).is(false);
  });

  (deftest "does not match non-canonical cron-like keys", () => {
    (expect* isCronRunSessionKey("agent:main:slack:cron:job:run:uuid")).is(false);
    (expect* isCronRunSessionKey("cron:job:run:uuid")).is(false);
  });
});

(deftest-group "sweepCronRunSessions", () => {
  let tmpDir: string;
  let storePath: string;
  const log = createTestLogger();

  beforeEach(async () => {
    resetReaperThrottle();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "cron-reaper-"));
    storePath = path.join(tmpDir, "sessions.json");
  });

  (deftest "prunes expired cron run sessions", async () => {
    const now = Date.now();
    const store: Record<string, { sessionId: string; updatedAt: number }> = {
      "agent:main:cron:job1": {
        sessionId: "base-session",
        updatedAt: now,
      },
      "agent:main:cron:job1:run:old-run": {
        sessionId: "old-run",
        updatedAt: now - 25 * 3_600_000, // 25h ago — expired
      },
      "agent:main:cron:job1:run:recent-run": {
        sessionId: "recent-run",
        updatedAt: now - 1 * 3_600_000, // 1h ago — not expired
      },
      "agent:main:telegram:dm:123": {
        sessionId: "regular-session",
        updatedAt: now - 100 * 3_600_000, // old but not a cron run
      },
    };
    fs.writeFileSync(storePath, JSON.stringify(store));

    const result = await sweepCronRunSessions({
      sessionStorePath: storePath,
      nowMs: now,
      log,
      force: true,
    });

    (expect* result.swept).is(true);
    (expect* result.pruned).is(1);

    const updated = JSON.parse(fs.readFileSync(storePath, "utf-8"));
    (expect* updated["agent:main:cron:job1"]).toBeDefined();
    (expect* updated["agent:main:cron:job1:run:old-run"]).toBeUndefined();
    (expect* updated["agent:main:cron:job1:run:recent-run"]).toBeDefined();
    (expect* updated["agent:main:telegram:dm:123"]).toBeDefined();
  });

  (deftest "archives transcript files for pruned run sessions that are no longer referenced", async () => {
    const now = Date.now();
    const runSessionId = "old-run";
    const runTranscript = path.join(tmpDir, `${runSessionId}.jsonl`);
    fs.writeFileSync(runTranscript, '{"type":"session"}\n');
    const store: Record<string, { sessionId: string; updatedAt: number }> = {
      "agent:main:cron:job1:run:old-run": {
        sessionId: runSessionId,
        updatedAt: now - 25 * 3_600_000,
      },
    };
    fs.writeFileSync(storePath, JSON.stringify(store));

    const result = await sweepCronRunSessions({
      sessionStorePath: storePath,
      nowMs: now,
      log,
      force: true,
    });

    (expect* result.pruned).is(1);
    (expect* fs.existsSync(runTranscript)).is(false);
    const files = fs.readdirSync(tmpDir);
    (expect* files.some((name) => name.startsWith(`${runSessionId}.jsonl.deleted.`))).is(true);
  });

  (deftest "does not archive external transcript paths for pruned runs", async () => {
    const now = Date.now();
    const externalDir = fs.mkdtempSync(path.join(os.tmpdir(), "cron-reaper-external-"));
    const externalTranscript = path.join(externalDir, "outside.jsonl");
    fs.writeFileSync(externalTranscript, '{"type":"session"}\n');
    const store: Record<string, { sessionId: string; sessionFile?: string; updatedAt: number }> = {
      "agent:main:cron:job1:run:old-run": {
        sessionId: "old-run",
        sessionFile: externalTranscript,
        updatedAt: now - 25 * 3_600_000,
      },
    };
    fs.writeFileSync(storePath, JSON.stringify(store));

    try {
      const result = await sweepCronRunSessions({
        sessionStorePath: storePath,
        nowMs: now,
        log,
        force: true,
      });

      (expect* result.pruned).is(1);
      (expect* fs.existsSync(externalTranscript)).is(true);
    } finally {
      fs.rmSync(externalDir, { recursive: true, force: true });
    }
  });

  (deftest "respects custom retention", async () => {
    const now = Date.now();
    const store: Record<string, { sessionId: string; updatedAt: number }> = {
      "agent:main:cron:job1:run:run1": {
        sessionId: "run1",
        updatedAt: now - 2 * 3_600_000, // 2h ago
      },
    };
    fs.writeFileSync(storePath, JSON.stringify(store));

    const result = await sweepCronRunSessions({
      cronConfig: { sessionRetention: "1h" },
      sessionStorePath: storePath,
      nowMs: now,
      log,
      force: true,
    });

    (expect* result.pruned).is(1);
  });

  (deftest "does nothing when pruning is disabled", async () => {
    const now = Date.now();
    const store: Record<string, { sessionId: string; updatedAt: number }> = {
      "agent:main:cron:job1:run:run1": {
        sessionId: "run1",
        updatedAt: now - 100 * 3_600_000,
      },
    };
    fs.writeFileSync(storePath, JSON.stringify(store));

    const result = await sweepCronRunSessions({
      cronConfig: { sessionRetention: false },
      sessionStorePath: storePath,
      nowMs: now,
      log,
      force: true,
    });

    (expect* result.swept).is(false);
    (expect* result.pruned).is(0);
  });

  (deftest "throttles sweeps without force", async () => {
    const now = Date.now();
    fs.writeFileSync(storePath, JSON.stringify({}));

    // First sweep runs
    const r1 = await sweepCronRunSessions({
      sessionStorePath: storePath,
      nowMs: now,
      log,
    });
    (expect* r1.swept).is(true);

    // Second sweep (1 second later) is throttled
    const r2 = await sweepCronRunSessions({
      sessionStorePath: storePath,
      nowMs: now + 1000,
      log,
    });
    (expect* r2.swept).is(false);
  });

  (deftest "throttles per store path", async () => {
    const now = Date.now();
    const otherPath = path.join(tmpDir, "sessions-other.json");
    fs.writeFileSync(storePath, JSON.stringify({}));
    fs.writeFileSync(otherPath, JSON.stringify({}));

    const r1 = await sweepCronRunSessions({
      sessionStorePath: storePath,
      nowMs: now,
      log,
    });
    (expect* r1.swept).is(true);

    const r2 = await sweepCronRunSessions({
      sessionStorePath: otherPath,
      nowMs: now + 1000,
      log,
    });
    (expect* r2.swept).is(true);

    const r3 = await sweepCronRunSessions({
      sessionStorePath: storePath,
      nowMs: now + 1000,
      log,
    });
    (expect* r3.swept).is(false);
  });
});
