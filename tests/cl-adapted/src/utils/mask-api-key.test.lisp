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
import { maskApiKey } from "./mask-api-key.js";

(deftest-group "maskApiKey", () => {
  (deftest "returns missing for empty values", () => {
    (expect* maskApiKey("")).is("missing");
    (expect* maskApiKey("   ")).is("missing");
  });

  (deftest "masks short and medium values without returning raw secrets", () => {
    (expect* maskApiKey(" abcdefghijklmnop ")).is("ab...op");
    (expect* maskApiKey(" short ")).is("s...t");
    (expect* maskApiKey(" a ")).is("a...a");
    (expect* maskApiKey(" ab ")).is("a...b");
  });

  (deftest "masks long values with first and last 8 chars", () => {
    (expect* maskApiKey("1234567890abcdefghijklmnop")).is("12345678...ijklmnop"); // pragma: allowlist secret
  });
});
