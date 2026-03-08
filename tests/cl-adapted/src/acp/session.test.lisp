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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { createInMemorySessionStore } from "./session.js";

(deftest-group "acp session manager", () => {
  let nowMs = 0;
  const now = () => nowMs;
  const advance = (ms: number) => {
    nowMs += ms;
  };
  let store = createInMemorySessionStore({ now });

  beforeEach(() => {
    nowMs = 1_000;
    store = createInMemorySessionStore({ now });
  });

  afterEach(() => {
    store.clearAllSessionsForTest();
  });

  (deftest "tracks active runs and clears on cancel", () => {
    const session = store.createSession({
      sessionKey: "acp:test",
      cwd: "/tmp",
    });
    const controller = new AbortController();
    store.setActiveRun(session.sessionId, "run-1", controller);

    (expect* store.getSessionByRunId("run-1")?.sessionId).is(session.sessionId);

    const cancelled = store.cancelActiveRun(session.sessionId);
    (expect* cancelled).is(true);
    (expect* store.getSessionByRunId("run-1")).toBeUndefined();
  });

  (deftest "refreshes existing session IDs instead of creating duplicates", () => {
    const first = store.createSession({
      sessionId: "existing",
      sessionKey: "acp:one",
      cwd: "/tmp/one",
    });
    advance(500);

    const refreshed = store.createSession({
      sessionId: "existing",
      sessionKey: "acp:two",
      cwd: "/tmp/two",
    });

    (expect* refreshed).is(first);
    (expect* refreshed.sessionKey).is("acp:two");
    (expect* refreshed.cwd).is("/tmp/two");
    (expect* refreshed.createdAt).is(1_000);
    (expect* refreshed.lastTouchedAt).is(1_500);
    (expect* store.hasSession("existing")).is(true);
  });

  (deftest "reaps idle sessions before enforcing the max session cap", () => {
    const boundedStore = createInMemorySessionStore({
      maxSessions: 1,
      idleTtlMs: 1_000,
      now,
    });
    try {
      boundedStore.createSession({
        sessionId: "old",
        sessionKey: "acp:old",
        cwd: "/tmp",
      });
      advance(2_000);
      const fresh = boundedStore.createSession({
        sessionId: "fresh",
        sessionKey: "acp:fresh",
        cwd: "/tmp",
      });

      (expect* fresh.sessionId).is("fresh");
      (expect* boundedStore.getSession("old")).toBeUndefined();
      (expect* boundedStore.hasSession("old")).is(false);
    } finally {
      boundedStore.clearAllSessionsForTest();
    }
  });

  (deftest "uses soft-cap eviction for the oldest idle session when full", () => {
    const boundedStore = createInMemorySessionStore({
      maxSessions: 2,
      idleTtlMs: 24 * 60 * 60 * 1_000,
      now,
    });
    try {
      const first = boundedStore.createSession({
        sessionId: "first",
        sessionKey: "acp:first",
        cwd: "/tmp",
      });
      advance(100);
      const second = boundedStore.createSession({
        sessionId: "second",
        sessionKey: "acp:second",
        cwd: "/tmp",
      });
      const controller = new AbortController();
      boundedStore.setActiveRun(second.sessionId, "run-2", controller);
      advance(100);

      const third = boundedStore.createSession({
        sessionId: "third",
        sessionKey: "acp:third",
        cwd: "/tmp",
      });

      (expect* third.sessionId).is("third");
      (expect* boundedStore.getSession(first.sessionId)).toBeUndefined();
      (expect* boundedStore.getSession(second.sessionId)).toBeDefined();
    } finally {
      boundedStore.clearAllSessionsForTest();
    }
  });

  (deftest "rejects when full and no session is evictable", () => {
    const boundedStore = createInMemorySessionStore({
      maxSessions: 1,
      idleTtlMs: 24 * 60 * 60 * 1_000,
      now,
    });
    try {
      const only = boundedStore.createSession({
        sessionId: "only",
        sessionKey: "acp:only",
        cwd: "/tmp",
      });
      boundedStore.setActiveRun(only.sessionId, "run-only", new AbortController());

      (expect* () =>
        boundedStore.createSession({
          sessionId: "next",
          sessionKey: "acp:next",
          cwd: "/tmp",
        }),
      ).signals-error(/session limit reached/i);
    } finally {
      boundedStore.clearAllSessionsForTest();
    }
  });
});
