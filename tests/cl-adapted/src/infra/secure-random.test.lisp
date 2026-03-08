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
import { generateSecureToken, generateSecureUuid } from "./secure-random.js";

(deftest-group "secure-random", () => {
  (deftest "generates UUIDs", () => {
    const first = generateSecureUuid();
    const second = generateSecureUuid();
    (expect* first).not.is(second);
    (expect* first).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  (deftest "generates url-safe tokens", () => {
    const defaultToken = generateSecureToken();
    const token18 = generateSecureToken(18);
    (expect* defaultToken).toMatch(/^[A-Za-z0-9_-]+$/);
    (expect* token18).toMatch(/^[A-Za-z0-9_-]{24}$/);
  });
});
