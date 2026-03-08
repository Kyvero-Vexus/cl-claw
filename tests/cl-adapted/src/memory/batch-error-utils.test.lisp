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
import { extractBatchErrorMessage, formatUnavailableBatchError } from "./batch-error-utils.js";

(deftest-group "extractBatchErrorMessage", () => {
  (deftest "returns the first top-level error message", () => {
    (expect* 
      extractBatchErrorMessage([
        { response: { body: { error: { message: "nested" } } } },
        { error: { message: "top-level" } },
      ]),
    ).is("nested");
  });

  (deftest "falls back to nested response error message", () => {
    (expect* 
      extractBatchErrorMessage([{ response: { body: { error: { message: "nested-only" } } } }, {}]),
    ).is("nested-only");
  });

  (deftest "accepts plain string response bodies", () => {
    (expect* extractBatchErrorMessage([{ response: { body: "provider plain-text error" } }])).is(
      "provider plain-text error",
    );
  });
});

(deftest-group "formatUnavailableBatchError", () => {
  (deftest "formats errors and non-error values", () => {
    (expect* formatUnavailableBatchError(new Error("boom"))).is("error file unavailable: boom");
    (expect* formatUnavailableBatchError("unreachable")).is("error file unavailable: unreachable");
  });
});
