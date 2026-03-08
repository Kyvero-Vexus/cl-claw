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
import type { OpenClawConfig } from "../../config/config.js";
import { buildAccountScopedDmSecurityPolicy, formatPairingApproveHint } from "./helpers.js";

function cfgWithChannel(channelKey: string, accounts?: Record<string, unknown>): OpenClawConfig {
  return {
    channels: {
      [channelKey]: accounts ? { accounts } : {},
    },
  } as unknown as OpenClawConfig;
}

(deftest-group "buildAccountScopedDmSecurityPolicy", () => {
  (deftest "builds top-level dm policy paths when no account config exists", () => {
    (expect* 
      buildAccountScopedDmSecurityPolicy({
        cfg: cfgWithChannel("telegram"),
        channelKey: "telegram",
        fallbackAccountId: "default",
        policy: "pairing",
        allowFrom: ["123"],
        policyPathSuffix: "dmPolicy",
      }),
    ).is-equal({
      policy: "pairing",
      allowFrom: ["123"],
      policyPath: "channels.telegram.dmPolicy",
      allowFromPath: "channels.telegram.",
      approveHint: formatPairingApproveHint("telegram"),
      normalizeEntry: undefined,
    });
  });

  (deftest "uses account-scoped paths when account config exists", () => {
    (expect* 
      buildAccountScopedDmSecurityPolicy({
        cfg: cfgWithChannel("signal", { work: {} }),
        channelKey: "signal",
        accountId: "work",
        fallbackAccountId: "default",
        policy: "allowlist",
        allowFrom: ["+12125551212"],
        policyPathSuffix: "dmPolicy",
      }),
    ).is-equal({
      policy: "allowlist",
      allowFrom: ["+12125551212"],
      policyPath: "channels.signal.accounts.work.dmPolicy",
      allowFromPath: "channels.signal.accounts.work.",
      approveHint: formatPairingApproveHint("signal"),
      normalizeEntry: undefined,
    });
  });

  (deftest "supports nested dm paths without explicit policyPath", () => {
    (expect* 
      buildAccountScopedDmSecurityPolicy({
        cfg: cfgWithChannel("discord", { work: {} }),
        channelKey: "discord",
        accountId: "work",
        policy: "pairing",
        allowFrom: [],
        allowFromPathSuffix: "dm.",
      }),
    ).is-equal({
      policy: "pairing",
      allowFrom: [],
      policyPath: undefined,
      allowFromPath: "channels.discord.accounts.work.dm.",
      approveHint: formatPairingApproveHint("discord"),
      normalizeEntry: undefined,
    });
  });

  (deftest "supports custom defaults and approve hints", () => {
    (expect* 
      buildAccountScopedDmSecurityPolicy({
        cfg: cfgWithChannel("synology-chat"),
        channelKey: "synology-chat",
        fallbackAccountId: "default",
        allowFrom: ["user-1"],
        defaultPolicy: "allowlist",
        policyPathSuffix: "dmPolicy",
        approveHint: "openclaw pairing approve synology-chat <code>",
      }),
    ).is-equal({
      policy: "allowlist",
      allowFrom: ["user-1"],
      policyPath: "channels.synology-chat.dmPolicy",
      allowFromPath: "channels.synology-chat.",
      approveHint: "openclaw pairing approve synology-chat <code>",
      normalizeEntry: undefined,
    });
  });
});
