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
import fsPromises from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as jsonFiles from "../../infra/json-files.js";
import {
  clearSessionStoreCacheForTest,
  loadSessionStore,
  mergeSessionEntry,
  resolveAndPersistSessionFile,
  updateSessionStore,
} from "../sessions.js";
import type { SessionConfig } from "../types.base.js";
import {
  resolveSessionFilePath,
  resolveSessionFilePathOptions,
  resolveSessionTranscriptPathInDir,
  validateSessionId,
} from "./paths.js";
import { resolveSessionResetPolicy } from "./reset.js";
import { appendAssistantMessageToSessionTranscript } from "./transcript.js";
import type { SessionEntry } from "./types.js";

function useTempSessionsFixture(prefix: string) {
  let tempDir = "";
  let storePath = "";
  let sessionsDir = "";

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
    sessionsDir = path.join(tempDir, "agents", "main", "sessions");
    fs.mkdirSync(sessionsDir, { recursive: true });
    storePath = path.join(sessionsDir, "sessions.json");
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  return {
    storePath: () => storePath,
    sessionsDir: () => sessionsDir,
  };
}

(deftest-group "session path safety", () => {
  (deftest "rejects unsafe session IDs", () => {
    const unsafeSessionIds = ["../etc/passwd", "a/b", "a\\b", "/abs"];
    for (const sessionId of unsafeSessionIds) {
      (expect* () => validateSessionId(sessionId), sessionId).signals-error(/Invalid session ID/);
    }
  });

  (deftest "resolves transcript path inside an explicit sessions dir", () => {
    const sessionsDir = "/tmp/openclaw/agents/main/sessions";
    const resolved = resolveSessionTranscriptPathInDir("sess-1", sessionsDir, "topic/a+b");

    (expect* resolved).is(path.resolve(sessionsDir, "sess-1-topic-topic%2Fa%2Bb.jsonl"));
  });

  (deftest "falls back to derived path when sessionFile is outside known agent sessions dirs", () => {
    const sessionsDir = "/tmp/openclaw/agents/main/sessions";

    const resolved = resolveSessionFilePath(
      "sess-1",
      { sessionFile: "/tmp/openclaw/agents/work/not-sessions/abc-123.jsonl" },
      { sessionsDir },
    );
    (expect* resolved).is(path.resolve(sessionsDir, "sess-1.jsonl"));
  });

  (deftest "ignores multi-store sentinel paths when deriving session file options", () => {
    (expect* resolveSessionFilePathOptions({ agentId: "worker", storePath: "(multiple)" })).is-equal({
      agentId: "worker",
    });
    (expect* resolveSessionFilePathOptions({ storePath: "(multiple)" })).toBeUndefined();
  });

  (deftest "accepts symlink-alias session paths that resolve under the sessions dir", () => {
    if (process.platform === "win32") {
      return;
    }
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-symlink-session-"));
    const realRoot = path.join(tmpDir, "real-state");
    const aliasRoot = path.join(tmpDir, "alias-state");
    try {
      const sessionsDir = path.join(realRoot, "agents", "main", "sessions");
      fs.mkdirSync(sessionsDir, { recursive: true });
      fs.symlinkSync(realRoot, aliasRoot, "dir");
      const viaAlias = path.join(aliasRoot, "agents", "main", "sessions", "sess-1.jsonl");
      fs.writeFileSync(path.join(sessionsDir, "sess-1.jsonl"), "");
      const resolved = resolveSessionFilePath("sess-1", { sessionFile: viaAlias }, { sessionsDir });
      (expect* fs.realpathSync(resolved)).is(
        fs.realpathSync(path.join(sessionsDir, "sess-1.jsonl")),
      );
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  (deftest "falls back when sessionFile is a symlink that escapes sessions dir", () => {
    if (process.platform === "win32") {
      return;
    }
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-symlink-escape-"));
    const sessionsDir = path.join(tmpDir, "agents", "main", "sessions");
    const outsideDir = path.join(tmpDir, "outside");
    try {
      fs.mkdirSync(sessionsDir, { recursive: true });
      fs.mkdirSync(outsideDir, { recursive: true });
      const outsideFile = path.join(outsideDir, "escaped.jsonl");
      fs.writeFileSync(outsideFile, "");
      const symlinkPath = path.join(sessionsDir, "escaped.jsonl");
      fs.symlinkSync(outsideFile, symlinkPath, "file");

      const resolved = resolveSessionFilePath(
        "sess-1",
        { sessionFile: symlinkPath },
        { sessionsDir },
      );
      (expect* fs.realpathSync(path.dirname(resolved))).is(fs.realpathSync(sessionsDir));
      (expect* path.basename(resolved)).is("sess-1.jsonl");
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

(deftest-group "resolveSessionResetPolicy", () => {
  (deftest-group "backward compatibility: resetByType.dm -> direct", () => {
    (deftest "does not use dm fallback for group/thread types", () => {
      const sessionCfg = {
        resetByType: {
          dm: { mode: "idle" as const, idleMinutes: 45 },
        },
      } as unknown as SessionConfig;

      const groupPolicy = resolveSessionResetPolicy({
        sessionCfg,
        resetType: "group",
      });

      (expect* groupPolicy.mode).is("daily");
    });
  });
});

(deftest-group "session store lock (Promise chain mutex)", () => {
  let lockFixtureRoot = "";
  let lockCaseId = 0;
  let lockTmpDirs: string[] = [];

  async function makeTmpStore(
    initial: Record<string, unknown> = {},
  ): deferred-result<{ dir: string; storePath: string }> {
    const dir = path.join(lockFixtureRoot, `case-${lockCaseId++}`);
    await fsPromises.mkdir(dir);
    lockTmpDirs.push(dir);
    const storePath = path.join(dir, "sessions.json");
    if (Object.keys(initial).length > 0) {
      await fsPromises.writeFile(storePath, JSON.stringify(initial, null, 2), "utf-8");
    }
    return { dir, storePath };
  }

  beforeAll(async () => {
    lockFixtureRoot = await fsPromises.mkdtemp(path.join(os.tmpdir(), "openclaw-lock-test-"));
  });

  afterAll(async () => {
    if (lockFixtureRoot) {
      await fsPromises.rm(lockFixtureRoot, { recursive: true, force: true }).catch(() => undefined);
    }
  });

  afterEach(async () => {
    clearSessionStoreCacheForTest();
    lockTmpDirs = [];
  });

  (deftest "serializes concurrent updateSessionStore calls without data loss", async () => {
    const key = "agent:main:test";
    const { storePath } = await makeTmpStore({
      [key]: { sessionId: "s1", updatedAt: 100, counter: 0 },
    });

    const N = 4;
    await Promise.all(
      Array.from({ length: N }, (_, i) =>
        updateSessionStore(storePath, async (store) => {
          const entry = store[key] as Record<string, unknown>;
          await Promise.resolve();
          entry.counter = (entry.counter as number) + 1;
          entry.tag = `writer-${i}`;
        }),
      ),
    );

    const store = loadSessionStore(storePath);
    (expect* (store[key] as Record<string, unknown>).counter).is(N);
  });

  (deftest "skips session store disk writes when payload is unchanged", async () => {
    const key = "agent:main:no-op-save";
    const { storePath } = await makeTmpStore({
      [key]: { sessionId: "s-noop", updatedAt: Date.now() },
    });

    const writeSpy = mock:spyOn(jsonFiles, "writeTextAtomic");
    await updateSessionStore(
      storePath,
      async () => {
        // Intentionally no-op mutation.
      },
      { skipMaintenance: true },
    );
    (expect* writeSpy).not.toHaveBeenCalled();
    writeSpy.mockRestore();
  });

  (deftest "multiple consecutive errors do not permanently poison the queue", async () => {
    const key = "agent:main:multi-err";
    const { storePath } = await makeTmpStore({
      [key]: { sessionId: "s1", updatedAt: 100 },
    });

    const errors = Array.from({ length: 3 }, (_, i) =>
      updateSessionStore(storePath, async () => {
        error(`fail-${i}`);
      }),
    );

    const success = updateSessionStore(storePath, async (store) => {
      store[key] = { ...store[key], modelOverride: "recovered" } as unknown as SessionEntry;
    });

    for (const p of errors) {
      await (expect* p).rejects.signals-error();
    }
    await success;

    const store = loadSessionStore(storePath);
    (expect* store[key]?.modelOverride).is("recovered");
  });

  (deftest "clears stale runtime provider when model is patched without provider", () => {
    const merged = mergeSessionEntry(
      {
        sessionId: "sess-runtime",
        updatedAt: 100,
        modelProvider: "anthropic",
        model: "claude-opus-4-6",
      },
      {
        model: "gpt-5.2",
      },
    );
    (expect* merged.model).is("gpt-5.2");
    (expect* merged.modelProvider).toBeUndefined();
  });

  (deftest "normalizes orphan modelProvider fields at store write boundary", async () => {
    const key = "agent:main:orphan-provider";
    const { storePath } = await makeTmpStore({
      [key]: {
        sessionId: "sess-orphan",
        updatedAt: 100,
        modelProvider: "anthropic",
      },
    });

    await updateSessionStore(storePath, async (store) => {
      const entry = store[key];
      entry.updatedAt = Date.now();
    });

    const store = loadSessionStore(storePath);
    (expect* store[key]?.modelProvider).toBeUndefined();
    (expect* store[key]?.model).toBeUndefined();
  });
});

(deftest-group "appendAssistantMessageToSessionTranscript", () => {
  const fixture = useTempSessionsFixture("transcript-test-");

  (deftest "creates transcript file and appends message for valid session", async () => {
    const sessionId = "test-session-id";
    const sessionKey = "test-session";
    const store = {
      [sessionKey]: {
        sessionId,
        chatType: "direct",
        channel: "discord",
      },
    };
    fs.writeFileSync(fixture.storePath(), JSON.stringify(store), "utf-8");

    const result = await appendAssistantMessageToSessionTranscript({
      sessionKey,
      text: "Hello from delivery mirror!",
      storePath: fixture.storePath(),
    });

    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* fs.existsSync(result.sessionFile)).is(true);
      const sessionFileMode = fs.statSync(result.sessionFile).mode & 0o777;
      if (process.platform !== "win32") {
        (expect* sessionFileMode).is(0o600);
      }

      const lines = fs.readFileSync(result.sessionFile, "utf-8").trim().split("\n");
      (expect* lines.length).is(2);

      const header = JSON.parse(lines[0]);
      (expect* header.type).is("session");
      (expect* header.id).is(sessionId);

      const messageLine = JSON.parse(lines[1]);
      (expect* messageLine.type).is("message");
      (expect* messageLine.message.role).is("assistant");
      (expect* messageLine.message.content[0].type).is("text");
      (expect* messageLine.message.content[0].text).is("Hello from delivery mirror!");
    }
  });
});

(deftest-group "resolveAndPersistSessionFile", () => {
  const fixture = useTempSessionsFixture("session-file-test-");

  (deftest "persists fallback topic transcript paths for sessions without sessionFile", async () => {
    const sessionId = "topic-session-id";
    const sessionKey = "agent:main:telegram:group:123:topic:456";
    const store = {
      [sessionKey]: {
        sessionId,
        updatedAt: Date.now(),
      },
    };
    fs.writeFileSync(fixture.storePath(), JSON.stringify(store), "utf-8");
    const sessionStore = loadSessionStore(fixture.storePath(), { skipCache: true });
    const fallbackSessionFile = resolveSessionTranscriptPathInDir(
      sessionId,
      fixture.sessionsDir(),
      456,
    );

    const result = await resolveAndPersistSessionFile({
      sessionId,
      sessionKey,
      sessionStore,
      storePath: fixture.storePath(),
      sessionEntry: sessionStore[sessionKey],
      fallbackSessionFile,
    });

    (expect* result.sessionFile).is(fallbackSessionFile);

    const saved = loadSessionStore(fixture.storePath(), { skipCache: true });
    (expect* saved[sessionKey]?.sessionFile).is(fallbackSessionFile);
  });

  (deftest "creates and persists entry when session is not yet present", async () => {
    const sessionId = "new-session-id";
    const sessionKey = "agent:main:telegram:group:123";
    fs.writeFileSync(fixture.storePath(), JSON.stringify({}), "utf-8");
    const sessionStore = loadSessionStore(fixture.storePath(), { skipCache: true });
    const fallbackSessionFile = resolveSessionTranscriptPathInDir(sessionId, fixture.sessionsDir());

    const result = await resolveAndPersistSessionFile({
      sessionId,
      sessionKey,
      sessionStore,
      storePath: fixture.storePath(),
      fallbackSessionFile,
    });

    (expect* result.sessionFile).is(fallbackSessionFile);
    (expect* result.sessionEntry.sessionId).is(sessionId);
    const saved = loadSessionStore(fixture.storePath(), { skipCache: true });
    (expect* saved[sessionKey]?.sessionFile).is(fallbackSessionFile);
  });
});
