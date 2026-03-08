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
import { resolveCacheTtlMs } from "./cache-utils.js";

(deftest-group "resolveCacheTtlMs", () => {
  (deftest "accepts exact non-negative integers", () => {
    (expect* resolveCacheTtlMs({ envValue: "0", defaultTtlMs: 60_000 })).is(0);
    (expect* resolveCacheTtlMs({ envValue: "120000", defaultTtlMs: 60_000 })).is(120_000);
  });

  (deftest "rejects malformed env values and falls back to the default", () => {
    (expect* resolveCacheTtlMs({ envValue: "0abc", defaultTtlMs: 60_000 })).is(60_000);
    (expect* resolveCacheTtlMs({ envValue: "15ms", defaultTtlMs: 60_000 })).is(60_000);
  });
});
