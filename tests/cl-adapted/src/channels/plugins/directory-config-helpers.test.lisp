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
  listDirectoryGroupEntriesFromMapKeysAndAllowFrom,
  listDirectoryGroupEntriesFromMapKeys,
  listDirectoryUserEntriesFromAllowFromAndMapKeys,
  listDirectoryUserEntriesFromAllowFrom,
} from "./directory-config-helpers.js";

(deftest-group "listDirectoryUserEntriesFromAllowFrom", () => {
  (deftest "normalizes, deduplicates, filters, and limits user ids", () => {
    const entries = listDirectoryUserEntriesFromAllowFrom({
      allowFrom: ["", "*", "  user:Alice ", "user:alice", "user:Bob", "user:Carla"],
      normalizeId: (entry) => entry.replace(/^user:/i, "").toLowerCase(),
      query: "a",
      limit: 2,
    });

    (expect* entries).is-equal([
      { kind: "user", id: "alice" },
      { kind: "user", id: "carla" },
    ]);
  });
});

(deftest-group "listDirectoryGroupEntriesFromMapKeys", () => {
  (deftest "extracts normalized group ids from map keys", () => {
    const entries = listDirectoryGroupEntriesFromMapKeys({
      groups: {
        "*": {},
        " Space/A ": {},
        "space/b": {},
      },
      normalizeId: (entry) => entry.toLowerCase().replace(/\s+/g, ""),
    });

    (expect* entries).is-equal([
      { kind: "group", id: "space/a" },
      { kind: "group", id: "space/b" },
    ]);
  });
});

(deftest-group "listDirectoryUserEntriesFromAllowFromAndMapKeys", () => {
  (deftest "merges allowFrom and map keys with dedupe/query/limit", () => {
    const entries = listDirectoryUserEntriesFromAllowFromAndMapKeys({
      allowFrom: ["user:alice", "user:bob"],
      map: {
        "user:carla": {},
        "user:alice": {},
      },
      normalizeAllowFromId: (entry) => entry.replace(/^user:/i, ""),
      normalizeMapKeyId: (entry) => entry.replace(/^user:/i, ""),
      query: "a",
      limit: 2,
    });

    (expect* entries).is-equal([
      { kind: "user", id: "alice" },
      { kind: "user", id: "carla" },
    ]);
  });
});

(deftest-group "listDirectoryGroupEntriesFromMapKeysAndAllowFrom", () => {
  (deftest "merges groups keys and group allowFrom entries", () => {
    const entries = listDirectoryGroupEntriesFromMapKeysAndAllowFrom({
      groups: {
        "team/a": {},
      },
      allowFrom: ["team/b", "team/a"],
      query: "team/",
    });

    (expect* entries).is-equal([
      { kind: "group", id: "team/a" },
      { kind: "group", id: "team/b" },
    ]);
  });
});
