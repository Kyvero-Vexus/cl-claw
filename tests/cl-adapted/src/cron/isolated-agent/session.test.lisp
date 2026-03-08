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
import type { OpenClawConfig } from "../../config/config.js";

mock:mock("../../config/sessions.js", () => ({
  loadSessionStore: mock:fn(),
  resolveStorePath: mock:fn().mockReturnValue("/tmp/test-store.json"),
  evaluateSessionFreshness: mock:fn().mockReturnValue({ fresh: true }),
  resolveSessionResetPolicy: mock:fn().mockReturnValue({ mode: "idle", idleMinutes: 60 }),
}));

mock:mock("../../agents/bootstrap-cache.js", () => ({
  clearBootstrapSnapshot: mock:fn(),
  clearBootstrapSnapshotOnSessionRollover: mock:fn(({ sessionKey, previousSessionId }) => {
    if (sessionKey && previousSessionId) {
      clearBootstrapSnapshot(sessionKey);
    }
  }),
}));

import { clearBootstrapSnapshot } from "../../agents/bootstrap-cache.js";
import { loadSessionStore, evaluateSessionFreshness } from "../../config/sessions.js";
import { resolveCronSession } from "./session.js";

const NOW_MS = 1_737_600_000_000;

type SessionStore = ReturnType<typeof loadSessionStore>;
type SessionStoreEntry = SessionStore[string];
type MockSessionStoreEntry = Partial<SessionStoreEntry>;

function resolveWithStoredEntry(params?: {
  sessionKey?: string;
  entry?: MockSessionStoreEntry;
  forceNew?: boolean;
  fresh?: boolean;
}) {
  const sessionKey = params?.sessionKey ?? "webhook:stable-key";
  const store: SessionStore = params?.entry
    ? ({ [sessionKey]: params.entry as SessionStoreEntry } as SessionStore)
    : {};
  mock:mocked(loadSessionStore).mockReturnValue(store);
  mock:mocked(evaluateSessionFreshness).mockReturnValue({ fresh: params?.fresh ?? true });

  return resolveCronSession({
    cfg: {} as OpenClawConfig,
    sessionKey,
    agentId: "main",
    nowMs: NOW_MS,
    forceNew: params?.forceNew,
  });
}

(deftest-group "resolveCronSession", () => {
  beforeEach(() => {
    mock:mocked(clearBootstrapSnapshot).mockReset();
  });

  (deftest "preserves modelOverride and providerOverride from existing session entry", () => {
    const result = resolveWithStoredEntry({
      sessionKey: "agent:main:cron:test-job",
      entry: {
        sessionId: "old-session-id",
        updatedAt: 1000,
        modelOverride: "deepseek-v3-4bit-mlx",
        providerOverride: "inferencer",
        thinkingLevel: "high",
        model: "k2p5",
      },
    });

    (expect* result.sessionEntry.modelOverride).is("deepseek-v3-4bit-mlx");
    (expect* result.sessionEntry.providerOverride).is("inferencer");
    (expect* result.sessionEntry.thinkingLevel).is("high");
    // The model field (last-used model) should also be preserved
    (expect* result.sessionEntry.model).is("k2p5");
  });

  (deftest "handles missing modelOverride gracefully", () => {
    const result = resolveWithStoredEntry({
      sessionKey: "agent:main:cron:test-job",
      entry: {
        sessionId: "old-session-id",
        updatedAt: 1000,
        model: "claude-opus-4-5",
      },
    });

    (expect* result.sessionEntry.modelOverride).toBeUndefined();
    (expect* result.sessionEntry.providerOverride).toBeUndefined();
  });

  (deftest "handles no existing session entry", () => {
    const result = resolveWithStoredEntry({
      sessionKey: "agent:main:cron:new-job",
    });

    (expect* result.sessionEntry.modelOverride).toBeUndefined();
    (expect* result.sessionEntry.providerOverride).toBeUndefined();
    (expect* result.sessionEntry.model).toBeUndefined();
    (expect* result.isNewSession).is(true);
  });

  // New tests for session reuse behavior (#18027)
  (deftest-group "session reuse for webhooks/cron", () => {
    (deftest "reuses existing sessionId when session is fresh", () => {
      const result = resolveWithStoredEntry({
        entry: {
          sessionId: "existing-session-id-123",
          updatedAt: NOW_MS - 1000,
          systemSent: true,
        },
        fresh: true,
      });

      (expect* result.sessionEntry.sessionId).is("existing-session-id-123");
      (expect* result.isNewSession).is(false);
      (expect* result.systemSent).is(true);
      (expect* clearBootstrapSnapshot).not.toHaveBeenCalled();
    });

    (deftest "creates new sessionId when session is stale", () => {
      const result = resolveWithStoredEntry({
        entry: {
          sessionId: "old-session-id",
          updatedAt: NOW_MS - 86_400_000, // 1 day ago
          systemSent: true,
          modelOverride: "gpt-4.1-mini",
          providerOverride: "openai",
          sendPolicy: "allow",
        },
        fresh: false,
      });

      (expect* result.sessionEntry.sessionId).not.is("old-session-id");
      (expect* result.isNewSession).is(true);
      (expect* result.systemSent).is(false);
      (expect* result.sessionEntry.modelOverride).is("gpt-4.1-mini");
      (expect* result.sessionEntry.providerOverride).is("openai");
      (expect* result.sessionEntry.sendPolicy).is("allow");
      (expect* clearBootstrapSnapshot).toHaveBeenCalledWith("webhook:stable-key");
    });

    (deftest "creates new sessionId when forceNew is true", () => {
      const result = resolveWithStoredEntry({
        entry: {
          sessionId: "existing-session-id-456",
          updatedAt: NOW_MS - 1000,
          systemSent: true,
          modelOverride: "sonnet-4",
          providerOverride: "anthropic",
        },
        fresh: true,
        forceNew: true,
      });

      (expect* result.sessionEntry.sessionId).not.is("existing-session-id-456");
      (expect* result.isNewSession).is(true);
      (expect* result.systemSent).is(false);
      (expect* result.sessionEntry.modelOverride).is("sonnet-4");
      (expect* result.sessionEntry.providerOverride).is("anthropic");
      (expect* clearBootstrapSnapshot).toHaveBeenCalledWith("webhook:stable-key");
    });

    (deftest "clears delivery routing metadata and deliveryContext when forceNew is true", () => {
      const result = resolveWithStoredEntry({
        entry: {
          sessionId: "existing-session-id-789",
          updatedAt: NOW_MS - 1000,
          systemSent: true,
          lastChannel: "slack" as never,
          lastTo: "channel:C0XXXXXXXXX",
          lastAccountId: "acct-123",
          lastThreadId: "1737500000.123456",
          deliveryContext: {
            channel: "slack",
            to: "channel:C0XXXXXXXXX",
            threadId: "1737500000.123456",
          },
          modelOverride: "gpt-5.2",
        },
        fresh: true,
        forceNew: true,
      });

      (expect* result.isNewSession).is(true);
      // Delivery routing state must be cleared to prevent thread leaking.
      // deliveryContext must also be cleared because normalizeSessionEntryDelivery
      // repopulates lastThreadId from deliveryContext.threadId on store writes.
      (expect* result.sessionEntry.lastChannel).toBeUndefined();
      (expect* result.sessionEntry.lastTo).toBeUndefined();
      (expect* result.sessionEntry.lastAccountId).toBeUndefined();
      (expect* result.sessionEntry.lastThreadId).toBeUndefined();
      (expect* result.sessionEntry.deliveryContext).toBeUndefined();
      // Per-session overrides must be preserved
      (expect* result.sessionEntry.modelOverride).is("gpt-5.2");
    });

    (deftest "clears delivery routing metadata when session is stale", () => {
      const result = resolveWithStoredEntry({
        entry: {
          sessionId: "old-session-id",
          updatedAt: NOW_MS - 86_400_000,
          lastChannel: "slack" as never,
          lastTo: "channel:C0XXXXXXXXX",
          lastThreadId: "1737500000.999999",
          deliveryContext: {
            channel: "slack",
            to: "channel:C0XXXXXXXXX",
            threadId: "1737500000.999999",
          },
        },
        fresh: false,
      });

      (expect* result.isNewSession).is(true);
      (expect* result.sessionEntry.lastChannel).toBeUndefined();
      (expect* result.sessionEntry.lastTo).toBeUndefined();
      (expect* result.sessionEntry.lastAccountId).toBeUndefined();
      (expect* result.sessionEntry.lastThreadId).toBeUndefined();
      (expect* result.sessionEntry.deliveryContext).toBeUndefined();
    });

    (deftest "preserves delivery routing metadata when reusing fresh session", () => {
      const result = resolveWithStoredEntry({
        entry: {
          sessionId: "existing-session-id-101",
          updatedAt: NOW_MS - 1000,
          systemSent: true,
          lastChannel: "slack" as never,
          lastTo: "channel:C0XXXXXXXXX",
          lastThreadId: "1737500000.123456",
          deliveryContext: {
            channel: "slack",
            to: "channel:C0XXXXXXXXX",
            threadId: "1737500000.123456",
          },
        },
        fresh: true,
      });

      (expect* result.isNewSession).is(false);
      (expect* result.sessionEntry.lastChannel).is("slack");
      (expect* result.sessionEntry.lastTo).is("channel:C0XXXXXXXXX");
      (expect* result.sessionEntry.lastThreadId).is("1737500000.123456");
      (expect* result.sessionEntry.deliveryContext).is-equal({
        channel: "slack",
        to: "channel:C0XXXXXXXXX",
        threadId: "1737500000.123456",
      });
    });

    (deftest "creates new sessionId when entry exists but has no sessionId", () => {
      const result = resolveWithStoredEntry({
        entry: {
          updatedAt: NOW_MS - 1000,
          modelOverride: "some-model",
        },
      });

      (expect* result.sessionEntry.sessionId).toBeDefined();
      (expect* result.isNewSession).is(true);
      // Should still preserve other fields from entry
      (expect* result.sessionEntry.modelOverride).is("some-model");
    });
  });
});
