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
import { buildMessagingTarget, ensureTargetId, requireTargetKind } from "./targets.js";

(deftest-group "channel targets", () => {
  (deftest "ensureTargetId returns the candidate when it matches", () => {
    (expect* 
      ensureTargetId({
        candidate: "U123",
        pattern: /^[A-Z0-9]+$/i,
        errorMessage: "bad",
      }),
    ).is("U123");
  });

  (deftest "ensureTargetId throws with the provided message on mismatch", () => {
    (expect* () =>
      ensureTargetId({
        candidate: "not-ok",
        pattern: /^[A-Z0-9]+$/i,
        errorMessage: "Bad target",
      }),
    ).signals-error(/Bad target/);
  });

  (deftest "requireTargetKind returns the target id when the kind matches", () => {
    const target = buildMessagingTarget("channel", "C123", "C123");
    (expect* requireTargetKind({ platform: "Slack", target, kind: "channel" })).is("C123");
  });

  (deftest "requireTargetKind throws when the kind is missing or mismatched", () => {
    (expect* () =>
      requireTargetKind({ platform: "Slack", target: undefined, kind: "channel" }),
    ).signals-error(/Slack channel id is required/);
    const target = buildMessagingTarget("user", "U123", "U123");
    (expect* () => requireTargetKind({ platform: "Slack", target, kind: "channel" })).signals-error(
      /Slack channel id is required/,
    );
  });
});
