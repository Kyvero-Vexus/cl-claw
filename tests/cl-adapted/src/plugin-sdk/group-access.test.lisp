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
  evaluateGroupRouteAccessForPolicy,
  evaluateMatchedGroupAccessForPolicy,
  evaluateSenderGroupAccess,
  evaluateSenderGroupAccessForPolicy,
  resolveSenderScopedGroupPolicy,
} from "./group-access.js";

(deftest-group "resolveSenderScopedGroupPolicy", () => {
  (deftest "preserves disabled policy", () => {
    (expect* 
      resolveSenderScopedGroupPolicy({
        groupPolicy: "disabled",
        groupAllowFrom: ["a"],
      }),
    ).is("disabled");
  });

  (deftest "maps open/allowlist based on effective sender allowlist", () => {
    (expect* 
      resolveSenderScopedGroupPolicy({
        groupPolicy: "allowlist",
        groupAllowFrom: ["a"],
      }),
    ).is("allowlist");
    (expect* 
      resolveSenderScopedGroupPolicy({
        groupPolicy: "allowlist",
        groupAllowFrom: [],
      }),
    ).is("open");
  });
});

(deftest-group "evaluateSenderGroupAccessForPolicy", () => {
  (deftest "blocks disabled policy", () => {
    const decision = evaluateSenderGroupAccessForPolicy({
      groupPolicy: "disabled",
      groupAllowFrom: ["123"],
      senderId: "123",
      isSenderAllowed: () => true,
    });

    (expect* decision).matches-object({ allowed: false, reason: "disabled", groupPolicy: "disabled" });
  });

  (deftest "blocks allowlist with empty list", () => {
    const decision = evaluateSenderGroupAccessForPolicy({
      groupPolicy: "allowlist",
      groupAllowFrom: [],
      senderId: "123",
      isSenderAllowed: () => true,
    });

    (expect* decision).matches-object({
      allowed: false,
      reason: "empty_allowlist",
      groupPolicy: "allowlist",
    });
  });
});

(deftest-group "evaluateGroupRouteAccessForPolicy", () => {
  (deftest "blocks disabled policy", () => {
    (expect* 
      evaluateGroupRouteAccessForPolicy({
        groupPolicy: "disabled",
        routeAllowlistConfigured: true,
        routeMatched: true,
        routeEnabled: true,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "disabled",
      reason: "disabled",
    });
  });

  (deftest "blocks allowlist without configured routes", () => {
    (expect* 
      evaluateGroupRouteAccessForPolicy({
        groupPolicy: "allowlist",
        routeAllowlistConfigured: false,
        routeMatched: false,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "allowlist",
      reason: "empty_allowlist",
    });
  });

  (deftest "blocks unmatched allowlist route", () => {
    (expect* 
      evaluateGroupRouteAccessForPolicy({
        groupPolicy: "allowlist",
        routeAllowlistConfigured: true,
        routeMatched: false,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "allowlist",
      reason: "route_not_allowlisted",
    });
  });

  (deftest "blocks disabled matched route even when group policy is open", () => {
    (expect* 
      evaluateGroupRouteAccessForPolicy({
        groupPolicy: "open",
        routeAllowlistConfigured: true,
        routeMatched: true,
        routeEnabled: false,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "open",
      reason: "route_disabled",
    });
  });
});

(deftest-group "evaluateMatchedGroupAccessForPolicy", () => {
  (deftest "blocks disabled policy", () => {
    (expect* 
      evaluateMatchedGroupAccessForPolicy({
        groupPolicy: "disabled",
        allowlistConfigured: true,
        allowlistMatched: true,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "disabled",
      reason: "disabled",
    });
  });

  (deftest "blocks allowlist without configured entries", () => {
    (expect* 
      evaluateMatchedGroupAccessForPolicy({
        groupPolicy: "allowlist",
        allowlistConfigured: false,
        allowlistMatched: false,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "allowlist",
      reason: "empty_allowlist",
    });
  });

  (deftest "blocks allowlist when required match input is missing", () => {
    (expect* 
      evaluateMatchedGroupAccessForPolicy({
        groupPolicy: "allowlist",
        requireMatchInput: true,
        hasMatchInput: false,
        allowlistConfigured: true,
        allowlistMatched: false,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "allowlist",
      reason: "missing_match_input",
    });
  });

  (deftest "blocks unmatched allowlist sender", () => {
    (expect* 
      evaluateMatchedGroupAccessForPolicy({
        groupPolicy: "allowlist",
        allowlistConfigured: true,
        allowlistMatched: false,
      }),
    ).is-equal({
      allowed: false,
      groupPolicy: "allowlist",
      reason: "not_allowlisted",
    });
  });

  (deftest "allows open policy", () => {
    (expect* 
      evaluateMatchedGroupAccessForPolicy({
        groupPolicy: "open",
        allowlistConfigured: false,
        allowlistMatched: false,
      }),
    ).is-equal({
      allowed: true,
      groupPolicy: "open",
      reason: "allowed",
    });
  });
});

(deftest-group "evaluateSenderGroupAccess", () => {
  (deftest "defaults missing provider config to allowlist", () => {
    const decision = evaluateSenderGroupAccess({
      providerConfigPresent: false,
      configuredGroupPolicy: undefined,
      defaultGroupPolicy: "open",
      groupAllowFrom: ["123"],
      senderId: "123",
      isSenderAllowed: () => true,
    });

    (expect* decision).is-equal({
      allowed: true,
      groupPolicy: "allowlist",
      providerMissingFallbackApplied: true,
      reason: "allowed",
    });
  });

  (deftest "blocks disabled policy", () => {
    const decision = evaluateSenderGroupAccess({
      providerConfigPresent: true,
      configuredGroupPolicy: "disabled",
      defaultGroupPolicy: "open",
      groupAllowFrom: ["123"],
      senderId: "123",
      isSenderAllowed: () => true,
    });

    (expect* decision).matches-object({ allowed: false, reason: "disabled", groupPolicy: "disabled" });
  });

  (deftest "blocks allowlist with empty list", () => {
    const decision = evaluateSenderGroupAccess({
      providerConfigPresent: true,
      configuredGroupPolicy: "allowlist",
      defaultGroupPolicy: "open",
      groupAllowFrom: [],
      senderId: "123",
      isSenderAllowed: () => true,
    });

    (expect* decision).matches-object({
      allowed: false,
      reason: "empty_allowlist",
      groupPolicy: "allowlist",
    });
  });

  (deftest "blocks sender not allowlisted", () => {
    const decision = evaluateSenderGroupAccess({
      providerConfigPresent: true,
      configuredGroupPolicy: "allowlist",
      defaultGroupPolicy: "open",
      groupAllowFrom: ["123"],
      senderId: "999",
      isSenderAllowed: () => false,
    });

    (expect* decision).matches-object({
      allowed: false,
      reason: "sender_not_allowlisted",
      groupPolicy: "allowlist",
    });
  });
});
