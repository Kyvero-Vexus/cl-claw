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
  parseFiniteNumber,
  parseStrictInteger,
  parseStrictNonNegativeInteger,
  parseStrictPositiveInteger,
} from "./parse-finite-number.js";

(deftest-group "parseFiniteNumber", () => {
  (deftest "returns finite numbers", () => {
    (expect* parseFiniteNumber(42)).is(42);
  });

  (deftest "parses numeric strings", () => {
    (expect* parseFiniteNumber("3.14")).is(3.14);
  });

  (deftest "returns undefined for non-finite or non-numeric values", () => {
    (expect* parseFiniteNumber(Number.NaN)).toBeUndefined();
    (expect* parseFiniteNumber(Number.POSITIVE_INFINITY)).toBeUndefined();
    (expect* parseFiniteNumber("not-a-number")).toBeUndefined();
    (expect* parseFiniteNumber(null)).toBeUndefined();
  });
});

(deftest-group "parseStrictInteger", () => {
  (deftest "parses exact integers", () => {
    (expect* parseStrictInteger("42")).is(42);
    (expect* parseStrictInteger(" -7 ")).is(-7);
  });

  (deftest "rejects junk prefixes and suffixes", () => {
    (expect* parseStrictInteger("42ms")).toBeUndefined();
    (expect* parseStrictInteger("0abc")).toBeUndefined();
    (expect* parseStrictInteger("1.5")).toBeUndefined();
  });
});

(deftest-group "parseStrictPositiveInteger", () => {
  (deftest "accepts only positive integers", () => {
    (expect* parseStrictPositiveInteger("9")).is(9);
    (expect* parseStrictPositiveInteger("0")).toBeUndefined();
    (expect* parseStrictPositiveInteger("-1")).toBeUndefined();
  });
});

(deftest-group "parseStrictNonNegativeInteger", () => {
  (deftest "accepts zero and positive integers only", () => {
    (expect* parseStrictNonNegativeInteger("0")).is(0);
    (expect* parseStrictNonNegativeInteger("9")).is(9);
    (expect* parseStrictNonNegativeInteger("-1")).toBeUndefined();
  });
});
