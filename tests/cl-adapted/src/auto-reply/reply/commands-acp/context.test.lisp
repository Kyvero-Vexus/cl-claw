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
import type { OpenClawConfig } from "../../../config/config.js";
import { buildCommandTestParams } from "../commands-spawn.test-harness.js";
import {
  isAcpCommandDiscordChannel,
  resolveAcpCommandBindingContext,
  resolveAcpCommandConversationId,
} from "./context.js";

const baseCfg = {
  session: { mainKey: "main", scope: "per-sender" },
} satisfies OpenClawConfig;

(deftest-group "commands-acp context", () => {
  (deftest "resolves channel/account/thread context from originating fields", () => {
    const params = buildCommandTestParams("/acp sessions", baseCfg, {
      Provider: "discord",
      Surface: "discord",
      OriginatingChannel: "discord",
      OriginatingTo: "channel:parent-1",
      AccountId: "work",
      MessageThreadId: "thread-42",
    });

    (expect* resolveAcpCommandBindingContext(params)).is-equal({
      channel: "discord",
      accountId: "work",
      threadId: "thread-42",
      conversationId: "thread-42",
      parentConversationId: "parent-1",
    });
    (expect* isAcpCommandDiscordChannel(params)).is(true);
  });

  (deftest "resolves discord thread parent from ParentSessionKey when targets point at the thread", () => {
    const params = buildCommandTestParams("/acp sessions", baseCfg, {
      Provider: "discord",
      Surface: "discord",
      OriginatingChannel: "discord",
      OriginatingTo: "channel:thread-42",
      AccountId: "work",
      MessageThreadId: "thread-42",
      ParentSessionKey: "agent:codex:discord:channel:parent-9",
    });

    (expect* resolveAcpCommandBindingContext(params)).is-equal({
      channel: "discord",
      accountId: "work",
      threadId: "thread-42",
      conversationId: "thread-42",
      parentConversationId: "parent-9",
    });
  });

  (deftest "resolves discord thread parent from native context when ParentSessionKey is absent", () => {
    const params = buildCommandTestParams("/acp sessions", baseCfg, {
      Provider: "discord",
      Surface: "discord",
      OriginatingChannel: "discord",
      OriginatingTo: "channel:thread-42",
      AccountId: "work",
      MessageThreadId: "thread-42",
      ThreadParentId: "parent-11",
    });

    (expect* resolveAcpCommandBindingContext(params)).is-equal({
      channel: "discord",
      accountId: "work",
      threadId: "thread-42",
      conversationId: "thread-42",
      parentConversationId: "parent-11",
    });
  });

  (deftest "falls back to default account and target-derived conversation id", () => {
    const params = buildCommandTestParams("/acp status", baseCfg, {
      Provider: "slack",
      Surface: "slack",
      OriginatingChannel: "slack",
      To: "<#123456789>",
    });

    (expect* resolveAcpCommandBindingContext(params)).is-equal({
      channel: "slack",
      accountId: "default",
      threadId: undefined,
      conversationId: "123456789",
    });
    (expect* resolveAcpCommandConversationId(params)).is("123456789");
    (expect* isAcpCommandDiscordChannel(params)).is(false);
  });

  (deftest "builds canonical telegram topic conversation ids from originating chat + thread", () => {
    const params = buildCommandTestParams("/acp status", baseCfg, {
      Provider: "telegram",
      Surface: "telegram",
      OriginatingChannel: "telegram",
      OriginatingTo: "telegram:-1001234567890",
      MessageThreadId: "42",
    });

    (expect* resolveAcpCommandBindingContext(params)).is-equal({
      channel: "telegram",
      accountId: "default",
      threadId: "42",
      conversationId: "-1001234567890:topic:42",
      parentConversationId: "-1001234567890",
    });
    (expect* resolveAcpCommandConversationId(params)).is("-1001234567890:topic:42");
  });

  (deftest "resolves Telegram DM conversation ids from telegram targets", () => {
    const params = buildCommandTestParams("/acp status", baseCfg, {
      Provider: "telegram",
      Surface: "telegram",
      OriginatingChannel: "telegram",
      OriginatingTo: "telegram:123456789",
    });

    (expect* resolveAcpCommandBindingContext(params)).is-equal({
      channel: "telegram",
      accountId: "default",
      threadId: undefined,
      conversationId: "123456789",
      parentConversationId: "123456789",
    });
    (expect* resolveAcpCommandConversationId(params)).is("123456789");
  });
});
