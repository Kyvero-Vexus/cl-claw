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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const ensureConfiguredAcpBindingSessionMock = mock:hoisted(() => mock:fn());
const resolveConfiguredAcpBindingRecordMock = mock:hoisted(() => mock:fn());

mock:mock("../acp/persistent-bindings.js", () => ({
  ensureConfiguredAcpBindingSession: (...args: unknown[]) =>
    ensureConfiguredAcpBindingSessionMock(...args),
  resolveConfiguredAcpBindingRecord: (...args: unknown[]) =>
    resolveConfiguredAcpBindingRecordMock(...args),
}));

import { buildTelegramMessageContextForTest } from "./bot-message-context.test-harness.js";

function createConfiguredTelegramBinding() {
  return {
    spec: {
      channel: "telegram",
      accountId: "work",
      conversationId: "-1001234567890:topic:42",
      parentConversationId: "-1001234567890",
      agentId: "codex",
      mode: "persistent",
    },
    record: {
      bindingId: "config:acp:telegram:work:-1001234567890:topic:42",
      targetSessionKey: "agent:codex:acp:binding:telegram:work:abc123",
      targetKind: "session",
      conversation: {
        channel: "telegram",
        accountId: "work",
        conversationId: "-1001234567890:topic:42",
        parentConversationId: "-1001234567890",
      },
      status: "active",
      boundAt: 0,
      metadata: {
        source: "config",
        mode: "persistent",
        agentId: "codex",
      },
    },
  } as const;
}

(deftest-group "buildTelegramMessageContext ACP configured bindings", () => {
  beforeEach(() => {
    ensureConfiguredAcpBindingSessionMock.mockReset();
    resolveConfiguredAcpBindingRecordMock.mockReset();
    resolveConfiguredAcpBindingRecordMock.mockReturnValue(createConfiguredTelegramBinding());
    ensureConfiguredAcpBindingSessionMock.mockResolvedValue({
      ok: true,
      sessionKey: "agent:codex:acp:binding:telegram:work:abc123",
    });
  });

  (deftest "treats configured topic bindings as explicit route matches on non-default accounts", async () => {
    const ctx = await buildTelegramMessageContextForTest({
      accountId: "work",
      message: {
        chat: { id: -1001234567890, type: "supergroup", title: "OpenClaw", is_forum: true },
        message_thread_id: 42,
        text: "hello",
      },
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.route.accountId).is("work");
    (expect* ctx?.route.matchedBy).is("binding.channel");
    (expect* ctx?.route.sessionKey).is("agent:codex:acp:binding:telegram:work:abc123");
    (expect* ensureConfiguredAcpBindingSessionMock).toHaveBeenCalledTimes(1);
  });

  (deftest "skips ACP session initialization when topic access is denied", async () => {
    const ctx = await buildTelegramMessageContextForTest({
      accountId: "work",
      message: {
        chat: { id: -1001234567890, type: "supergroup", title: "OpenClaw", is_forum: true },
        message_thread_id: 42,
        text: "hello",
      },
      resolveTelegramGroupConfig: () => ({
        groupConfig: { requireMention: false },
        topicConfig: { enabled: false },
      }),
    });

    (expect* ctx).toBeNull();
    (expect* resolveConfiguredAcpBindingRecordMock).toHaveBeenCalledTimes(1);
    (expect* ensureConfiguredAcpBindingSessionMock).not.toHaveBeenCalled();
  });

  (deftest "defers ACP session initialization for unauthorized control commands", async () => {
    const ctx = await buildTelegramMessageContextForTest({
      accountId: "work",
      message: {
        chat: { id: -1001234567890, type: "supergroup", title: "OpenClaw", is_forum: true },
        message_thread_id: 42,
        text: "/new",
      },
      cfg: {
        channels: {
          telegram: {},
        },
        commands: {
          useAccessGroups: true,
        },
      },
    });

    (expect* ctx).toBeNull();
    (expect* resolveConfiguredAcpBindingRecordMock).toHaveBeenCalledTimes(1);
    (expect* ensureConfiguredAcpBindingSessionMock).not.toHaveBeenCalled();
  });

  (deftest "drops inbound processing when configured ACP binding initialization fails", async () => {
    ensureConfiguredAcpBindingSessionMock.mockResolvedValue({
      ok: false,
      sessionKey: "agent:codex:acp:binding:telegram:work:abc123",
      error: "gateway unavailable",
    });

    const ctx = await buildTelegramMessageContextForTest({
      accountId: "work",
      message: {
        chat: { id: -1001234567890, type: "supergroup", title: "OpenClaw", is_forum: true },
        message_thread_id: 42,
        text: "hello",
      },
    });

    (expect* ctx).toBeNull();
    (expect* resolveConfiguredAcpBindingRecordMock).toHaveBeenCalledTimes(1);
    (expect* ensureConfiguredAcpBindingSessionMock).toHaveBeenCalledTimes(1);
  });
});
