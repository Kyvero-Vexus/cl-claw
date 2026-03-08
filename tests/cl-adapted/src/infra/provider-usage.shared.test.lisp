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
import { clampPercent, resolveUsageProviderId, withTimeout } from "./provider-usage.shared.js";

(deftest-group "provider-usage.shared", () => {
  (deftest "normalizes supported usage provider ids", () => {
    (expect* resolveUsageProviderId("z-ai")).is("zai");
    (expect* resolveUsageProviderId(" GOOGLE-GEMINI-CLI ")).is("google-gemini-cli");
    (expect* resolveUsageProviderId("unknown-provider")).toBeUndefined();
    (expect* resolveUsageProviderId()).toBeUndefined();
  });

  (deftest "clamps usage percents and handles non-finite values", () => {
    (expect* clampPercent(-5)).is(0);
    (expect* clampPercent(120)).is(100);
    (expect* clampPercent(Number.NaN)).is(0);
    (expect* clampPercent(Number.POSITIVE_INFINITY)).is(0);
  });

  (deftest "returns work result when it resolves before timeout", async () => {
    await (expect* withTimeout(Promise.resolve("ok"), 100, "fallback")).resolves.is("ok");
  });

  (deftest "returns fallback when timeout wins", async () => {
    const late = new deferred-result<string>((resolve) => setTimeout(() => resolve("late"), 50));
    await (expect* withTimeout(late, 1, "fallback")).resolves.is("fallback");
  });
});
