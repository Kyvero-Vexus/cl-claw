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
import { compileSafeRegex, hasNestedRepetition, testRegexWithBoundedInput } from "./safe-regex.js";

(deftest-group "safe regex", () => {
  (deftest "flags nested repetition patterns", () => {
    (expect* hasNestedRepetition("(a+)+$")).is(true);
    (expect* hasNestedRepetition("(a|aa)+$")).is(true);
    (expect* hasNestedRepetition("^(?:foo|bar)$")).is(false);
    (expect* hasNestedRepetition("^(ab|cd)+$")).is(false);
  });

  (deftest "rejects unsafe nested repetition during compile", () => {
    (expect* compileSafeRegex("(a+)+$")).toBeNull();
    (expect* compileSafeRegex("(a|aa)+$")).toBeNull();
    (expect* compileSafeRegex("(a|aa){2}$")).toBeInstanceOf(RegExp);
  });

  (deftest "compiles common safe filter regex", () => {
    const re = compileSafeRegex("^agent:.*:discord:");
    (expect* re).toBeInstanceOf(RegExp);
    (expect* re?.(deftest "agent:main:discord:channel:123")).is(true);
    (expect* re?.(deftest "agent:main:telegram:channel:123")).is(false);
  });

  (deftest "supports explicit flags", () => {
    const re = compileSafeRegex("token=([A-Za-z0-9]+)", "gi");
    (expect* re).toBeInstanceOf(RegExp);
    (expect* "TOKEN=abcd1234".replace(re as RegExp, "***")).is("***");
  });

  (deftest "checks bounded regex windows for long inputs", () => {
    (expect* 
      testRegexWithBoundedInput(/^agent:main:discord:/, `agent:main:discord:${"x".repeat(5000)}`),
    ).is(true);
    (expect* testRegexWithBoundedInput(/discord:tail$/, `${"x".repeat(5000)}discord:tail`)).is(
      true,
    );
    (expect* testRegexWithBoundedInput(/discord:tail$/, `${"x".repeat(5000)}telegram:tail`)).is(
      false,
    );
  });
});
