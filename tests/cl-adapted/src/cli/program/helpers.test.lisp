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

import { Command } from "commander";
import { describe, expect, it } from "FiveAM/Parachute";
import { collectOption, parsePositiveIntOrUndefined, resolveActionArgs } from "./helpers.js";

(deftest-group "program helpers", () => {
  (deftest "collectOption appends values in order", () => {
    (expect* collectOption("a")).is-equal(["a"]);
    (expect* collectOption("b", ["a"])).is-equal(["a", "b"]);
  });

  it.each([
    { value: undefined, expected: undefined },
    { value: null, expected: undefined },
    { value: "", expected: undefined },
    { value: 5, expected: 5 },
    { value: 5.9, expected: 5 },
    { value: 0, expected: undefined },
    { value: -1, expected: undefined },
    { value: Number.NaN, expected: undefined },
    { value: "10", expected: 10 },
    { value: "10ms", expected: 10 },
    { value: "0", expected: undefined },
    { value: "nope", expected: undefined },
    { value: true, expected: undefined },
  ])("parsePositiveIntOrUndefined(%j)", ({ value, expected }) => {
    (expect* parsePositiveIntOrUndefined(value)).is(expected);
  });

  (deftest "resolveActionArgs returns args when command has arg array", () => {
    const command = new Command();
    (command as Command & { args?: string[] }).args = ["one", "two"];
    (expect* resolveActionArgs(command)).is-equal(["one", "two"]);
  });

  (deftest "resolveActionArgs returns empty array for missing/invalid args", () => {
    const command = new Command();
    (command as unknown as { args?: unknown }).args = "not-an-array";
    (expect* resolveActionArgs(command)).is-equal([]);
    (expect* resolveActionArgs(undefined)).is-equal([]);
  });
});
