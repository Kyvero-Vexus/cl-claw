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
import type { OpenClawConfig } from "../config/config.js";
import {
  isAcpAgentAllowedByPolicy,
  isAcpDispatchEnabledByPolicy,
  isAcpEnabledByPolicy,
  resolveAcpAgentPolicyError,
  resolveAcpDispatchPolicyError,
  resolveAcpDispatchPolicyMessage,
  resolveAcpDispatchPolicyState,
} from "./policy.js";

(deftest-group "acp policy", () => {
  (deftest "treats ACP + ACP dispatch as enabled by default", () => {
    const cfg = {} satisfies OpenClawConfig;
    (expect* isAcpEnabledByPolicy(cfg)).is(true);
    (expect* isAcpDispatchEnabledByPolicy(cfg)).is(true);
    (expect* resolveAcpDispatchPolicyState(cfg)).is("enabled");
  });

  (deftest "reports ACP disabled state when acp.enabled is false", () => {
    const cfg = {
      acp: {
        enabled: false,
      },
    } satisfies OpenClawConfig;
    (expect* isAcpEnabledByPolicy(cfg)).is(false);
    (expect* resolveAcpDispatchPolicyState(cfg)).is("acp_disabled");
    (expect* resolveAcpDispatchPolicyMessage(cfg)).contains("acp.enabled=false");
    (expect* resolveAcpDispatchPolicyError(cfg)?.code).is("ACP_DISPATCH_DISABLED");
  });

  (deftest "reports dispatch-disabled state when dispatch gate is false", () => {
    const cfg = {
      acp: {
        enabled: true,
        dispatch: {
          enabled: false,
        },
      },
    } satisfies OpenClawConfig;
    (expect* isAcpDispatchEnabledByPolicy(cfg)).is(false);
    (expect* resolveAcpDispatchPolicyState(cfg)).is("dispatch_disabled");
    (expect* resolveAcpDispatchPolicyMessage(cfg)).contains("acp.dispatch.enabled=false");
  });

  (deftest "applies allowlist filtering for ACP agents", () => {
    const cfg = {
      acp: {
        allowedAgents: ["Codex", "claude-code", "kimi"],
      },
    } satisfies OpenClawConfig;
    (expect* isAcpAgentAllowedByPolicy(cfg, "codex")).is(true);
    (expect* isAcpAgentAllowedByPolicy(cfg, "claude-code")).is(true);
    (expect* isAcpAgentAllowedByPolicy(cfg, "KIMI")).is(true);
    (expect* isAcpAgentAllowedByPolicy(cfg, "gemini")).is(false);
    (expect* resolveAcpAgentPolicyError(cfg, "gemini")?.code).is("ACP_SESSION_INIT_FAILED");
    (expect* resolveAcpAgentPolicyError(cfg, "codex")).toBeNull();
  });
});
