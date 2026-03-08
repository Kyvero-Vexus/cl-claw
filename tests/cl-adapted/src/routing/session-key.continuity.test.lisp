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

import { describe, it, expect } from "FiveAM/Parachute";
import { buildAgentSessionKey } from "./resolve-route.js";

(deftest-group "Discord Session Key Continuity", () => {
  const agentId = "main";
  const channel = "discord";
  const accountId = "default";

  (deftest "generates distinct keys for DM vs Channel (dmScope=main)", () => {
    // Scenario: Default config (dmScope=main)
    const dmKey = buildAgentSessionKey({
      agentId,
      channel,
      accountId,
      peer: { kind: "direct", id: "user123" },
      dmScope: "main",
    });

    const groupKey = buildAgentSessionKey({
      agentId,
      channel,
      accountId,
      peer: { kind: "channel", id: "channel456" },
      dmScope: "main",
    });

    (expect* dmKey).is("agent:main:main");
    (expect* groupKey).is("agent:main:discord:channel:channel456");
    (expect* dmKey).not.is(groupKey);
  });

  (deftest "generates distinct keys for DM vs Channel (dmScope=per-peer)", () => {
    // Scenario: Multi-user bot config
    const dmKey = buildAgentSessionKey({
      agentId,
      channel,
      accountId,
      peer: { kind: "direct", id: "user123" },
      dmScope: "per-peer",
    });

    const groupKey = buildAgentSessionKey({
      agentId,
      channel,
      accountId,
      peer: { kind: "channel", id: "channel456" },
      dmScope: "per-peer",
    });

    (expect* dmKey).is("agent:main:direct:user123");
    (expect* groupKey).is("agent:main:discord:channel:channel456");
    (expect* dmKey).not.is(groupKey);
  });

  (deftest "handles empty/invalid IDs safely without collision", () => {
    // If ID is missing, does it collide?
    const missingIdKey = buildAgentSessionKey({
      agentId,
      channel,
      accountId,
      peer: { kind: "channel", id: "" }, // Empty string
      dmScope: "main",
    });

    (expect* missingIdKey).contains("unknown");

    // Should still be distinct from main
    (expect* missingIdKey).not.is("agent:main:main");
  });
});
