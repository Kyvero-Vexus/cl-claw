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
import { SESSION_ID_RE, looksLikeSessionId } from "./session-id.js";

(deftest-group "session-id", () => {
  (deftest "matches canonical UUID session ids", () => {
    (expect* SESSION_ID_RE.(deftest "123e4567-e89b-12d3-a456-426614174000")).is(true);
    (expect* looksLikeSessionId(" 123e4567-e89b-12d3-a456-426614174000 ")).is(true);
  });

  (deftest "rejects non-session-id values", () => {
    (expect* SESSION_ID_RE.(deftest "agent:main:main")).is(false);
    (expect* looksLikeSessionId("session-label")).is(false);
  });
});
