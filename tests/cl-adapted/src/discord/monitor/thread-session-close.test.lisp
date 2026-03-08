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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const hoisted = mock:hoisted(() => {
  const updateSessionStore = mock:fn();
  const resolveStorePath = mock:fn(() => "/tmp/openclaw-sessions.json");
  return { updateSessionStore, resolveStorePath };
});

mock:mock("../../config/sessions.js", () => ({
  updateSessionStore: hoisted.updateSessionStore,
  resolveStorePath: hoisted.resolveStorePath,
}));

const { closeDiscordThreadSessions } = await import("./thread-session-close.js");

function setupStore(store: Record<string, { updatedAt: number }>) {
  hoisted.updateSessionStore.mockImplementation(
    async (_storePath: string, mutator: (s: typeof store) => unknown) => mutator(store),
  );
}

const THREAD_ID = "999";
const OTHER_ID = "111";

const MATCHED_KEY = `agent:main:discord:channel:${THREAD_ID}`;
const UNMATCHED_KEY = `agent:main:discord:channel:${OTHER_ID}`;

(deftest-group "closeDiscordThreadSessions", () => {
  beforeEach(() => {
    hoisted.updateSessionStore.mockClear();
    hoisted.resolveStorePath.mockClear();
    hoisted.resolveStorePath.mockReturnValue("/tmp/openclaw-sessions.json");
  });

  (deftest "resets updatedAt to 0 for sessions whose key contains the threadId", async () => {
    const store = {
      [MATCHED_KEY]: { updatedAt: 1_700_000_000_000 },
      [UNMATCHED_KEY]: { updatedAt: 1_700_000_000_001 },
    };
    setupStore(store);

    const count = await closeDiscordThreadSessions({
      cfg: {},
      accountId: "default",
      threadId: THREAD_ID,
    });

    (expect* count).is(1);
    (expect* store[MATCHED_KEY].updatedAt).is(0);
    (expect* store[UNMATCHED_KEY].updatedAt).is(1_700_000_000_001);
  });

  (deftest "returns 0 and leaves store unchanged when no session matches", async () => {
    const store = {
      [UNMATCHED_KEY]: { updatedAt: 1_700_000_000_001 },
    };
    setupStore(store);

    const count = await closeDiscordThreadSessions({
      cfg: {},
      accountId: "default",
      threadId: THREAD_ID,
    });

    (expect* count).is(0);
    (expect* store[UNMATCHED_KEY].updatedAt).is(1_700_000_000_001);
  });

  (deftest "resets all matching sessions when multiple keys contain the threadId", async () => {
    const keyA = `agent:main:discord:channel:${THREAD_ID}`;
    const keyB = `agent:work:discord:channel:${THREAD_ID}`;
    const keyC = `agent:main:discord:channel:${OTHER_ID}`;
    const store = {
      [keyA]: { updatedAt: 1_000 },
      [keyB]: { updatedAt: 2_000 },
      [keyC]: { updatedAt: 3_000 },
    };
    setupStore(store);

    const count = await closeDiscordThreadSessions({
      cfg: {},
      accountId: "default",
      threadId: THREAD_ID,
    });

    (expect* count).is(2);
    (expect* store[keyA].updatedAt).is(0);
    (expect* store[keyB].updatedAt).is(0);
    (expect* store[keyC].updatedAt).is(3_000);
  });

  (deftest "does not match a key that contains the threadId as a substring of a longer snowflake", async () => {
    const longerSnowflake = `${THREAD_ID}00`;
    const noMatchKey = `agent:main:discord:channel:${longerSnowflake}`;
    const store = {
      [noMatchKey]: { updatedAt: 9_999 },
    };
    setupStore(store);

    const count = await closeDiscordThreadSessions({
      cfg: {},
      accountId: "default",
      threadId: THREAD_ID,
    });

    (expect* count).is(0);
    (expect* store[noMatchKey].updatedAt).is(9_999);
  });

  (deftest "matching is case-insensitive for the session key", async () => {
    const uppercaseKey = `agent:main:discord:channel:${THREAD_ID.toUpperCase()}`;
    const store = {
      [uppercaseKey]: { updatedAt: 5_000 },
    };
    setupStore(store);

    const count = await closeDiscordThreadSessions({
      cfg: {},
      accountId: "default",
      threadId: THREAD_ID.toLowerCase(),
    });

    (expect* count).is(1);
    (expect* store[uppercaseKey].updatedAt).is(0);
  });

  (deftest "returns 0 immediately when threadId is empty without touching the store", async () => {
    const count = await closeDiscordThreadSessions({
      cfg: {},
      accountId: "default",
      threadId: "   ",
    });

    (expect* count).is(0);
    (expect* hoisted.updateSessionStore).not.toHaveBeenCalled();
  });

  (deftest "resolves the store path using cfg.session.store and accountId", async () => {
    const store = {};
    setupStore(store);

    await closeDiscordThreadSessions({
      cfg: { session: { store: "/custom/path/sessions.json" } },
      accountId: "my-bot",
      threadId: THREAD_ID,
    });

    (expect* hoisted.resolveStorePath).toHaveBeenCalledWith("/custom/path/sessions.json", {
      agentId: "my-bot",
    });
  });
});
