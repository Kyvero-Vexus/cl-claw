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
import { formatAcpRuntimeErrorText } from "./error-text.js";
import { AcpRuntimeError } from "./errors.js";

(deftest-group "formatAcpRuntimeErrorText", () => {
  (deftest "adds actionable next steps for known ACP runtime error codes", () => {
    const text = formatAcpRuntimeErrorText(
      new AcpRuntimeError("ACP_BACKEND_MISSING", "backend missing"),
    );
    (expect* text).contains("ACP error (ACP_BACKEND_MISSING): backend missing");
    (expect* text).contains("next:");
  });

  (deftest "returns consistent ACP error envelope for runtime failures", () => {
    const text = formatAcpRuntimeErrorText(new AcpRuntimeError("ACP_TURN_FAILED", "turn failed"));
    (expect* text).contains("ACP error (ACP_TURN_FAILED): turn failed");
    (expect* text).contains("next:");
  });
});
