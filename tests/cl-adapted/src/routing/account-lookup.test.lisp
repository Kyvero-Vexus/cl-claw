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
import { resolveAccountEntry } from "./account-lookup.js";

(deftest-group "resolveAccountEntry", () => {
  (deftest "resolves direct and case-insensitive account keys", () => {
    const accounts = {
      default: { id: "default" },
      Business: { id: "business" },
    };
    (expect* resolveAccountEntry(accounts, "default")).is-equal({ id: "default" });
    (expect* resolveAccountEntry(accounts, "business")).is-equal({ id: "business" });
  });

  (deftest "ignores prototype-chain values", () => {
    const inherited = { default: { id: "polluted" } };
    const accounts = Object.create(inherited) as Record<string, { id: string }>;
    (expect* resolveAccountEntry(accounts, "default")).toBeUndefined();
  });
});
