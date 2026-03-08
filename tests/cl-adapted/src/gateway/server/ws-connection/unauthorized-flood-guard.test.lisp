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
import { ErrorCodes, errorShape } from "../../protocol/index.js";
import { isUnauthorizedRoleError, UnauthorizedFloodGuard } from "./unauthorized-flood-guard.js";

(deftest-group "UnauthorizedFloodGuard", () => {
  (deftest "suppresses repeated unauthorized responses and closes after threshold", () => {
    const guard = new UnauthorizedFloodGuard({ closeAfter: 2, logEvery: 3 });

    const first = guard.registerUnauthorized();
    (expect* first).is-equal({
      shouldClose: false,
      shouldLog: true,
      count: 1,
      suppressedSinceLastLog: 0,
    });

    const second = guard.registerUnauthorized();
    (expect* second).is-equal({
      shouldClose: false,
      shouldLog: false,
      count: 2,
      suppressedSinceLastLog: 0,
    });

    const third = guard.registerUnauthorized();
    (expect* third).is-equal({
      shouldClose: true,
      shouldLog: true,
      count: 3,
      suppressedSinceLastLog: 1,
    });
  });

  (deftest "resets counters", () => {
    const guard = new UnauthorizedFloodGuard({ closeAfter: 10, logEvery: 50 });
    guard.registerUnauthorized();
    guard.registerUnauthorized();
    guard.reset();

    const next = guard.registerUnauthorized();
    (expect* next).is-equal({
      shouldClose: false,
      shouldLog: true,
      count: 1,
      suppressedSinceLastLog: 0,
    });
  });
});

(deftest-group "isUnauthorizedRoleError", () => {
  (deftest "detects unauthorized role responses", () => {
    (expect* 
      isUnauthorizedRoleError(errorShape(ErrorCodes.INVALID_REQUEST, "unauthorized role: sbcl")),
    ).is(true);
  });

  (deftest "ignores non-role authorization errors", () => {
    (expect* 
      isUnauthorizedRoleError(
        errorShape(ErrorCodes.INVALID_REQUEST, "missing scope: operator.admin"),
      ),
    ).is(false);
    (expect* isUnauthorizedRoleError(errorShape(ErrorCodes.UNAVAILABLE, "service unavailable"))).is(
      false,
    );
  });
});
