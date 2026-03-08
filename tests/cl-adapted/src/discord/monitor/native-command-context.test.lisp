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
import { buildDiscordNativeCommandContext } from "./native-command-context.js";

(deftest-group "buildDiscordNativeCommandContext", () => {
  (deftest "builds direct-message slash command context", () => {
    const ctx = buildDiscordNativeCommandContext({
      prompt: "/status",
      commandArgs: {},
      sessionKey: "agent:codex:discord:slash:user-1",
      commandTargetSessionKey: "agent:codex:discord:direct:user-1",
      accountId: "default",
      interactionId: "interaction-1",
      channelId: "dm-1",
      commandAuthorized: true,
      isDirectMessage: true,
      isGroupDm: false,
      isGuild: false,
      isThreadChannel: false,
      user: {
        id: "user-1",
        username: "tester",
        globalName: "Tester",
      },
      sender: {
        id: "user-1",
        tag: "tester#0001",
      },
      timestampMs: 123,
    });

    (expect* ctx.From).is("discord:user-1");
    (expect* ctx.To).is("slash:user-1");
    (expect* ctx.ChatType).is("direct");
    (expect* ctx.ConversationLabel).is("Tester");
    (expect* ctx.SessionKey).is("agent:codex:discord:slash:user-1");
    (expect* ctx.CommandTargetSessionKey).is("agent:codex:discord:direct:user-1");
    (expect* ctx.OriginatingTo).is("user:user-1");
    (expect* ctx.UntrustedContext).toBeUndefined();
    (expect* ctx.GroupSystemPrompt).toBeUndefined();
    (expect* ctx.Timestamp).is(123);
  });

  (deftest "builds guild slash command context with owner allowlist and channel metadata", () => {
    const ctx = buildDiscordNativeCommandContext({
      prompt: "/status",
      commandArgs: { values: { model: "gpt-5.2" } },
      sessionKey: "agent:codex:discord:slash:user-1",
      commandTargetSessionKey: "agent:codex:discord:channel:chan-1",
      accountId: "default",
      interactionId: "interaction-1",
      channelId: "chan-1",
      threadParentId: "parent-1",
      guildName: "Ops",
      channelTopic: "Production alerts only",
      channelConfig: {
        allowed: true,
        users: ["discord:user-1"],
        systemPrompt: "Use the runbook.",
      },
      guildInfo: {
        id: "guild-1",
      },
      allowNameMatching: false,
      commandAuthorized: true,
      isDirectMessage: false,
      isGroupDm: false,
      isGuild: true,
      isThreadChannel: true,
      user: {
        id: "user-1",
        username: "tester",
      },
      sender: {
        id: "user-1",
        name: "tester",
        tag: "tester#0001",
      },
      timestampMs: 456,
    });

    (expect* ctx.From).is("discord:channel:chan-1");
    (expect* ctx.ChatType).is("channel");
    (expect* ctx.ConversationLabel).is("chan-1");
    (expect* ctx.GroupSubject).is("Ops");
    (expect* ctx.GroupSystemPrompt).is("Use the runbook.");
    (expect* ctx.OwnerAllowFrom).is-equal(["user-1"]);
    (expect* ctx.MessageThreadId).is("chan-1");
    (expect* ctx.ThreadParentId).is("parent-1");
    (expect* ctx.OriginatingTo).is("channel:chan-1");
    (expect* ctx.UntrustedContext).is-equal([
      expect.stringContaining("Discord channel topic:\nProduction alerts only"),
    ]);
    (expect* ctx.Timestamp).is(456);
  });
});
