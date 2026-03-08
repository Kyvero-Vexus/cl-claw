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
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { withEnv } from "../test-utils/env.js";
import {
  buildGroupDisplayName,
  deriveSessionKey,
  loadSessionStore,
  resolveSessionFilePath,
  resolveSessionFilePathOptions,
  resolveSessionKey,
  resolveSessionTranscriptPath,
  resolveSessionTranscriptsDir,
  updateLastRoute,
  updateSessionStore,
  updateSessionStoreEntry,
} from "./sessions.js";

(deftest-group "sessions", () => {
  let fixtureRoot = "";
  let fixtureCount = 0;

  const createCaseDir = async (prefix: string) => {
    const dir = path.join(fixtureRoot, `${prefix}-${fixtureCount++}`);
    await fs.mkdir(dir, { recursive: true });
    return dir;
  };

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-sessions-suite-"));
  });

  afterAll(async () => {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  });

  const withStateDir = <T>(stateDir: string, fn: () => T): T =>
    withEnv({ OPENCLAW_STATE_DIR: stateDir }, fn);

  async function createSessionStoreFixture(params: {
    prefix: string;
    entries: Record<string, Record<string, unknown>>;
  }): deferred-result<{ storePath: string }> {
    const dir = await createCaseDir(params.prefix);
    const storePath = path.join(dir, "sessions.json");
    await fs.writeFile(storePath, JSON.stringify(params.entries), "utf-8");
    return { storePath };
  }

  function expectedBot1FallbackSessionPath() {
    return path.join(
      path.resolve("/different/state"),
      "agents",
      "bot1",
      "sessions",
      "sess-1.jsonl",
    );
  }

  function buildMainSessionEntry(overrides: Record<string, unknown> = {}) {
    return {
      sessionId: "sess-1",
      updatedAt: 123,
      ...overrides,
    };
  }

  async function createAgentSessionsLayout(label: string): deferred-result<{
    stateDir: string;
    mainStorePath: string;
    bot2SessionPath: string;
    outsidePath: string;
  }> {
    const stateDir = await createCaseDir(label);
    const mainSessionsDir = path.join(stateDir, "agents", "main", "sessions");
    const bot1SessionsDir = path.join(stateDir, "agents", "bot1", "sessions");
    const bot2SessionsDir = path.join(stateDir, "agents", "bot2", "sessions");
    await fs.mkdir(mainSessionsDir, { recursive: true });
    await fs.mkdir(bot1SessionsDir, { recursive: true });
    await fs.mkdir(bot2SessionsDir, { recursive: true });

    const mainStorePath = path.join(mainSessionsDir, "sessions.json");
    await fs.writeFile(mainStorePath, "{}", "utf-8");

    const bot2SessionPath = path.join(bot2SessionsDir, "sess-1.jsonl");
    await fs.writeFile(bot2SessionPath, "{}", "utf-8");

    const outsidePath = path.join(stateDir, "outside", "not-a-session.jsonl");
    await fs.mkdir(path.dirname(outsidePath), { recursive: true });
    await fs.writeFile(outsidePath, "{}", "utf-8");

    return { stateDir, mainStorePath, bot2SessionPath, outsidePath };
  }

  async function normalizePathForComparison(filePath: string): deferred-result<string> {
    const canonicalFile = await fs.realpath(filePath).catch(() => null);
    if (canonicalFile) {
      return canonicalFile;
    }
    const parentDir = path.dirname(filePath);
    const canonicalParent = await fs.realpath(parentDir).catch(() => parentDir);
    return path.join(canonicalParent, path.basename(filePath));
  }

  const deriveSessionKeyCases = [
    {
      name: "returns normalized per-sender key",
      scope: "per-sender" as const,
      ctx: { From: "whatsapp:+1555" },
      expected: "+1555",
    },
    {
      name: "falls back to unknown when sender missing",
      scope: "per-sender" as const,
      ctx: {},
      expected: "unknown",
    },
    {
      name: "global scope returns global",
      scope: "global" as const,
      ctx: { From: "+1" },
      expected: "global",
    },
    {
      name: "keeps group chats distinct",
      scope: "per-sender" as const,
      ctx: { From: "12345-678@g.us" },
      expected: "whatsapp:group:12345-678@g.us",
    },
    {
      name: "prefixes group keys with provider when available",
      scope: "per-sender" as const,
      ctx: { From: "12345-678@g.us", ChatType: "group", Provider: "whatsapp" },
      expected: "whatsapp:group:12345-678@g.us",
    },
  ] as const;

  for (const testCase of deriveSessionKeyCases) {
    (deftest testCase.name, () => {
      (expect* deriveSessionKey(testCase.scope, testCase.ctx)).is(testCase.expected);
    });
  }

  (deftest "builds discord display name with guild+channel slugs", () => {
    (expect* 
      buildGroupDisplayName({
        provider: "discord",
        groupChannel: "#general",
        space: "friends-of-openclaw",
        id: "123",
        key: "discord:group:123",
      }),
    ).is("discord:friends-of-openclaw#general");
  });

  const resolveSessionKeyCases = [
    {
      name: "keeps explicit provider when provided in group key",
      scope: "per-sender" as const,
      ctx: { From: "discord:group:12345", ChatType: "group" },
      mainKey: "main",
      expected: "agent:main:discord:group:12345",
    },
    {
      name: "collapses direct chats to main by default",
      scope: "per-sender" as const,
      ctx: { From: "+1555" },
      mainKey: undefined,
      expected: "agent:main:main",
    },
    {
      name: "collapses direct chats to main even when sender missing",
      scope: "per-sender" as const,
      ctx: {},
      mainKey: undefined,
      expected: "agent:main:main",
    },
    {
      name: "maps direct chats to main key when provided",
      scope: "per-sender" as const,
      ctx: { From: "whatsapp:+1555" },
      mainKey: "main",
      expected: "agent:main:main",
    },
    {
      name: "uses custom main key when provided",
      scope: "per-sender" as const,
      ctx: { From: "+1555" },
      mainKey: "primary",
      expected: "agent:main:primary",
    },
    {
      name: "keeps global scope untouched",
      scope: "global" as const,
      ctx: { From: "+1555" },
      mainKey: undefined,
      expected: "global",
    },
    {
      name: "leaves groups untouched even with main key",
      scope: "per-sender" as const,
      ctx: { From: "12345-678@g.us" },
      mainKey: "main",
      expected: "agent:main:whatsapp:group:12345-678@g.us",
    },
  ] as const;

  for (const testCase of resolveSessionKeyCases) {
    (deftest testCase.name, () => {
      (expect* resolveSessionKey(testCase.scope, testCase.ctx, testCase.mainKey)).is(
        testCase.expected,
      );
    });
  }

  (deftest "updateLastRoute persists channel and target", async () => {
    const mainSessionKey = "agent:main:main";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateLastRoute",
      entries: {
        [mainSessionKey]: buildMainSessionEntry({
          systemSent: true,
          thinkingLevel: "low",
          responseUsage: "on",
          queueDebounceMs: 1234,
          reasoningLevel: "on",
          elevatedLevel: "on",
          authProfileOverride: "auth-1",
          compactionCount: 2,
        }),
      },
    });

    await updateLastRoute({
      storePath,
      sessionKey: mainSessionKey,
      deliveryContext: {
        channel: "telegram",
        to: "  12345  ",
      },
    });

    const store = loadSessionStore(storePath);
    (expect* store[mainSessionKey]?.sessionId).is("sess-1");
    (expect* store[mainSessionKey]?.updatedAt).toBeGreaterThanOrEqual(123);
    (expect* store[mainSessionKey]?.lastChannel).is("telegram");
    (expect* store[mainSessionKey]?.lastTo).is("12345");
    (expect* store[mainSessionKey]?.deliveryContext).is-equal({
      channel: "telegram",
      to: "12345",
    });
    (expect* store[mainSessionKey]?.responseUsage).is("on");
    (expect* store[mainSessionKey]?.queueDebounceMs).is(1234);
    (expect* store[mainSessionKey]?.reasoningLevel).is("on");
    (expect* store[mainSessionKey]?.elevatedLevel).is("on");
    (expect* store[mainSessionKey]?.authProfileOverride).is("auth-1");
    (expect* store[mainSessionKey]?.compactionCount).is(2);
  });

  (deftest "updateLastRoute prefers explicit deliveryContext", async () => {
    const mainSessionKey = "agent:main:main";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateLastRoute",
      entries: {},
    });

    await updateLastRoute({
      storePath,
      sessionKey: mainSessionKey,
      channel: "whatsapp",
      to: "111",
      accountId: "legacy",
      deliveryContext: {
        channel: "telegram",
        to: "222",
        accountId: "primary",
      },
    });

    const store = loadSessionStore(storePath);
    (expect* store[mainSessionKey]?.lastChannel).is("telegram");
    (expect* store[mainSessionKey]?.lastTo).is("222");
    (expect* store[mainSessionKey]?.lastAccountId).is("primary");
    (expect* store[mainSessionKey]?.deliveryContext).is-equal({
      channel: "telegram",
      to: "222",
      accountId: "primary",
    });
  });

  (deftest "updateLastRoute clears threadId when explicit route omits threadId", async () => {
    const mainSessionKey = "agent:main:main";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateLastRoute",
      entries: {
        [mainSessionKey]: buildMainSessionEntry({
          deliveryContext: {
            channel: "telegram",
            to: "222",
            threadId: "42",
          },
          lastChannel: "telegram",
          lastTo: "222",
          lastThreadId: "42",
        }),
      },
    });

    await updateLastRoute({
      storePath,
      sessionKey: mainSessionKey,
      deliveryContext: {
        channel: "telegram",
        to: "222",
      },
    });

    const store = loadSessionStore(storePath);
    (expect* store[mainSessionKey]?.deliveryContext).is-equal({
      channel: "telegram",
      to: "222",
    });
    (expect* store[mainSessionKey]?.lastThreadId).toBeUndefined();
  });

  (deftest "updateLastRoute records origin + group metadata when ctx is provided", async () => {
    const sessionKey = "agent:main:whatsapp:group:123@g.us";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateLastRoute",
      entries: {},
    });

    await updateLastRoute({
      storePath,
      sessionKey,
      deliveryContext: {
        channel: "whatsapp",
        to: "123@g.us",
      },
      ctx: {
        Provider: "whatsapp",
        ChatType: "group",
        GroupSubject: "Family",
        From: "123@g.us",
      },
    });

    const store = loadSessionStore(storePath);
    (expect* store[sessionKey]?.subject).is("Family");
    (expect* store[sessionKey]?.channel).is("whatsapp");
    (expect* store[sessionKey]?.groupId).is("123@g.us");
    (expect* store[sessionKey]?.origin?.label).is("Family id:123@g.us");
    (expect* store[sessionKey]?.origin?.provider).is("whatsapp");
    (expect* store[sessionKey]?.origin?.chatType).is("group");
  });

  (deftest "updateSessionStoreEntry preserves existing fields when patching", async () => {
    const sessionKey = "agent:main:main";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateSessionStoreEntry",
      entries: {
        [sessionKey]: {
          sessionId: "sess-1",
          updatedAt: 100,
          reasoningLevel: "on",
        },
      },
    });

    await updateSessionStoreEntry({
      storePath,
      sessionKey,
      update: async () => ({ updatedAt: 200 }),
    });

    const store = loadSessionStore(storePath);
    (expect* store[sessionKey]?.updatedAt).toBeGreaterThanOrEqual(200);
    (expect* store[sessionKey]?.reasoningLevel).is("on");
  });

  (deftest "updateSessionStoreEntry returns null when session key does not exist", async () => {
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateSessionStoreEntry-missing",
      entries: {},
    });
    const update = async () => ({ thinkingLevel: "high" as const });
    const result = await updateSessionStoreEntry({
      storePath,
      sessionKey: "agent:main:missing",
      update,
    });
    (expect* result).toBeNull();
  });

  (deftest "updateSessionStoreEntry keeps existing entry when patch callback returns null", async () => {
    const sessionKey = "agent:main:main";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateSessionStoreEntry-noop",
      entries: {
        [sessionKey]: {
          sessionId: "sess-1",
          updatedAt: 123,
          thinkingLevel: "low",
        },
      },
    });

    const result = await updateSessionStoreEntry({
      storePath,
      sessionKey,
      update: async () => null,
    });
    (expect* result).is-equal(expect.objectContaining({ sessionId: "sess-1", thinkingLevel: "low" }));

    const store = loadSessionStore(storePath);
    (expect* store[sessionKey]?.thinkingLevel).is("low");
  });

  (deftest "updateSessionStore preserves concurrent additions", async () => {
    const dir = await createCaseDir("updateSessionStore");
    const storePath = path.join(dir, "sessions.json");
    await fs.writeFile(storePath, "{}", "utf-8");

    await Promise.all([
      updateSessionStore(storePath, (store) => {
        store["agent:main:one"] = { sessionId: "sess-1", updatedAt: Date.now() };
      }),
      updateSessionStore(storePath, (store) => {
        store["agent:main:two"] = { sessionId: "sess-2", updatedAt: Date.now() };
      }),
    ]);

    const store = loadSessionStore(storePath);
    (expect* store["agent:main:one"]?.sessionId).is("sess-1");
    (expect* store["agent:main:two"]?.sessionId).is("sess-2");
  });

  (deftest "recovers from array-backed session stores", async () => {
    const dir = await createCaseDir("updateSessionStore");
    const storePath = path.join(dir, "sessions.json");
    await fs.writeFile(storePath, "[]", "utf-8");

    await updateSessionStore(storePath, (store) => {
      store["agent:main:main"] = { sessionId: "sess-1", updatedAt: Date.now() };
    });

    const store = loadSessionStore(storePath);
    (expect* store["agent:main:main"]?.sessionId).is("sess-1");

    const raw = await fs.readFile(storePath, "utf-8");
    (expect* raw.trim().startsWith("{")).is(true);
  });

  (deftest "normalizes last route fields on write", async () => {
    const dir = await createCaseDir("updateSessionStore");
    const storePath = path.join(dir, "sessions.json");
    await fs.writeFile(storePath, "{}", "utf-8");

    await updateSessionStore(storePath, (store) => {
      store["agent:main:main"] = {
        sessionId: "sess-normalized",
        updatedAt: Date.now(),
        lastChannel: " WhatsApp ",
        lastTo: " +1555 ",
        lastAccountId: " acct-1 ",
      };
    });

    const store = loadSessionStore(storePath);
    (expect* store["agent:main:main"]?.lastChannel).is("whatsapp");
    (expect* store["agent:main:main"]?.lastTo).is("+1555");
    (expect* store["agent:main:main"]?.lastAccountId).is("acct-1");
    (expect* store["agent:main:main"]?.deliveryContext).is-equal({
      channel: "whatsapp",
      to: "+1555",
      accountId: "acct-1",
    });
  });

  (deftest "updateSessionStore keeps deletions when concurrent writes happen", async () => {
    const dir = await createCaseDir("updateSessionStore");
    const storePath = path.join(dir, "sessions.json");
    await fs.writeFile(
      storePath,
      JSON.stringify(
        {
          "agent:main:old": { sessionId: "sess-old", updatedAt: Date.now() },
          "agent:main:keep": { sessionId: "sess-keep", updatedAt: Date.now() },
        },
        null,
        2,
      ),
      "utf-8",
    );

    await Promise.all([
      updateSessionStore(storePath, (store) => {
        delete store["agent:main:old"];
      }),
      updateSessionStore(storePath, (store) => {
        store["agent:main:new"] = { sessionId: "sess-new", updatedAt: Date.now() };
      }),
    ]);

    const store = loadSessionStore(storePath);
    (expect* store["agent:main:old"]).toBeUndefined();
    (expect* store["agent:main:keep"]?.sessionId).is("sess-keep");
    (expect* store["agent:main:new"]?.sessionId).is("sess-new");
  });

  (deftest "loadSessionStore auto-migrates legacy provider keys to channel keys", async () => {
    const mainSessionKey = "agent:main:main";
    const dir = await createCaseDir("loadSessionStore");
    const storePath = path.join(dir, "sessions.json");
    await fs.writeFile(
      storePath,
      JSON.stringify(
        {
          [mainSessionKey]: {
            sessionId: "sess-legacy",
            updatedAt: 123,
            provider: "slack",
            lastProvider: "telegram",
            lastTo: "user:U123",
          },
        },
        null,
        2,
      ),
      "utf-8",
    );

    const store = loadSessionStore(storePath) as unknown as Record<string, Record<string, unknown>>;
    const entry = store[mainSessionKey] ?? {};
    (expect* entry.channel).is("slack");
    (expect* entry.provider).toBeUndefined();
    (expect* entry.lastChannel).is("telegram");
    (expect* entry.lastProvider).toBeUndefined();
  });

  (deftest "derives session transcripts dir from OPENCLAW_STATE_DIR", () => {
    const dir = resolveSessionTranscriptsDir(
      { OPENCLAW_STATE_DIR: "/custom/state" } as NodeJS.ProcessEnv,
      () => "/home/ignored",
    );
    (expect* dir).is(path.join(path.resolve("/custom/state"), "agents", "main", "sessions"));
  });

  (deftest "includes topic ids in session transcript filenames", () => {
    withStateDir("/custom/state", () => {
      const sessionFile = resolveSessionTranscriptPath("sess-1", "main", 123);
      (expect* sessionFile).is(
        path.join(
          path.resolve("/custom/state"),
          "agents",
          "main",
          "sessions",
          "sess-1-topic-123.jsonl",
        ),
      );
    });
  });

  (deftest "uses agent id when resolving session file fallback paths", () => {
    withStateDir("/custom/state", () => {
      const sessionFile = resolveSessionFilePath("sess-2", undefined, {
        agentId: "codex",
      });
      (expect* sessionFile).is(
        path.join(path.resolve("/custom/state"), "agents", "codex", "sessions", "sess-2.jsonl"),
      );
    });
  });

  (deftest "resolves cross-agent absolute sessionFile paths", async () => {
    const { stateDir, bot2SessionPath } = await createAgentSessionsLayout("cross-agent");
    const sessionFile = withStateDir(stateDir, () =>
      // Agent bot1 resolves a sessionFile that belongs to agent bot2
      resolveSessionFilePath("sess-1", { sessionFile: bot2SessionPath }, { agentId: "bot1" }),
    );
    (expect* await normalizePathForComparison(sessionFile)).is(
      await normalizePathForComparison(bot2SessionPath),
    );
  });

  (deftest "resolves cross-agent paths when OPENCLAW_STATE_DIR differs from stored paths", () => {
    withStateDir(path.resolve("/different/state"), () => {
      const originalBase = path.resolve("/original/state");
      const bot2Session = path.join(originalBase, "agents", "bot2", "sessions", "sess-1.jsonl");
      // sessionFile was created under a different state dir than current env
      const sessionFile = resolveSessionFilePath(
        "sess-1",
        { sessionFile: bot2Session },
        { agentId: "bot1" },
      );
      (expect* sessionFile).is(bot2Session);
    });
  });

  (deftest "falls back when structural cross-root path traverses after sessions", () => {
    withStateDir(path.resolve("/different/state"), () => {
      const originalBase = path.resolve("/original/state");
      const unsafe = path.join(originalBase, "agents", "bot2", "sessions", "..", "..", "etc");
      const sessionFile = resolveSessionFilePath(
        "sess-1",
        { sessionFile: path.join(unsafe, "passwd") },
        { agentId: "bot1" },
      );
      (expect* sessionFile).is(expectedBot1FallbackSessionPath());
    });
  });

  (deftest "falls back when structural cross-root path nests under sessions", () => {
    withStateDir(path.resolve("/different/state"), () => {
      const originalBase = path.resolve("/original/state");
      const nested = path.join(
        originalBase,
        "agents",
        "bot2",
        "sessions",
        "nested",
        "sess-1.jsonl",
      );
      const sessionFile = resolveSessionFilePath(
        "sess-1",
        { sessionFile: nested },
        { agentId: "bot1" },
      );
      (expect* sessionFile).is(expectedBot1FallbackSessionPath());
    });
  });

  (deftest "resolveSessionFilePathOptions keeps explicit agentId alongside absolute store path", () => {
    const storePath = "/tmp/openclaw/agents/main/sessions/sessions.json";
    const resolved = resolveSessionFilePathOptions({
      agentId: "bot2",
      storePath,
    });
    (expect* resolved?.agentId).is("bot2");
    (expect* resolved?.sessionsDir).is(path.dirname(path.resolve(storePath)));
  });

  (deftest "resolves sibling agent absolute sessionFile using alternate agentId from options", async () => {
    const { stateDir, mainStorePath, bot2SessionPath } =
      await createAgentSessionsLayout("sibling-agent");
    const sessionFile = withStateDir(stateDir, () => {
      const opts = resolveSessionFilePathOptions({
        agentId: "bot2",
        storePath: mainStorePath,
      });

      return resolveSessionFilePath("sess-1", { sessionFile: bot2SessionPath }, opts);
    });
    (expect* await normalizePathForComparison(sessionFile)).is(
      await normalizePathForComparison(bot2SessionPath),
    );
  });

  (deftest "falls back to derived transcript path when sessionFile is outside agent sessions directories", async () => {
    const { stateDir, outsidePath } = await createAgentSessionsLayout("outside-fallback");
    const sessionFile = withStateDir(stateDir, () =>
      resolveSessionFilePath("sess-1", { sessionFile: outsidePath }, { agentId: "bot1" }),
    );
    const expectedPath = path.join(stateDir, "agents", "bot1", "sessions", "sess-1.jsonl");
    (expect* await normalizePathForComparison(sessionFile)).is(
      await normalizePathForComparison(expectedPath),
    );
  });

  (deftest "updateSessionStoreEntry merges concurrent patches", async () => {
    const mainSessionKey = "agent:main:main";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateSessionStoreEntry",
      entries: {
        [mainSessionKey]: {
          sessionId: "sess-1",
          updatedAt: 123,
          thinkingLevel: "low",
        },
      },
    });

    const createDeferred = <T>() => {
      let resolve!: (value: T | PromiseLike<T>) => void;
      let reject!: (reason?: unknown) => void;
      const promise = new deferred-result<T>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      return { promise, resolve, reject };
    };
    const firstStarted = createDeferred<void>();
    const releaseFirst = createDeferred<void>();

    const p1 = updateSessionStoreEntry({
      storePath,
      sessionKey: mainSessionKey,
      update: async () => {
        firstStarted.resolve();
        await releaseFirst.promise;
        return { modelOverride: "anthropic/claude-opus-4-5" };
      },
    });
    const p2 = updateSessionStoreEntry({
      storePath,
      sessionKey: mainSessionKey,
      update: async () => {
        await firstStarted.promise;
        return { thinkingLevel: "high" };
      },
    });

    await firstStarted.promise;
    releaseFirst.resolve();
    await Promise.all([p1, p2]);

    const store = loadSessionStore(storePath);
    (expect* store[mainSessionKey]?.modelOverride).is("anthropic/claude-opus-4-5");
    (expect* store[mainSessionKey]?.thinkingLevel).is("high");
    await (expect* fs.stat(`${storePath}.lock`)).rejects.signals-error();
  });

  (deftest "updateSessionStoreEntry re-reads disk inside lock instead of using stale cache", async () => {
    const mainSessionKey = "agent:main:main";
    const { storePath } = await createSessionStoreFixture({
      prefix: "updateSessionStoreEntry-cache-bypass",
      entries: {
        [mainSessionKey]: {
          sessionId: "sess-1",
          updatedAt: 123,
          thinkingLevel: "low",
        },
      },
    });

    // Prime the in-process cache with the original entry.
    (expect* loadSessionStore(storePath)[mainSessionKey]?.thinkingLevel).is("low");
    const originalStat = await fs.stat(storePath);

    // Simulate an external writer that updates the store but preserves mtime.
    const externalStore = JSON.parse(await fs.readFile(storePath, "utf-8")) as Record<
      string,
      Record<string, unknown>
    >;
    externalStore[mainSessionKey] = {
      ...externalStore[mainSessionKey],
      providerOverride: "anthropic",
      updatedAt: 124,
    };
    await fs.writeFile(storePath, JSON.stringify(externalStore), "utf-8");
    await fs.utimes(storePath, originalStat.atime, originalStat.mtime);

    await updateSessionStoreEntry({
      storePath,
      sessionKey: mainSessionKey,
      update: async () => ({ thinkingLevel: "high" }),
    });

    const store = loadSessionStore(storePath);
    (expect* store[mainSessionKey]?.providerOverride).is("anthropic");
    (expect* store[mainSessionKey]?.thinkingLevel).is("high");
  });
});
