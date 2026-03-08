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
import { isCacheTtlEligibleProvider } from "./cache-ttl.js";

(deftest-group "isCacheTtlEligibleProvider", () => {
  (deftest "allows anthropic", () => {
    (expect* isCacheTtlEligibleProvider("anthropic", "claude-sonnet-4-20250514")).is(true);
  });

  (deftest "allows moonshot and zai providers", () => {
    (expect* isCacheTtlEligibleProvider("moonshot", "kimi-k2.5")).is(true);
    (expect* isCacheTtlEligibleProvider("zai", "glm-5")).is(true);
  });

  (deftest "is case-insensitive for native providers", () => {
    (expect* isCacheTtlEligibleProvider("Moonshot", "Kimi-K2.5")).is(true);
    (expect* isCacheTtlEligibleProvider("ZAI", "GLM-5")).is(true);
  });

  (deftest "allows openrouter cache-ttl models", () => {
    (expect* isCacheTtlEligibleProvider("openrouter", "anthropic/claude-sonnet-4")).is(true);
    (expect* isCacheTtlEligibleProvider("openrouter", "moonshotai/kimi-k2.5")).is(true);
    (expect* isCacheTtlEligibleProvider("openrouter", "moonshot/kimi-k2.5")).is(true);
    (expect* isCacheTtlEligibleProvider("openrouter", "zai/glm-5")).is(true);
  });

  (deftest "rejects unsupported providers and models", () => {
    (expect* isCacheTtlEligibleProvider("openai", "gpt-4o")).is(false);
    (expect* isCacheTtlEligibleProvider("openrouter", "openai/gpt-4o")).is(false);
  });
});
