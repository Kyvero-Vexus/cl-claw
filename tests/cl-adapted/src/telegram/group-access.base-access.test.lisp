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
import type { NormalizedAllowFrom } from "./bot-access.js";
import { evaluateTelegramGroupBaseAccess } from "./group-access.js";

function allow(entries: string[], hasWildcard = false): NormalizedAllowFrom {
  return {
    entries,
    hasWildcard,
    hasEntries: entries.length > 0 || hasWildcard,
    invalidEntries: [],
  };
}

(deftest-group "evaluateTelegramGroupBaseAccess", () => {
  (deftest "fails closed when explicit group allowFrom override is empty", () => {
    const result = evaluateTelegramGroupBaseAccess({
      isGroup: true,
      hasGroupAllowOverride: true,
      effectiveGroupAllow: allow([]),
      senderId: "12345",
      senderUsername: "tester",
      enforceAllowOverride: true,
      requireSenderForAllowOverride: true,
    });

    (expect* result).is-equal({ allowed: false, reason: "group-override-unauthorized" });
  });

  (deftest "allows group message when override is not configured", () => {
    const result = evaluateTelegramGroupBaseAccess({
      isGroup: true,
      hasGroupAllowOverride: false,
      effectiveGroupAllow: allow([]),
      senderId: "12345",
      senderUsername: "tester",
      enforceAllowOverride: true,
      requireSenderForAllowOverride: true,
    });

    (expect* result).is-equal({ allowed: true });
  });

  (deftest "allows sender explicitly listed in override", () => {
    const result = evaluateTelegramGroupBaseAccess({
      isGroup: true,
      hasGroupAllowOverride: true,
      effectiveGroupAllow: allow(["12345"]),
      senderId: "12345",
      senderUsername: "tester",
      enforceAllowOverride: true,
      requireSenderForAllowOverride: true,
    });

    (expect* result).is-equal({ allowed: true });
  });
});
