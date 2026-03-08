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
  collectAllowlistProviderGroupPolicyWarnings,
  collectAllowlistProviderRestrictSendersWarnings,
  collectOpenGroupPolicyConfiguredRouteWarnings,
  collectOpenProviderGroupPolicyWarnings,
  collectOpenGroupPolicyRestrictSendersWarnings,
  collectOpenGroupPolicyRouteAllowlistWarnings,
  buildOpenGroupPolicyConfigureRouteAllowlistWarning,
  buildOpenGroupPolicyNoRouteAllowlistWarning,
  buildOpenGroupPolicyRestrictSendersWarning,
  buildOpenGroupPolicyWarning,
} from "./group-policy-warnings.js";

(deftest-group "group policy warning builders", () => {
  (deftest "builds base open-policy warning", () => {
    (expect* 
      buildOpenGroupPolicyWarning({
        surface: "Example groups",
        openBehavior: "allows any member to trigger (mention-gated)",
        remediation: 'Set channels.example.groupPolicy="allowlist"',
      }),
    ).is(
      '- Example groups: groupPolicy="open" allows any member to trigger (mention-gated). Set channels.example.groupPolicy="allowlist".',
    );
  });

  (deftest "builds restrict-senders warning", () => {
    (expect* 
      buildOpenGroupPolicyRestrictSendersWarning({
        surface: "Example groups",
        openScope: "any member in allowed groups",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      }),
    ).is(
      '- Example groups: groupPolicy="open" allows any member in allowed groups to trigger (mention-gated). Set channels.example.groupPolicy="allowlist" + channels.example.groupAllowFrom to restrict senders.',
    );
  });

  (deftest "builds no-route-allowlist warning", () => {
    (expect* 
      buildOpenGroupPolicyNoRouteAllowlistWarning({
        surface: "Example groups",
        routeAllowlistPath: "channels.example.groups",
        routeScope: "group",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      }),
    ).is(
      '- Example groups: groupPolicy="open" with no channels.example.groups allowlist; any group can add + ping (mention-gated). Set channels.example.groupPolicy="allowlist" + channels.example.groupAllowFrom or configure channels.example.groups.',
    );
  });

  (deftest "builds configure-route-allowlist warning", () => {
    (expect* 
      buildOpenGroupPolicyConfigureRouteAllowlistWarning({
        surface: "Example channels",
        openScope: "any channel not explicitly denied",
        groupPolicyPath: "channels.example.groupPolicy",
        routeAllowlistPath: "channels.example.channels",
      }),
    ).is(
      '- Example channels: groupPolicy="open" allows any channel not explicitly denied to trigger (mention-gated). Set channels.example.groupPolicy="allowlist" and configure channels.example.channels.',
    );
  });

  (deftest "collects restrict-senders warning only for open policy", () => {
    (expect* 
      collectOpenGroupPolicyRestrictSendersWarnings({
        groupPolicy: "allowlist",
        surface: "Example groups",
        openScope: "any member",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      }),
    ).is-equal([]);

    (expect* 
      collectOpenGroupPolicyRestrictSendersWarnings({
        groupPolicy: "open",
        surface: "Example groups",
        openScope: "any member",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      }),
    ).has-length(1);
  });

  (deftest "resolves allowlist-provider runtime policy before collecting restrict-senders warnings", () => {
    (expect* 
      collectAllowlistProviderRestrictSendersWarnings({
        cfg: {
          channels: {
            defaults: { groupPolicy: "open" },
          },
        },
        providerConfigPresent: false,
        configuredGroupPolicy: undefined,
        surface: "Example groups",
        openScope: "any member",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      }),
    ).is-equal([]);

    (expect* 
      collectAllowlistProviderRestrictSendersWarnings({
        cfg: {
          channels: {
            defaults: { groupPolicy: "open" },
          },
        },
        providerConfigPresent: true,
        configuredGroupPolicy: "open",
        surface: "Example groups",
        openScope: "any member",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      }),
    ).is-equal([
      buildOpenGroupPolicyRestrictSendersWarning({
        surface: "Example groups",
        openScope: "any member",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      }),
    ]);
  });

  (deftest "passes resolved allowlist-provider policy into the warning collector", () => {
    (expect* 
      collectAllowlistProviderGroupPolicyWarnings({
        cfg: {
          channels: {
            defaults: { groupPolicy: "open" },
          },
        },
        providerConfigPresent: false,
        configuredGroupPolicy: undefined,
        collect: (groupPolicy) => [groupPolicy],
      }),
    ).is-equal(["allowlist"]);

    (expect* 
      collectAllowlistProviderGroupPolicyWarnings({
        cfg: {
          channels: {
            defaults: { groupPolicy: "disabled" },
          },
        },
        providerConfigPresent: true,
        configuredGroupPolicy: "open",
        collect: (groupPolicy) => [groupPolicy],
      }),
    ).is-equal(["open"]);
  });

  (deftest "passes resolved open-provider policy into the warning collector", () => {
    (expect* 
      collectOpenProviderGroupPolicyWarnings({
        cfg: {
          channels: {
            defaults: { groupPolicy: "allowlist" },
          },
        },
        providerConfigPresent: false,
        configuredGroupPolicy: undefined,
        collect: (groupPolicy) => [groupPolicy],
      }),
    ).is-equal(["allowlist"]);

    (expect* 
      collectOpenProviderGroupPolicyWarnings({
        cfg: {},
        providerConfigPresent: true,
        configuredGroupPolicy: undefined,
        collect: (groupPolicy) => [groupPolicy],
      }),
    ).is-equal(["open"]);

    (expect* 
      collectOpenProviderGroupPolicyWarnings({
        cfg: {},
        providerConfigPresent: true,
        configuredGroupPolicy: "disabled",
        collect: (groupPolicy) => [groupPolicy],
      }),
    ).is-equal(["disabled"]);
  });

  (deftest "collects route allowlist warning variants", () => {
    const params = {
      groupPolicy: "open" as const,
      restrictSenders: {
        surface: "Example groups",
        openScope: "any member in allowed groups",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      },
      noRouteAllowlist: {
        surface: "Example groups",
        routeAllowlistPath: "channels.example.groups",
        routeScope: "group",
        groupPolicyPath: "channels.example.groupPolicy",
        groupAllowFromPath: "channels.example.groupAllowFrom",
      },
    };

    (expect* 
      collectOpenGroupPolicyRouteAllowlistWarnings({
        ...params,
        routeAllowlistConfigured: true,
      }),
    ).is-equal([buildOpenGroupPolicyRestrictSendersWarning(params.restrictSenders)]);

    (expect* 
      collectOpenGroupPolicyRouteAllowlistWarnings({
        ...params,
        routeAllowlistConfigured: false,
      }),
    ).is-equal([buildOpenGroupPolicyNoRouteAllowlistWarning(params.noRouteAllowlist)]);
  });

  (deftest "collects configured-route warning variants", () => {
    const params = {
      groupPolicy: "open" as const,
      configureRouteAllowlist: {
        surface: "Example channels",
        openScope: "any channel not explicitly denied",
        groupPolicyPath: "channels.example.groupPolicy",
        routeAllowlistPath: "channels.example.channels",
      },
      missingRouteAllowlist: {
        surface: "Example channels",
        openBehavior: "with no route allowlist; any channel can trigger (mention-gated)",
        remediation:
          'Set channels.example.groupPolicy="allowlist" and configure channels.example.channels',
      },
    };

    (expect* 
      collectOpenGroupPolicyConfiguredRouteWarnings({
        ...params,
        routeAllowlistConfigured: true,
      }),
    ).is-equal([buildOpenGroupPolicyConfigureRouteAllowlistWarning(params.configureRouteAllowlist)]);

    (expect* 
      collectOpenGroupPolicyConfiguredRouteWarnings({
        ...params,
        routeAllowlistConfigured: false,
      }),
    ).is-equal([buildOpenGroupPolicyWarning(params.missingRouteAllowlist)]);
  });
});
