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
import { consumeRootOptionToken } from "./cli-root-options.js";

(deftest-group "consumeRootOptionToken", () => {
  (deftest "consumes boolean and inline root options", () => {
    (expect* consumeRootOptionToken(["--dev"], 0)).is(1);
    (expect* consumeRootOptionToken(["--profile=work"], 0)).is(1);
    (expect* consumeRootOptionToken(["--log-level=debug"], 0)).is(1);
  });

  (deftest "consumes split root value option only when next token is a value", () => {
    (expect* consumeRootOptionToken(["--profile", "work"], 0)).is(2);
    (expect* consumeRootOptionToken(["--profile", "--no-color"], 0)).is(1);
    (expect* consumeRootOptionToken(["--profile", "--"], 0)).is(1);
  });
});
