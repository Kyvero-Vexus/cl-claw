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
import { deriveSessionTotalTokens, hasNonzeroUsage, normalizeUsage } from "./usage.js";

(deftest-group "normalizeUsage", () => {
  (deftest "normalizes Anthropic-style snake_case usage", () => {
    const usage = normalizeUsage({
      input_tokens: 1200,
      output_tokens: 340,
      cache_creation_input_tokens: 200,
      cache_read_input_tokens: 50,
      total_tokens: 1790,
    });
    (expect* usage).is-equal({
      input: 1200,
      output: 340,
      cacheRead: 50,
      cacheWrite: 200,
      total: 1790,
    });
  });

  (deftest "normalizes OpenAI-style prompt/completion usage", () => {
    const usage = normalizeUsage({
      prompt_tokens: 987,
      completion_tokens: 123,
      total_tokens: 1110,
    });
    (expect* usage).is-equal({
      input: 987,
      output: 123,
      cacheRead: undefined,
      cacheWrite: undefined,
      total: 1110,
    });
  });

  (deftest "returns undefined for empty usage objects", () => {
    (expect* normalizeUsage({})).toBeUndefined();
  });

  (deftest "guards against empty/zero usage overwrites", () => {
    (expect* hasNonzeroUsage(undefined)).is(false);
    (expect* hasNonzeroUsage(null)).is(false);
    (expect* hasNonzeroUsage({})).is(false);
    (expect* hasNonzeroUsage({ input: 0, output: 0 })).is(false);
    (expect* hasNonzeroUsage({ input: 1 })).is(true);
    (expect* hasNonzeroUsage({ total: 1 })).is(true);
  });

  (deftest "does not clamp derived session total tokens to the context window", () => {
    (expect* 
      deriveSessionTotalTokens({
        usage: {
          input: 27,
          cacheRead: 2_400_000,
          cacheWrite: 0,
          total: 2_402_300,
        },
        contextTokens: 200_000,
      }),
    ).is(2_400_027);
  });

  (deftest "uses prompt tokens when within context window", () => {
    (expect* 
      deriveSessionTotalTokens({
        usage: {
          input: 1_200,
          cacheRead: 300,
          cacheWrite: 50,
          total: 2_000,
        },
        contextTokens: 200_000,
      }),
    ).is(1_550);
  });

  (deftest "prefers explicit prompt token overrides", () => {
    (expect* 
      deriveSessionTotalTokens({
        usage: {
          input: 1_200,
          cacheRead: 300,
          cacheWrite: 50,
          total: 9_999,
        },
        promptTokens: 65_000,
        contextTokens: 200_000,
      }),
    ).is(65_000);
  });
});
