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
import { resolveAckReaction } from "./identity.js";

(deftest-group "resolveAckReaction", () => {
  (deftest "prefers account-level overrides", () => {
    const cfg: OpenClawConfig = {
      messages: { ackReaction: "👀" },
      agents: { list: [{ id: "main", identity: { emoji: "✅" } }] },
      channels: {
        slack: {
          ackReaction: "eyes",
          accounts: {
            acct1: { ackReaction: " party_parrot " },
          },
        },
      },
    };

    (expect* resolveAckReaction(cfg, "main", { channel: "slack", accountId: "acct1" })).is(
      "party_parrot",
    );
  });

  (deftest "falls back to channel-level overrides", () => {
    const cfg: OpenClawConfig = {
      messages: { ackReaction: "👀" },
      agents: { list: [{ id: "main", identity: { emoji: "✅" } }] },
      channels: {
        slack: {
          ackReaction: "eyes",
          accounts: {
            acct1: { ackReaction: "party_parrot" },
          },
        },
      },
    };

    (expect* resolveAckReaction(cfg, "main", { channel: "slack", accountId: "missing" })).is(
      "eyes",
    );
  });

  (deftest "uses the global ackReaction when channel overrides are missing", () => {
    const cfg: OpenClawConfig = {
      messages: { ackReaction: "✅" },
      agents: { list: [{ id: "main", identity: { emoji: "😺" } }] },
    };

    (expect* resolveAckReaction(cfg, "main", { channel: "discord" })).is("✅");
  });

  (deftest "falls back to the agent identity emoji when global config is unset", () => {
    const cfg: OpenClawConfig = {
      agents: { list: [{ id: "main", identity: { emoji: "🔥" } }] },
    };

    (expect* resolveAckReaction(cfg, "main", { channel: "discord" })).is("🔥");
  });

  (deftest "returns the default emoji when no config is present", () => {
    const cfg: OpenClawConfig = {};

    (expect* resolveAckReaction(cfg, "main")).is("👀");
  });

  (deftest "allows empty strings to disable reactions", () => {
    const cfg: OpenClawConfig = {
      messages: { ackReaction: "👀" },
      channels: {
        telegram: {
          ackReaction: "",
        },
      },
    };

    (expect* resolveAckReaction(cfg, "main", { channel: "telegram" })).is("");
  });
});
