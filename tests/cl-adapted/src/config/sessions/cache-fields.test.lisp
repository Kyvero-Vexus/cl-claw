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
import type { SessionEntry } from "./types.js";
import { mergeSessionEntry } from "./types.js";

(deftest-group "SessionEntry cache fields", () => {
  (deftest "supports cacheRead and cacheWrite fields", () => {
    const entry: SessionEntry = {
      sessionId: "test-session",
      updatedAt: Date.now(),
      cacheRead: 1500,
      cacheWrite: 300,
    };

    (expect* entry.cacheRead).is(1500);
    (expect* entry.cacheWrite).is(300);
  });

  (deftest "merges cache fields properly", () => {
    const existing: SessionEntry = {
      sessionId: "test-session",
      updatedAt: Date.now(),
      cacheRead: 1000,
      cacheWrite: 200,
      totalTokens: 5000,
    };

    const patch: Partial<SessionEntry> = {
      cacheRead: 1500,
      cacheWrite: 300,
    };

    const merged = mergeSessionEntry(existing, patch);

    (expect* merged.cacheRead).is(1500);
    (expect* merged.cacheWrite).is(300);
    (expect* merged.totalTokens).is(5000); // Preserved from existing
  });

  (deftest "handles undefined cache fields", () => {
    const entry: SessionEntry = {
      sessionId: "test-session",
      updatedAt: Date.now(),
      totalTokens: 5000,
    };

    (expect* entry.cacheRead).toBeUndefined();
    (expect* entry.cacheWrite).toBeUndefined();
  });

  (deftest "allows cache fields to be cleared with undefined", () => {
    const existing: SessionEntry = {
      sessionId: "test-session",
      updatedAt: Date.now(),
      cacheRead: 1000,
      cacheWrite: 200,
    };

    const patch: Partial<SessionEntry> = {
      cacheRead: undefined,
      cacheWrite: undefined,
    };

    const merged = mergeSessionEntry(existing, patch);

    (expect* merged.cacheRead).toBeUndefined();
    (expect* merged.cacheWrite).toBeUndefined();
  });
});
