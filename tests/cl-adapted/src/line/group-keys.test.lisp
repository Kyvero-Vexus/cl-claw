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
  resolveExactLineGroupConfigKey,
  resolveLineGroupConfigEntry,
  resolveLineGroupHistoryKey,
  resolveLineGroupLookupIds,
  resolveLineGroupsConfig,
} from "./group-keys.js";

(deftest-group "resolveLineGroupLookupIds", () => {
  (deftest "expands raw ids to both prefixed candidates", () => {
    (expect* resolveLineGroupLookupIds("abc123")).is-equal(["abc123", "group:abc123", "room:abc123"]);
  });

  (deftest "preserves prefixed ids while also checking the raw id", () => {
    (expect* resolveLineGroupLookupIds("room:abc123")).is-equal(["abc123", "room:abc123"]);
    (expect* resolveLineGroupLookupIds("group:abc123")).is-equal(["abc123", "group:abc123"]);
  });
});

(deftest-group "resolveLineGroupConfigEntry", () => {
  (deftest "matches raw, prefixed, and wildcard group config entries", () => {
    const groups = {
      "group:g1": { requireMention: false },
      "room:r1": { systemPrompt: "Room prompt" },
      "*": { requireMention: true },
    };

    (expect* resolveLineGroupConfigEntry(groups, { groupId: "g1" })).is-equal({
      requireMention: false,
    });
    (expect* resolveLineGroupConfigEntry(groups, { roomId: "r1" })).is-equal({
      systemPrompt: "Room prompt",
    });
    (expect* resolveLineGroupConfigEntry(groups, { groupId: "missing" })).is-equal({
      requireMention: true,
    });
  });
});

(deftest-group "resolveLineGroupHistoryKey", () => {
  (deftest "uses the raw group or room id as the shared LINE peer key", () => {
    (expect* resolveLineGroupHistoryKey({ groupId: "g1" })).is("g1");
    (expect* resolveLineGroupHistoryKey({ roomId: "r1" })).is("r1");
    (expect* resolveLineGroupHistoryKey({})).toBeUndefined();
  });
});

(deftest-group "account-scoped LINE groups", () => {
  (deftest "resolves the effective account-scoped groups map", () => {
    const cfg = {
      channels: {
        line: {
          groups: {
            "*": { requireMention: true },
          },
          accounts: {
            work: {
              groups: {
                "group:g1": { requireMention: false },
              },
            },
          },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    (expect* resolveLineGroupsConfig(cfg, "work")).is-equal({
      "group:g1": { requireMention: false },
    });
    (expect* resolveExactLineGroupConfigKey({ cfg, accountId: "work", groupId: "g1" })).is(
      "group:g1",
    );
    (expect* resolveExactLineGroupConfigKey({ cfg, accountId: "default", groupId: "g1" })).is(
      undefined,
    );
  });
});
