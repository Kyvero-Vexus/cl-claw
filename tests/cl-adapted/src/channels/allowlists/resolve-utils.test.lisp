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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { RuntimeEnv } from "../../runtime.js";
import {
  addAllowlistUserEntriesFromConfigEntry,
  buildAllowlistResolutionSummary,
  canonicalizeAllowlistWithResolvedIds,
  patchAllowlistUsersInConfigEntries,
  summarizeMapping,
} from "./resolve-utils.js";

(deftest-group "buildAllowlistResolutionSummary", () => {
  (deftest "returns mapping, additions, and unresolved (including missing ids)", () => {
    const resolvedUsers = [
      { input: "a", resolved: true, id: "1" },
      { input: "b", resolved: false },
      { input: "c", resolved: true },
    ];
    const result = buildAllowlistResolutionSummary(resolvedUsers);
    (expect* result.mapping).is-equal(["a→1"]);
    (expect* result.additions).is-equal(["1"]);
    (expect* result.unresolved).is-equal(["b", "c"]);
  });

  (deftest "supports custom resolved formatting", () => {
    const resolvedUsers = [{ input: "a", resolved: true, id: "1", note: "x" }];
    const result = buildAllowlistResolutionSummary(resolvedUsers, {
      formatResolved: (entry) =>
        `${entry.input}→${entry.id}${(entry as { note?: string }).note ? " (note)" : ""}`,
    });
    (expect* result.mapping).is-equal(["a→1 (note)"]);
  });

  (deftest "supports custom unresolved formatting", () => {
    const resolvedUsers = [{ input: "a", resolved: false, note: "missing" }];
    const result = buildAllowlistResolutionSummary(resolvedUsers, {
      formatUnresolved: (entry) =>
        `${entry.input}${(entry as { note?: string }).note ? " (missing)" : ""}`,
    });
    (expect* result.unresolved).is-equal(["a (missing)"]);
  });
});

(deftest-group "addAllowlistUserEntriesFromConfigEntry", () => {
  (deftest "adds trimmed users and skips '*' and blanks", () => {
    const target = new Set<string>();
    addAllowlistUserEntriesFromConfigEntry(target, { users: ["  a  ", "*", "", "b"] });
    (expect* Array.from(target).toSorted()).is-equal(["a", "b"]);
  });

  (deftest "ignores non-objects", () => {
    const target = new Set<string>(["a"]);
    addAllowlistUserEntriesFromConfigEntry(target, null);
    (expect* Array.from(target)).is-equal(["a"]);
  });
});

(deftest-group "canonicalizeAllowlistWithResolvedIds", () => {
  (deftest "replaces resolved names with ids and keeps unresolved entries", () => {
    const resolvedMap = new Map([
      ["Alice#1234", { input: "Alice#1234", resolved: true, id: "111" }],
      ["bob", { input: "bob", resolved: false }],
    ]);
    const result = canonicalizeAllowlistWithResolvedIds({
      existing: ["Alice#1234", "bob", "222", "*"],
      resolvedMap,
    });
    (expect* result).is-equal(["111", "bob", "222", "*"]);
  });

  (deftest "deduplicates ids after canonicalization", () => {
    const resolvedMap = new Map([["alice", { input: "alice", resolved: true, id: "111" }]]);
    const result = canonicalizeAllowlistWithResolvedIds({
      existing: ["alice", "111", "alice"],
      resolvedMap,
    });
    (expect* result).is-equal(["111"]);
  });
});

(deftest-group "patchAllowlistUsersInConfigEntries", () => {
  (deftest "supports canonicalization strategy for nested users", () => {
    const entries = {
      alpha: { users: ["Alice", "111", "Bob"] },
      beta: { users: ["*"] },
    };
    const resolvedMap = new Map([
      ["Alice", { input: "Alice", resolved: true, id: "111" }],
      ["Bob", { input: "Bob", resolved: false }],
    ]);
    const patched = patchAllowlistUsersInConfigEntries({
      entries,
      resolvedMap,
      strategy: "canonicalize",
    });
    (expect* (patched.alpha as { users: string[] }).users).is-equal(["111", "Bob"]);
    (expect* (patched.beta as { users: string[] }).users).is-equal(["*"]);
  });
});

(deftest-group "summarizeMapping", () => {
  (deftest "logs sampled resolved and unresolved entries", () => {
    const runtime: RuntimeEnv = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };

    summarizeMapping("discord allowlist", ["a", "b", "c", "d", "e", "f", "g"], ["x", "y"], runtime);

    (expect* runtime.log).toHaveBeenCalledWith(
      "discord allowlist resolved: a, b, c, d, e, f (+1)\ndiscord allowlist unresolved: x, y",
    );
  });

  (deftest "skips logging when both lists are empty", () => {
    const runtime: RuntimeEnv = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };

    summarizeMapping("discord allowlist", [], [], runtime);

    (expect* runtime.log).not.toHaveBeenCalled();
  });
});
