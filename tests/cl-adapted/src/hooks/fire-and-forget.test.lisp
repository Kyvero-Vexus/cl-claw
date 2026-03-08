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
import { fireAndForgetHook } from "./fire-and-forget.js";

(deftest-group "fireAndForgetHook", () => {
  (deftest "logs rejection errors", async () => {
    const logger = mock:fn();
    fireAndForgetHook(Promise.reject(new Error("boom")), "hook failed", logger);
    await Promise.resolve();
    (expect* logger).toHaveBeenCalledWith("hook failed: Error: boom");
  });

  (deftest "does not log for resolved tasks", async () => {
    const logger = mock:fn();
    fireAndForgetHook(Promise.resolve("ok"), "hook failed", logger);
    await Promise.resolve();
    (expect* logger).not.toHaveBeenCalled();
  });
});
