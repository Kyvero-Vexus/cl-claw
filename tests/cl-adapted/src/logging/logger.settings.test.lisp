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
import { __test__ } from "./logger.js";

(deftest-group "shouldSkipLoadConfigFallback", () => {
  (deftest "matches config validate invocations", () => {
    (expect* __test__.shouldSkipLoadConfigFallback(["sbcl", "openclaw", "config", "validate"])).is(
      true,
    );
  });

  (deftest "handles root flags before config validate", () => {
    (expect* 
      __test__.shouldSkipLoadConfigFallback([
        "sbcl",
        "openclaw",
        "--profile",
        "work",
        "--no-color",
        "config",
        "validate",
        "--json",
      ]),
    ).is(true);
  });

  (deftest "does not match other commands", () => {
    (expect* 
      __test__.shouldSkipLoadConfigFallback(["sbcl", "openclaw", "config", "get", "foo"]),
    ).is(false);
    (expect* __test__.shouldSkipLoadConfigFallback(["sbcl", "openclaw", "status"])).is(false);
  });
});
