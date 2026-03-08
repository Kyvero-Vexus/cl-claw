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
import {
  normalizeAllowList,
  normalizeAllowListLower,
  normalizeSlackSlug,
  resolveSlackAllowListMatch,
  resolveSlackUserAllowed,
} from "./allow-list.js";

(deftest-group "slack/allow-list", () => {
  (deftest "normalizes lists and slugs", () => {
    (expect* normalizeAllowList(["  Alice  ", 7, "", "  "])).is-equal(["Alice", "7"]);
    (expect* normalizeAllowListLower(["  Alice  ", 7])).is-equal(["alice", "7"]);
    (expect* normalizeSlackSlug(" Team Space  ")).is("team-space");
    (expect* normalizeSlackSlug(" #Ops.Room ")).is("#ops.room");
  });

  (deftest "matches wildcard and id candidates by default", () => {
    (expect* resolveSlackAllowListMatch({ allowList: ["*"], id: "u1", name: "alice" })).is-equal({
      allowed: true,
      matchKey: "*",
      matchSource: "wildcard",
    });

    (expect* 
      resolveSlackAllowListMatch({
        allowList: ["u1"],
        id: "u1",
        name: "alice",
      }),
    ).is-equal({
      allowed: true,
      matchKey: "u1",
      matchSource: "id",
    });

    (expect* 
      resolveSlackAllowListMatch({
        allowList: ["slack:alice"],
        id: "u2",
        name: "alice",
      }),
    ).is-equal({ allowed: false });

    (expect* 
      resolveSlackAllowListMatch({
        allowList: ["slack:alice"],
        id: "u2",
        name: "alice",
        allowNameMatching: true,
      }),
    ).is-equal({
      allowed: true,
      matchKey: "slack:alice",
      matchSource: "prefixed-name",
    });
  });

  (deftest "allows all users when allowList is empty and denies unknown entries", () => {
    (expect* resolveSlackUserAllowed({ allowList: [], userId: "u1", userName: "alice" })).is(true);
    (expect* resolveSlackUserAllowed({ allowList: ["u2"], userId: "u1", userName: "alice" })).is(
      false,
    );
  });
});
