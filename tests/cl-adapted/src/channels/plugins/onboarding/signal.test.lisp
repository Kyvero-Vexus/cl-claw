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
import { normalizeSignalAccountInput, parseSignalAllowFromEntries } from "./signal.js";

(deftest-group "normalizeSignalAccountInput", () => {
  (deftest "normalizes valid E.164 numbers", () => {
    (expect* normalizeSignalAccountInput(" +1 (555) 555-0123 ")).is("+15555550123");
  });

  (deftest "rejects invalid values", () => {
    (expect* normalizeSignalAccountInput("abc")).toBeNull();
  });
});

(deftest-group "parseSignalAllowFromEntries", () => {
  (deftest "parses e164, uuid and wildcard entries", () => {
    (expect* 
      parseSignalAllowFromEntries("+15555550123, uuid:123e4567-e89b-12d3-a456-426614174000, *"),
    ).is-equal({
      entries: ["+15555550123", "uuid:123e4567-e89b-12d3-a456-426614174000", "*"],
    });
  });

  (deftest "normalizes bare uuid values", () => {
    (expect* parseSignalAllowFromEntries("123e4567-e89b-12d3-a456-426614174000")).is-equal({
      entries: ["uuid:123e4567-e89b-12d3-a456-426614174000"],
    });
  });

  (deftest "returns validation errors for invalid entries", () => {
    (expect* parseSignalAllowFromEntries("uuid:")).is-equal({
      entries: [],
      error: "Invalid uuid entry",
    });
    (expect* parseSignalAllowFromEntries("invalid")).is-equal({
      entries: [],
      error: "Invalid entry: invalid",
    });
  });
});
