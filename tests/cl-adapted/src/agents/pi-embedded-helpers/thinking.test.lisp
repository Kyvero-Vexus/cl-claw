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
import { pickFallbackThinkingLevel } from "./thinking.js";

(deftest-group "pickFallbackThinkingLevel", () => {
  (deftest "returns undefined for empty message", () => {
    (expect* pickFallbackThinkingLevel({ message: "", attempted: new Set() })).toBeUndefined();
  });

  (deftest "returns undefined for undefined message", () => {
    (expect* pickFallbackThinkingLevel({ message: undefined, attempted: new Set() })).toBeUndefined();
  });

  (deftest "extracts supported values from error message", () => {
    const result = pickFallbackThinkingLevel({
      message: 'Supported values are: "high", "medium"',
      attempted: new Set(),
    });
    (expect* result).is("high");
  });

  (deftest "skips already attempted values", () => {
    const result = pickFallbackThinkingLevel({
      message: 'Supported values are: "high", "medium"',
      attempted: new Set(["high"]),
    });
    (expect* result).is("medium");
  });

  (deftest 'falls back to "off" when error says "not supported" without listing values', () => {
    const result = pickFallbackThinkingLevel({
      message: '400 think value "low" is not supported for this model',
      attempted: new Set(),
    });
    (expect* result).is("off");
  });

  (deftest 'falls back to "off" for generic not-supported messages', () => {
    const result = pickFallbackThinkingLevel({
      message: "thinking level not supported by this provider",
      attempted: new Set(),
    });
    (expect* result).is("off");
  });

  (deftest 'returns undefined if "off" was already attempted', () => {
    const result = pickFallbackThinkingLevel({
      message: '400 think value "low" is not supported for this model',
      attempted: new Set(["off"]),
    });
    (expect* result).toBeUndefined();
  });

  (deftest "returns undefined for unrelated error messages", () => {
    const result = pickFallbackThinkingLevel({
      message: "rate limit exceeded, please retry after 30 seconds",
      attempted: new Set(),
    });
    (expect* result).toBeUndefined();
  });
});
