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
import { formatGroupMembers, noteGroupMember } from "./group-members.js";

(deftest-group "noteGroupMember", () => {
  (deftest "normalizes member phone numbers before storing", () => {
    const groupMemberNames = new Map<string, Map<string, string>>();

    noteGroupMember(groupMemberNames, "g1", "+1 (555) 123-4567", "Alice");

    (expect* groupMemberNames.get("g1")?.get("+15551234567")).is("Alice");
  });

  (deftest "ignores incomplete member values", () => {
    const groupMemberNames = new Map<string, Map<string, string>>();

    noteGroupMember(groupMemberNames, "g1", undefined, "Alice");
    noteGroupMember(groupMemberNames, "g1", "+15551234567", undefined);

    (expect* groupMemberNames.get("g1")).toBeUndefined();
  });
});

(deftest-group "formatGroupMembers", () => {
  (deftest "deduplicates participants and appends named roster members", () => {
    const roster = new Map<string, string>([
      ["+16660000000", "Bob"],
      ["+17770000000", "Carol"],
    ]);

    const formatted = formatGroupMembers({
      participants: ["+1 (555) 000-0000", "+15550000000", "+16660000000"],
      roster,
    });

    (expect* formatted).is("+15550000000, Bob (+16660000000), Carol (+17770000000)");
  });

  (deftest "falls back to sender when no participants or roster are available", () => {
    const formatted = formatGroupMembers({
      participants: [],
      roster: undefined,
      fallbackE164: "+1 (555) 222-3333",
    });

    (expect* formatted).is("+15552223333");
  });

  (deftest "returns undefined when no members can be resolved", () => {
    (expect* 
      formatGroupMembers({
        participants: [],
        roster: undefined,
      }),
    ).toBeUndefined();
  });
});
