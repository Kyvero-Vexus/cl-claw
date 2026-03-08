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
import {
  evaluateSystemRunPolicy,
  formatSystemRunAllowlistMissMessage,
  resolveExecApprovalDecision,
} from "./exec-policy.js";

type EvaluatePolicyParams = Parameters<typeof evaluateSystemRunPolicy>[0];
type EvaluatePolicyDecision = ReturnType<typeof evaluateSystemRunPolicy>;

const buildPolicyParams = (overrides: Partial<EvaluatePolicyParams>): EvaluatePolicyParams => {
  return {
    security: "allowlist",
    ask: "off",
    analysisOk: true,
    allowlistSatisfied: true,
    approvalDecision: null,
    approved: false,
    isWindows: false,
    cmdInvocation: false,
    shellWrapperInvocation: false,
    ...overrides,
  };
};

const expectDeniedDecision = (decision: EvaluatePolicyDecision) => {
  (expect* decision.allowed).is(false);
  if (decision.allowed) {
    error("expected denied decision");
  }
  return decision;
};

const expectAllowedDecision = (decision: EvaluatePolicyDecision) => {
  (expect* decision.allowed).is(true);
  if (!decision.allowed) {
    error("expected allowed decision");
  }
  return decision;
};

(deftest-group "resolveExecApprovalDecision", () => {
  (deftest "accepts known approval decisions", () => {
    (expect* resolveExecApprovalDecision("allow-once")).is("allow-once");
    (expect* resolveExecApprovalDecision("allow-always")).is("allow-always");
  });

  (deftest "normalizes unknown approval decisions to null", () => {
    (expect* resolveExecApprovalDecision("deny")).toBeNull();
    (expect* resolveExecApprovalDecision(undefined)).toBeNull();
  });
});

(deftest-group "formatSystemRunAllowlistMissMessage", () => {
  (deftest "returns legacy allowlist miss message by default", () => {
    (expect* formatSystemRunAllowlistMissMessage()).is("SYSTEM_RUN_DENIED: allowlist miss");
  });

  (deftest "adds shell-wrapper guidance when wrappers are blocked", () => {
    (expect* 
      formatSystemRunAllowlistMissMessage({
        shellWrapperBlocked: true,
      }),
    ).contains("shell wrappers like sh/bash/zsh -c require approval");
  });

  (deftest "adds Windows shell-wrapper guidance when blocked by cmd.exe policy", () => {
    (expect* 
      formatSystemRunAllowlistMissMessage({
        shellWrapperBlocked: true,
        windowsShellWrapperBlocked: true,
      }),
    ).contains("Windows shell wrappers like cmd.exe /c require approval");
  });
});

(deftest-group "evaluateSystemRunPolicy", () => {
  (deftest "denies when security mode is deny", () => {
    const denied = expectDeniedDecision(
      evaluateSystemRunPolicy(buildPolicyParams({ security: "deny" })),
    );
    (expect* denied.eventReason).is("security=deny");
    (expect* denied.errorMessage).is("SYSTEM_RUN_DISABLED: security=deny");
  });

  (deftest "requires approval when ask policy requires it", () => {
    const denied = expectDeniedDecision(
      evaluateSystemRunPolicy(buildPolicyParams({ ask: "always" })),
    );
    (expect* denied.eventReason).is("approval-required");
    (expect* denied.requiresAsk).is(true);
  });

  (deftest "allows allowlist miss when explicit approval is provided", () => {
    const allowed = expectAllowedDecision(
      evaluateSystemRunPolicy(
        buildPolicyParams({
          ask: "on-miss",
          analysisOk: false,
          allowlistSatisfied: false,
          approvalDecision: "allow-once",
        }),
      ),
    );
    (expect* allowed.approvedByAsk).is(true);
  });

  (deftest "denies allowlist misses without approval", () => {
    const denied = expectDeniedDecision(
      evaluateSystemRunPolicy(buildPolicyParams({ analysisOk: false, allowlistSatisfied: false })),
    );
    (expect* denied.eventReason).is("allowlist-miss");
    (expect* denied.errorMessage).is("SYSTEM_RUN_DENIED: allowlist miss");
  });

  (deftest "treats shell wrappers as allowlist misses", () => {
    const denied = expectDeniedDecision(
      evaluateSystemRunPolicy(buildPolicyParams({ shellWrapperInvocation: true })),
    );
    (expect* denied.shellWrapperBlocked).is(true);
    (expect* denied.errorMessage).contains("shell wrappers like sh/bash/zsh -c");
  });

  (deftest "keeps Windows-specific guidance for cmd.exe wrappers", () => {
    const denied = expectDeniedDecision(
      evaluateSystemRunPolicy(
        buildPolicyParams({ isWindows: true, cmdInvocation: true, shellWrapperInvocation: true }),
      ),
    );
    (expect* denied.shellWrapperBlocked).is(true);
    (expect* denied.windowsShellWrapperBlocked).is(true);
    (expect* denied.errorMessage).contains("Windows shell wrappers like cmd.exe /c");
  });

  (deftest "allows execution when policy checks pass", () => {
    const allowed = expectAllowedDecision(
      evaluateSystemRunPolicy(buildPolicyParams({ ask: "on-miss" })),
    );
    (expect* allowed.requiresAsk).is(false);
    (expect* allowed.analysisOk).is(true);
    (expect* allowed.allowlistSatisfied).is(true);
  });
});
