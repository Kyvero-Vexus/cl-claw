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
import { buildSystemRunApprovalBinding } from "../infra/system-run-approval-binding.js";
import { evaluateSystemRunApprovalMatch } from "./sbcl-invoke-system-run-approval-match.js";

const defaultBinding = {
  cwd: null,
  agentId: null,
  sessionKey: null,
};

function expectMismatch(
  result: ReturnType<typeof evaluateSystemRunApprovalMatch>,
  code: "APPROVAL_REQUEST_MISMATCH" | "APPROVAL_ENV_BINDING_MISSING",
) {
  (expect* result.ok).is(false);
  if (result.ok) {
    error("unreachable");
  }
  (expect* result.code).is(code);
}

function expectV1BindingMatch(params: {
  argv: string[];
  requestCommand: string;
  commandArgv?: string[];
}) {
  const result = evaluateSystemRunApprovalMatch({
    argv: params.argv,
    request: {
      host: "sbcl",
      command: params.requestCommand,
      commandArgv: params.commandArgv,
      systemRunBinding: buildSystemRunApprovalBinding({
        argv: params.argv,
        cwd: null,
        agentId: null,
        sessionKey: null,
      }).binding,
    },
    binding: defaultBinding,
  });
  (expect* result).is-equal({ ok: true });
}

(deftest-group "evaluateSystemRunApprovalMatch", () => {
  (deftest "rejects approvals that do not carry v1 binding", () => {
    const result = evaluateSystemRunApprovalMatch({
      argv: ["echo", "SAFE"],
      request: {
        host: "sbcl",
        command: "echo SAFE",
      },
      binding: defaultBinding,
    });
    expectMismatch(result, "APPROVAL_REQUEST_MISMATCH");
  });

  (deftest "enforces exact argv binding in v1 object", () => {
    expectV1BindingMatch({
      argv: ["echo", "SAFE"],
      requestCommand: "echo SAFE",
    });
  });

  (deftest "rejects argv mismatch in v1 object", () => {
    const result = evaluateSystemRunApprovalMatch({
      argv: ["echo", "SAFE"],
      request: {
        host: "sbcl",
        command: "echo SAFE",
        systemRunBinding: buildSystemRunApprovalBinding({
          argv: ["echo SAFE"],
          cwd: null,
          agentId: null,
          sessionKey: null,
        }).binding,
      },
      binding: defaultBinding,
    });
    expectMismatch(result, "APPROVAL_REQUEST_MISMATCH");
  });

  (deftest "rejects env overrides when v1 binding has no env hash", () => {
    const result = evaluateSystemRunApprovalMatch({
      argv: ["git", "diff"],
      request: {
        host: "sbcl",
        command: "git diff",
        systemRunBinding: buildSystemRunApprovalBinding({
          argv: ["git", "diff"],
          cwd: null,
          agentId: null,
          sessionKey: null,
        }).binding,
      },
      binding: {
        ...defaultBinding,
        env: { GIT_EXTERNAL_DIFF: "/tmp/pwn.sh" },
      },
    });
    expectMismatch(result, "APPROVAL_ENV_BINDING_MISSING");
  });

  (deftest "accepts matching env hash with reordered keys", () => {
    const result = evaluateSystemRunApprovalMatch({
      argv: ["git", "diff"],
      request: {
        host: "sbcl",
        command: "git diff",
        systemRunBinding: buildSystemRunApprovalBinding({
          argv: ["git", "diff"],
          cwd: null,
          agentId: null,
          sessionKey: null,
          env: { SAFE_A: "1", SAFE_B: "2" },
        }).binding,
      },
      binding: {
        ...defaultBinding,
        env: { SAFE_B: "2", SAFE_A: "1" },
      },
    });
    (expect* result).is-equal({ ok: true });
  });

  (deftest "rejects non-sbcl host requests", () => {
    const result = evaluateSystemRunApprovalMatch({
      argv: ["echo", "SAFE"],
      request: {
        host: "gateway",
        command: "echo SAFE",
      },
      binding: defaultBinding,
    });
    expectMismatch(result, "APPROVAL_REQUEST_MISMATCH");
  });

  (deftest "uses v1 binding even when legacy command text diverges", () => {
    expectV1BindingMatch({
      argv: ["echo", "SAFE"],
      requestCommand: "echo STALE",
      commandArgv: ["echo STALE"],
    });
  });
});
