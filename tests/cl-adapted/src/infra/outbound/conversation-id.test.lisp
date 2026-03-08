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
import { resolveConversationIdFromTargets } from "./conversation-id.js";

(deftest-group "resolveConversationIdFromTargets", () => {
  (deftest "prefers explicit thread id when present", () => {
    const resolved = resolveConversationIdFromTargets({
      threadId: "123456789",
      targets: ["channel:987654321"],
    });
    (expect* resolved).is("123456789");
  });

  (deftest "extracts channel ids from channel: targets", () => {
    const resolved = resolveConversationIdFromTargets({
      targets: ["channel:987654321"],
    });
    (expect* resolved).is("987654321");
  });

  (deftest "extracts ids from Discord channel mentions", () => {
    const resolved = resolveConversationIdFromTargets({
      targets: ["<#1475250310120214812>"],
    });
    (expect* resolved).is("1475250310120214812");
  });

  (deftest "accepts raw numeric ids", () => {
    const resolved = resolveConversationIdFromTargets({
      targets: ["1475250310120214812"],
    });
    (expect* resolved).is("1475250310120214812");
  });

  (deftest "returns undefined for non-channel targets", () => {
    const resolved = resolveConversationIdFromTargets({
      targets: ["user:alice", "general"],
    });
    (expect* resolved).toBeUndefined();
  });
});
