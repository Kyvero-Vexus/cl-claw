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
import { mapAllowlistResolutionInputs } from "./allowlist-resolution.js";

(deftest-group "mapAllowlistResolutionInputs", () => {
  (deftest "maps inputs sequentially and preserves order", async () => {
    const visited: string[] = [];
    const result = await mapAllowlistResolutionInputs({
      inputs: ["one", "two", "three"],
      mapInput: async (input) => {
        visited.push(input);
        return input.toUpperCase();
      },
    });

    (expect* visited).is-equal(["one", "two", "three"]);
    (expect* result).is-equal(["ONE", "TWO", "THREE"]);
  });
});
