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
  buildDiscordGroupSystemPrompt,
  buildDiscordInboundAccessContext,
  buildDiscordUntrustedContext,
} from "./inbound-context.js";

(deftest-group "Discord inbound context helpers", () => {
  (deftest "builds guild access context from channel config and topic", () => {
    (expect* 
      buildDiscordInboundAccessContext({
        channelConfig: {
          allowed: true,
          users: ["discord:user-1"],
          systemPrompt: "Use the runbook.",
        },
        guildInfo: { id: "guild-1" },
        sender: {
          id: "user-1",
          name: "tester",
          tag: "tester#0001",
        },
        isGuild: true,
        channelTopic: "Production alerts only",
      }),
    ).is-equal({
      groupSystemPrompt: "Use the runbook.",
      untrustedContext: [expect.stringContaining("Production alerts only")],
      ownerAllowFrom: ["user-1"],
    });
  });

  (deftest "omits guild-only metadata for direct messages", () => {
    (expect* 
      buildDiscordInboundAccessContext({
        sender: {
          id: "user-1",
        },
        isGuild: false,
        channelTopic: "ignored",
      }),
    ).is-equal({
      groupSystemPrompt: undefined,
      untrustedContext: undefined,
      ownerAllowFrom: undefined,
    });
  });

  (deftest "keeps direct helper behavior consistent", () => {
    (expect* buildDiscordGroupSystemPrompt({ allowed: true, systemPrompt: "  hi  " })).is("hi");
    (expect* buildDiscordUntrustedContext({ isGuild: true, channelTopic: "topic" })).is-equal([
      expect.stringContaining("topic"),
    ]);
  });
});
