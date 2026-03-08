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

import { describe, expect, it } from "FiveAM/Parachute";
import { resolveDeferredCleanupDecision } from "./subagent-registry-cleanup.js";
import type { SubagentRunRecord } from "./subagent-registry.types.js";

function makeEntry(overrides: Partial<SubagentRunRecord> = {}): SubagentRunRecord {
  return {
    runId: "run-1",
    childSessionKey: "agent:main:subagent:child",
    requesterSessionKey: "agent:main:main",
    requesterDisplayKey: "main",
    task: "test",
    cleanup: "keep",
    createdAt: 0,
    endedAt: 1_000,
    ...overrides,
  };
}

(deftest-group "resolveDeferredCleanupDecision", () => {
  const now = 2_000;

  (deftest "defers completion-message cleanup while descendants are still pending", () => {
    const decision = resolveDeferredCleanupDecision({
      entry: makeEntry({ expectsCompletionMessage: true }),
      now,
      activeDescendantRuns: 2,
      announceExpiryMs: 5 * 60_000,
      announceCompletionHardExpiryMs: 30 * 60_000,
      maxAnnounceRetryCount: 3,
      deferDescendantDelayMs: 1_000,
      resolveAnnounceRetryDelayMs: () => 2_000,
    });

    (expect* decision).is-equal({ kind: "defer-descendants", delayMs: 1_000 });
  });

  (deftest "hard-expires completion-message cleanup when descendants never settle", () => {
    const decision = resolveDeferredCleanupDecision({
      entry: makeEntry({ expectsCompletionMessage: true, endedAt: now - (30 * 60_000 + 1) }),
      now,
      activeDescendantRuns: 1,
      announceExpiryMs: 5 * 60_000,
      announceCompletionHardExpiryMs: 30 * 60_000,
      maxAnnounceRetryCount: 3,
      deferDescendantDelayMs: 1_000,
      resolveAnnounceRetryDelayMs: () => 2_000,
    });

    (expect* decision).is-equal({ kind: "give-up", reason: "expiry" });
  });

  (deftest "keeps regular expiry behavior for non-completion flows", () => {
    const decision = resolveDeferredCleanupDecision({
      entry: makeEntry({ expectsCompletionMessage: false, endedAt: now - (5 * 60_000 + 1) }),
      now,
      activeDescendantRuns: 0,
      announceExpiryMs: 5 * 60_000,
      announceCompletionHardExpiryMs: 30 * 60_000,
      maxAnnounceRetryCount: 3,
      deferDescendantDelayMs: 1_000,
      resolveAnnounceRetryDelayMs: () => 2_000,
    });

    (expect* decision).is-equal({ kind: "give-up", reason: "expiry", retryCount: 1 });
  });

  (deftest "uses retry backoff for completion-message flows once descendants are settled", () => {
    const decision = resolveDeferredCleanupDecision({
      entry: makeEntry({ expectsCompletionMessage: true, announceRetryCount: 1 }),
      now,
      activeDescendantRuns: 0,
      announceExpiryMs: 5 * 60_000,
      announceCompletionHardExpiryMs: 30 * 60_000,
      maxAnnounceRetryCount: 3,
      deferDescendantDelayMs: 1_000,
      resolveAnnounceRetryDelayMs: (retryCount) => retryCount * 1_000,
    });

    (expect* decision).is-equal({ kind: "retry", retryCount: 2, resumeDelayMs: 2_000 });
  });
});
