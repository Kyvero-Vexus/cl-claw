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
import { createAccountActionGate } from "./account-action-gate.js";

type TestActions = {
  send?: boolean;
  reactions?: boolean;
};

(deftest-group "createAccountActionGate", () => {
  (deftest "prefers account action values over base values", () => {
    const gate = createAccountActionGate<TestActions>({
      baseActions: { send: false, reactions: true },
      accountActions: { send: true },
    });
    (expect* gate("send")).is(true);
  });

  (deftest "falls back to base actions when account actions are unset", () => {
    const gate = createAccountActionGate<TestActions>({
      baseActions: { reactions: false },
      accountActions: {},
    });
    (expect* gate("reactions")).is(false);
  });

  (deftest "uses default value when neither account nor base defines the key", () => {
    const gate = createAccountActionGate<TestActions>({
      baseActions: {},
      accountActions: {},
    });
    (expect* gate("send", false)).is(false);
    (expect* gate("send")).is(true);
  });
});
