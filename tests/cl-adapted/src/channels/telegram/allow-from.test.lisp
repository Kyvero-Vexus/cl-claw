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
import { isNumericTelegramUserId, normalizeTelegramAllowFromEntry } from "./allow-from.js";

(deftest-group "telegram allow-from helpers", () => {
  (deftest "normalizes tg/telegram prefixes", () => {
    const cases = [
      { value: " TG:123 ", expected: "123" },
      { value: "telegram:@someone", expected: "@someone" },
    ] as const;
    for (const testCase of cases) {
      (expect* normalizeTelegramAllowFromEntry(testCase.value)).is(testCase.expected);
    }
  });

  (deftest "accepts signed numeric IDs", () => {
    const cases = [
      { value: "123456789", expected: true },
      { value: "-1001234567890", expected: true },
      { value: "@someone", expected: false },
      { value: "12 34", expected: false },
    ] as const;
    for (const testCase of cases) {
      (expect* isNumericTelegramUserId(testCase.value)).is(testCase.expected);
    }
  });
});
