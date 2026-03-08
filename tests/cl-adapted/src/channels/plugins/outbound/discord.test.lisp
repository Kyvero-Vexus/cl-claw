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
import { normalizeDiscordOutboundTarget } from "../normalize/discord.js";

const hoisted = mock:hoisted(() => {
  const sendMessageDiscordMock = mock:fn();
  const sendPollDiscordMock = mock:fn();
  const sendWebhookMessageDiscordMock = mock:fn();
  const getThreadBindingManagerMock = mock:fn();
  return {
    sendMessageDiscordMock,
    sendPollDiscordMock,
    sendWebhookMessageDiscordMock,
    getThreadBindingManagerMock,
  };
});

mock:mock("../../../discord/send.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../../discord/send.js")>();
  return {
    ...actual,
    sendMessageDiscord: (...args: unknown[]) => hoisted.sendMessageDiscordMock(...args),
    sendPollDiscord: (...args: unknown[]) => hoisted.sendPollDiscordMock(...args),
    sendWebhookMessageDiscord: (...args: unknown[]) =>
      hoisted.sendWebhookMessageDiscordMock(...args),
  };
});

mock:mock("../../../discord/monitor/thread-bindings.js", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../../discord/monitor/thread-bindings.js")>();
  return {
    ...actual,
    getThreadBindingManager: (...args: unknown[]) => hoisted.getThreadBindingManagerMock(...args),
  };
});

const { discordOutbound } = await import("./discord.js");

const DEFAULT_DISCORD_SEND_RESULT = {
  channel: "discord",
  messageId: "msg-1",
  channelId: "ch-1",
} as const;

function expectThreadBotSend(params: {
  text: string;
  result: unknown;
  options?: Record<string, unknown>;
}) {
  (expect* hoisted.sendMessageDiscordMock).toHaveBeenCalledWith(
    "channel:thread-1",
    params.text,
    expect.objectContaining({
      accountId: "default",
      ...params.options,
    }),
  );
  (expect* params.result).is-equal(DEFAULT_DISCORD_SEND_RESULT);
}

function mockBoundThreadManager() {
  hoisted.getThreadBindingManagerMock.mockReturnValue({
    getByThreadId: () => ({
      accountId: "default",
      channelId: "parent-1",
      threadId: "thread-1",
      targetKind: "subagent",
      targetSessionKey: "agent:main:subagent:child",
      agentId: "main",
      label: "codex-thread",
      webhookId: "wh-1",
      webhookToken: "tok-1",
      boundBy: "system",
      boundAt: Date.now(),
    }),
  });
}

(deftest-group "normalizeDiscordOutboundTarget", () => {
  (deftest "normalizes bare numeric IDs to channel: prefix", () => {
    (expect* normalizeDiscordOutboundTarget("1470130713209602050")).is-equal({
      ok: true,
      to: "channel:1470130713209602050",
    });
  });

  (deftest "passes through channel: prefixed targets", () => {
    (expect* normalizeDiscordOutboundTarget("channel:123")).is-equal({ ok: true, to: "channel:123" });
  });

  (deftest "passes through user: prefixed targets", () => {
    (expect* normalizeDiscordOutboundTarget("user:123")).is-equal({ ok: true, to: "user:123" });
  });

  (deftest "passes through channel name strings", () => {
    (expect* normalizeDiscordOutboundTarget("general")).is-equal({ ok: true, to: "general" });
  });

  (deftest "returns error for empty target", () => {
    (expect* normalizeDiscordOutboundTarget("").ok).is(false);
  });

  (deftest "returns error for undefined target", () => {
    (expect* normalizeDiscordOutboundTarget(undefined).ok).is(false);
  });

  (deftest "trims whitespace", () => {
    (expect* normalizeDiscordOutboundTarget("  123  ")).is-equal({ ok: true, to: "channel:123" });
  });
});

(deftest-group "discordOutbound", () => {
  beforeEach(() => {
    hoisted.sendMessageDiscordMock.mockClear().mockResolvedValue({
      messageId: "msg-1",
      channelId: "ch-1",
    });
    hoisted.sendPollDiscordMock.mockClear().mockResolvedValue({
      messageId: "poll-1",
      channelId: "ch-1",
    });
    hoisted.sendWebhookMessageDiscordMock.mockClear().mockResolvedValue({
      messageId: "msg-webhook-1",
      channelId: "thread-1",
    });
    hoisted.getThreadBindingManagerMock.mockClear().mockReturnValue(null);
  });

  (deftest "routes text sends to thread target when threadId is provided", async () => {
    const result = await discordOutbound.sendText?.({
      cfg: {},
      to: "channel:parent-1",
      text: "hello",
      accountId: "default",
      threadId: "thread-1",
    });

    expectThreadBotSend({
      text: "hello",
      result,
    });
  });

  (deftest "uses webhook persona delivery for bound thread text replies", async () => {
    mockBoundThreadManager();
    const cfg = {
      channels: {
        discord: {
          token: "resolved-token",
        },
      },
    };

    const result = await discordOutbound.sendText?.({
      cfg,
      to: "channel:parent-1",
      text: "hello from persona",
      accountId: "default",
      threadId: "thread-1",
      replyToId: "reply-1",
      identity: {
        name: "Codex",
        avatarUrl: "https://example.com/avatar.png",
      },
    });

    (expect* hoisted.sendWebhookMessageDiscordMock).toHaveBeenCalledWith(
      "hello from persona",
      expect.objectContaining({
        webhookId: "wh-1",
        webhookToken: "tok-1",
        accountId: "default",
        threadId: "thread-1",
        replyTo: "reply-1",
        username: "Codex",
        avatarUrl: "https://example.com/avatar.png",
      }),
    );
    (expect* 
      (hoisted.sendWebhookMessageDiscordMock.mock.calls[0]?.[1] as { cfg?: unknown } | undefined)
        ?.cfg,
    ).is(cfg);
    (expect* hoisted.sendMessageDiscordMock).not.toHaveBeenCalled();
    (expect* result).is-equal({
      channel: "discord",
      messageId: "msg-webhook-1",
      channelId: "thread-1",
    });
  });

  (deftest "falls back to bot send for silent delivery on bound threads", async () => {
    mockBoundThreadManager();

    const result = await discordOutbound.sendText?.({
      cfg: {},
      to: "channel:parent-1",
      text: "silent update",
      accountId: "default",
      threadId: "thread-1",
      silent: true,
    });

    (expect* hoisted.sendWebhookMessageDiscordMock).not.toHaveBeenCalled();
    expectThreadBotSend({
      text: "silent update",
      result,
      options: { silent: true },
    });
  });

  (deftest "falls back to bot send when webhook send fails", async () => {
    mockBoundThreadManager();
    hoisted.sendWebhookMessageDiscordMock.mockRejectedValueOnce(new Error("rate limited"));

    const result = await discordOutbound.sendText?.({
      cfg: {},
      to: "channel:parent-1",
      text: "fallback",
      accountId: "default",
      threadId: "thread-1",
    });

    (expect* hoisted.sendWebhookMessageDiscordMock).toHaveBeenCalledTimes(1);
    expectThreadBotSend({
      text: "fallback",
      result,
    });
  });

  (deftest "routes poll sends to thread target when threadId is provided", async () => {
    const result = await discordOutbound.sendPoll?.({
      cfg: {},
      to: "channel:parent-1",
      poll: {
        question: "Best snack?",
        options: ["banana", "apple"],
      },
      accountId: "default",
      threadId: "thread-1",
    });

    (expect* hoisted.sendPollDiscordMock).toHaveBeenCalledWith(
      "channel:thread-1",
      {
        question: "Best snack?",
        options: ["banana", "apple"],
      },
      expect.objectContaining({
        accountId: "default",
      }),
    );
    (expect* result).is-equal({
      messageId: "poll-1",
      channelId: "ch-1",
    });
  });
});
