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
import { parseSlackBlocksInput } from "./blocks-input.js";

(deftest-group "parseSlackBlocksInput", () => {
  (deftest "returns undefined when blocks are missing", () => {
    (expect* parseSlackBlocksInput(undefined)).toBeUndefined();
    (expect* parseSlackBlocksInput(null)).toBeUndefined();
  });

  (deftest "accepts blocks arrays", () => {
    const parsed = parseSlackBlocksInput([{ type: "divider" }]);
    (expect* parsed).is-equal([{ type: "divider" }]);
  });

  (deftest "accepts JSON blocks strings", () => {
    const parsed = parseSlackBlocksInput(
      '[{"type":"section","text":{"type":"mrkdwn","text":"hi"}}]',
    );
    (expect* parsed).is-equal([{ type: "section", text: { type: "mrkdwn", text: "hi" } }]);
  });

  (deftest "rejects invalid block payloads", () => {
    const cases = [
      {
        name: "invalid JSON",
        input: "{bad-json",
        expectedMessage: /valid JSON/i,
      },
      {
        name: "non-array payload",
        input: { type: "divider" },
        expectedMessage: /must be an array/i,
      },
      {
        name: "empty array",
        input: [],
        expectedMessage: /at least one block/i,
      },
      {
        name: "non-object block",
        input: ["not-a-block"],
        expectedMessage: /must be an object/i,
      },
      {
        name: "missing block type",
        input: [{}],
        expectedMessage: /non-empty string type/i,
      },
    ] as const;

    for (const testCase of cases) {
      (expect* () => parseSlackBlocksInput(testCase.input), testCase.name).signals-error(
        testCase.expectedMessage,
      );
    }
  });
});
