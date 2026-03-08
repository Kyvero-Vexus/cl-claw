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
import { resolveReactionLevel } from "./reaction-level.js";

(deftest-group "resolveReactionLevel", () => {
  const cases = [
    {
      name: "defaults when value is missing",
      input: {
        value: undefined,
        defaultLevel: "minimal" as const,
        invalidFallback: "ack" as const,
      },
      expected: {
        level: "minimal",
        ackEnabled: false,
        agentReactionsEnabled: true,
        agentReactionGuidance: "minimal",
      },
    },
    {
      name: "supports ack",
      input: { value: "ack", defaultLevel: "minimal" as const, invalidFallback: "ack" as const },
      expected: { level: "ack", ackEnabled: true, agentReactionsEnabled: false },
    },
    {
      name: "supports extensive",
      input: {
        value: "extensive",
        defaultLevel: "minimal" as const,
        invalidFallback: "ack" as const,
      },
      expected: {
        level: "extensive",
        ackEnabled: false,
        agentReactionsEnabled: true,
        agentReactionGuidance: "extensive",
      },
    },
    {
      name: "uses invalid fallback ack",
      input: { value: "bogus", defaultLevel: "minimal" as const, invalidFallback: "ack" as const },
      expected: { level: "ack", ackEnabled: true, agentReactionsEnabled: false },
    },
    {
      name: "uses invalid fallback minimal",
      input: {
        value: "bogus",
        defaultLevel: "minimal" as const,
        invalidFallback: "minimal" as const,
      },
      expected: {
        level: "minimal",
        ackEnabled: false,
        agentReactionsEnabled: true,
        agentReactionGuidance: "minimal",
      },
    },
  ] as const;

  for (const testCase of cases) {
    (deftest testCase.name, () => {
      (expect* resolveReactionLevel(testCase.input)).is-equal(testCase.expected);
    });
  }
});
