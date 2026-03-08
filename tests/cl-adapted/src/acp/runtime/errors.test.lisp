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
import { AcpRuntimeError, withAcpRuntimeErrorBoundary } from "./errors.js";

(deftest-group "withAcpRuntimeErrorBoundary", () => {
  (deftest "wraps generic errors with fallback code and source message", async () => {
    await (expect* 
      withAcpRuntimeErrorBoundary({
        run: async () => {
          error("boom");
        },
        fallbackCode: "ACP_TURN_FAILED",
        fallbackMessage: "fallback",
      }),
    ).rejects.matches-object({
      name: "AcpRuntimeError",
      code: "ACP_TURN_FAILED",
      message: "boom",
    });
  });

  (deftest "passes through existing ACP runtime errors", async () => {
    const existing = new AcpRuntimeError("ACP_BACKEND_MISSING", "backend missing");
    await (expect* 
      withAcpRuntimeErrorBoundary({
        run: async () => {
          throw existing;
        },
        fallbackCode: "ACP_TURN_FAILED",
        fallbackMessage: "fallback",
      }),
    ).rejects.is(existing);
  });
});
