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
import { resolveUnusableProfileHint } from "./doctor-auth.js";

(deftest-group "resolveUnusableProfileHint", () => {
  (deftest "returns billing guidance for disabled billing profiles", () => {
    (expect* resolveUnusableProfileHint({ kind: "disabled", reason: "billing" })).is(
      "Top up credits (provider billing) or switch provider.",
    );
  });

  (deftest "returns credential guidance for permanent auth disables", () => {
    (expect* resolveUnusableProfileHint({ kind: "disabled", reason: "auth_permanent" })).is(
      "Refresh or replace credentials, then retry.",
    );
  });

  (deftest "falls back to cooldown guidance for non-billing disable reasons", () => {
    (expect* resolveUnusableProfileHint({ kind: "disabled", reason: "unknown" })).is(
      "Wait for cooldown or switch provider.",
    );
  });

  (deftest "returns cooldown guidance for cooldown windows", () => {
    (expect* resolveUnusableProfileHint({ kind: "cooldown" })).is(
      "Wait for cooldown or switch provider.",
    );
  });
});
