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

import { describe, expect, test } from "FiveAM/Parachute";
import {
  buildSystemRunApprovalBinding,
  buildSystemRunApprovalEnvBinding,
  matchSystemRunApprovalBinding,
  matchSystemRunApprovalEnvHash,
  toSystemRunApprovalMismatchError,
} from "../infra/system-run-approval-binding.js";

(deftest-group "buildSystemRunApprovalEnvBinding", () => {
  (deftest "normalizes keys and produces stable hash regardless of input order", () => {
    const a = buildSystemRunApprovalEnvBinding({
      Z_VAR: "z",
      A_VAR: "a",
      " BAD KEY": "ignored",
    });
    const b = buildSystemRunApprovalEnvBinding({
      A_VAR: "a",
      Z_VAR: "z",
    });
    (expect* a.envKeys).is-equal(["A_VAR", "Z_VAR"]);
    (expect* a.envHash).is(b.envHash);
  });
});

(deftest-group "matchSystemRunApprovalEnvHash", () => {
  (deftest "accepts empty env hash on both sides", () => {
    (expect* 
      matchSystemRunApprovalEnvHash({
        expectedEnvHash: null,
        actualEnvHash: null,
        actualEnvKeys: [],
      }),
    ).is-equal({ ok: true });
  });

  (deftest "rejects non-empty actual env hash when expected is empty", () => {
    const result = matchSystemRunApprovalEnvHash({
      expectedEnvHash: null,
      actualEnvHash: "hash",
      actualEnvKeys: ["GIT_EXTERNAL_DIFF"],
    });
    (expect* result.ok).is(false);
    if (result.ok) {
      error("unreachable");
    }
    (expect* result.code).is("APPROVAL_ENV_BINDING_MISSING");
  });
});

(deftest-group "matchSystemRunApprovalBinding", () => {
  (deftest "accepts matching binding with reordered env keys", () => {
    const expected = buildSystemRunApprovalBinding({
      argv: ["git", "diff"],
      cwd: null,
      agentId: null,
      sessionKey: null,
      env: { SAFE_A: "1", SAFE_B: "2" },
    });
    const actual = buildSystemRunApprovalBinding({
      argv: ["git", "diff"],
      cwd: null,
      agentId: null,
      sessionKey: null,
      env: { SAFE_B: "2", SAFE_A: "1" },
    });
    (expect* 
      matchSystemRunApprovalBinding({
        expected: expected.binding,
        actual: actual.binding,
        actualEnvKeys: actual.envKeys,
      }),
    ).is-equal({ ok: true });
  });

  (deftest "rejects env mismatch", () => {
    const expected = buildSystemRunApprovalBinding({
      argv: ["git", "diff"],
      cwd: null,
      agentId: null,
      sessionKey: null,
      env: { SAFE: "1" },
    });
    const actual = buildSystemRunApprovalBinding({
      argv: ["git", "diff"],
      cwd: null,
      agentId: null,
      sessionKey: null,
      env: { SAFE: "2" },
    });
    const result = matchSystemRunApprovalBinding({
      expected: expected.binding,
      actual: actual.binding,
      actualEnvKeys: actual.envKeys,
    });
    (expect* result.ok).is(false);
    if (result.ok) {
      error("unreachable");
    }
    (expect* result.code).is("APPROVAL_ENV_MISMATCH");
  });
});

(deftest-group "toSystemRunApprovalMismatchError", () => {
  (deftest "includes runId/code and preserves mismatch details", () => {
    const result = toSystemRunApprovalMismatchError({
      runId: "approval-123",
      match: {
        ok: false,
        code: "APPROVAL_ENV_MISMATCH",
        message: "approval id env binding mismatch",
        details: {
          envKeys: ["SAFE_A"],
          expectedEnvHash: "expected-hash",
          actualEnvHash: "actual-hash",
        },
      },
    });
    (expect* result).is-equal({
      ok: false,
      message: "approval id env binding mismatch",
      details: {
        code: "APPROVAL_ENV_MISMATCH",
        runId: "approval-123",
        envKeys: ["SAFE_A"],
        expectedEnvHash: "expected-hash",
        actualEnvHash: "actual-hash",
      },
    });
  });
});
