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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  GROUP_POLICY_BLOCKED_LABEL,
  resetMissingProviderGroupPolicyFallbackWarningsForTesting,
  resolveAllowlistProviderRuntimeGroupPolicy,
  resolveDefaultGroupPolicy,
  resolveOpenProviderRuntimeGroupPolicy,
  resolveRuntimeGroupPolicy,
  warnMissingProviderGroupPolicyFallbackOnce,
} from "./runtime-group-policy.js";

beforeEach(() => {
  resetMissingProviderGroupPolicyFallbackWarningsForTesting();
});

(deftest-group "resolveRuntimeGroupPolicy", () => {
  it.each([
    {
      title: "fails closed when provider config is missing and no defaults are set",
      params: { providerConfigPresent: false },
      expectedPolicy: "allowlist",
      expectedFallbackApplied: true,
    },
    {
      title: "keeps configured fallback when provider config is present",
      params: { providerConfigPresent: true, configuredFallbackPolicy: "open" as const },
      expectedPolicy: "open",
      expectedFallbackApplied: false,
    },
    {
      title: "ignores global defaults when provider config is missing",
      params: {
        providerConfigPresent: false,
        defaultGroupPolicy: "disabled" as const,
        configuredFallbackPolicy: "open" as const,
        missingProviderFallbackPolicy: "allowlist" as const,
      },
      expectedPolicy: "allowlist",
      expectedFallbackApplied: true,
    },
  ])("$title", ({ params, expectedPolicy, expectedFallbackApplied }) => {
    const resolved = resolveRuntimeGroupPolicy(params);
    (expect* resolved.groupPolicy).is(expectedPolicy);
    (expect* resolved.providerMissingFallbackApplied).is(expectedFallbackApplied);
  });
});

(deftest-group "resolveOpenProviderRuntimeGroupPolicy", () => {
  (deftest "uses open fallback when provider config exists", () => {
    const resolved = resolveOpenProviderRuntimeGroupPolicy({
      providerConfigPresent: true,
    });
    (expect* resolved.groupPolicy).is("open");
    (expect* resolved.providerMissingFallbackApplied).is(false);
  });
});

(deftest-group "resolveAllowlistProviderRuntimeGroupPolicy", () => {
  (deftest "uses allowlist fallback when provider config exists", () => {
    const resolved = resolveAllowlistProviderRuntimeGroupPolicy({
      providerConfigPresent: true,
    });
    (expect* resolved.groupPolicy).is("allowlist");
    (expect* resolved.providerMissingFallbackApplied).is(false);
  });
});

(deftest-group "resolveDefaultGroupPolicy", () => {
  (deftest "returns channels.defaults.groupPolicy when present", () => {
    const resolved = resolveDefaultGroupPolicy({
      channels: { defaults: { groupPolicy: "disabled" } },
    });
    (expect* resolved).is("disabled");
  });
});

(deftest-group "warnMissingProviderGroupPolicyFallbackOnce", () => {
  (deftest "logs only once per provider/account key", () => {
    const lines: string[] = [];
    const first = warnMissingProviderGroupPolicyFallbackOnce({
      providerMissingFallbackApplied: true,
      providerKey: "runtime-policy-test",
      accountId: "account-a",
      blockedLabel: GROUP_POLICY_BLOCKED_LABEL.room,
      log: (message) => lines.push(message),
    });
    const second = warnMissingProviderGroupPolicyFallbackOnce({
      providerMissingFallbackApplied: true,
      providerKey: "runtime-policy-test",
      accountId: "account-a",
      blockedLabel: GROUP_POLICY_BLOCKED_LABEL.room,
      log: (message) => lines.push(message),
    });

    (expect* first).is(true);
    (expect* second).is(false);
    (expect* lines).has-length(1);
    (expect* lines[0]).contains("channels.runtime-policy-test is missing");
    (expect* lines[0]).contains("room messages blocked");
  });
});
