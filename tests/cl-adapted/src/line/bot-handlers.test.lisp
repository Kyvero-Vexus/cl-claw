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

import type { MessageEvent, PostbackEvent } from "@line/bot-sdk";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

// Avoid pulling in globals/pairing/media dependencies; this suite only asserts
// allowlist/groupPolicy gating and message-context wiring.
mock:mock("../globals.js", () => ({
  danger: (text: string) => text,
  logVerbose: () => {},
  shouldLogVerbose: () => false,
}));

mock:mock("../pairing/pairing-labels.js", () => ({
  resolvePairingIdLabel: () => "lineUserId",
}));

mock:mock("../pairing/pairing-messages.js", () => ({
  buildPairingReply: () => "pairing-reply",
}));

mock:mock("./download.js", () => ({
  downloadLineMedia: async () => {
    error("downloadLineMedia should not be called from bot-handlers tests");
  },
}));

mock:mock("./send.js", () => ({
  pushMessageLine: async () => {
    error("pushMessageLine should not be called from bot-handlers tests");
  },
  replyMessageLine: async () => {
    error("replyMessageLine should not be called from bot-handlers tests");
  },
}));

const { buildLineMessageContextMock, buildLinePostbackContextMock } = mock:hoisted(() => ({
  buildLineMessageContextMock: mock:fn(async () => ({
    ctxPayload: { From: "line:group:group-1" },
    replyToken: "reply-token",
    route: { agentId: "default" },
    isGroup: true,
    accountId: "default",
  })),
  buildLinePostbackContextMock: mock:fn(async () => null as unknown),
}));

mock:mock("./bot-message-context.js", () => ({
  buildLineMessageContext: buildLineMessageContextMock,
  buildLinePostbackContext: buildLinePostbackContextMock,
  getLineSourceInfo: (source: {
    type?: string;
    userId?: string;
    groupId?: string;
    roomId?: string;
  }) => ({
    userId: source.userId,
    groupId: source.type === "group" ? source.groupId : undefined,
    roomId: source.type === "room" ? source.roomId : undefined,
    isGroup: source.type === "group" || source.type === "room",
  }),
}));

const { readAllowFromStoreMock, upsertPairingRequestMock } = mock:hoisted(() => ({
  readAllowFromStoreMock: mock:fn(async () => [] as string[]),
  upsertPairingRequestMock: mock:fn(async () => ({ code: "CODE", created: true })),
}));

let handleLineWebhookEvents: typeof import("./bot-handlers.js").handleLineWebhookEvents;
let createLineWebhookReplayCache: typeof import("./bot-handlers.js").createLineWebhookReplayCache;
type LineWebhookContext = Parameters<typeof import("./bot-handlers.js").handleLineWebhookEvents>[1];

const createRuntime = () => ({ log: mock:fn(), error: mock:fn(), exit: mock:fn() });

function createReplayMessageEvent(params: {
  messageId: string;
  groupId: string;
  userId: string;
  webhookEventId: string;
  isRedelivery: boolean;
}) {
  return {
    type: "message",
    message: { id: params.messageId, type: "text", text: "hello" },
    replyToken: "reply-token",
    timestamp: Date.now(),
    source: { type: "group", groupId: params.groupId, userId: params.userId },
    mode: "active",
    webhookEventId: params.webhookEventId,
    deliveryContext: { isRedelivery: params.isRedelivery },
  } as MessageEvent;
}

function createOpenGroupReplayContext(
  processMessage: LineWebhookContext["processMessage"],
  replayCache: ReturnType<typeof createLineWebhookReplayCache>,
): Parameters<typeof handleLineWebhookEvents>[1] {
  return {
    cfg: { channels: { line: { groupPolicy: "open" } } },
    account: {
      accountId: "default",
      enabled: true,
      channelAccessToken: "token",
      channelSecret: "secret",
      tokenSource: "config",
      config: { groupPolicy: "open", groups: { "*": { requireMention: false } } },
    },
    runtime: createRuntime(),
    mediaMaxBytes: 1,
    processMessage,
    replayCache,
  };
}

mock:mock("../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: readAllowFromStoreMock,
  upsertChannelPairingRequest: upsertPairingRequestMock,
}));

(deftest-group "handleLineWebhookEvents", () => {
  beforeAll(async () => {
    ({ handleLineWebhookEvents, createLineWebhookReplayCache } = await import("./bot-handlers.js"));
  });

  beforeEach(() => {
    buildLineMessageContextMock.mockClear();
    buildLinePostbackContextMock.mockClear();
    readAllowFromStoreMock.mockClear();
    upsertPairingRequestMock.mockClear();
  });

  (deftest "blocks group messages when groupPolicy is disabled", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m1", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1", userId: "user-1" },
      mode: "active",
      webhookEventId: "evt-1",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "disabled" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { groupPolicy: "disabled" },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
  });

  (deftest "blocks group messages when allowlist is empty", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m2", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1", userId: "user-2" },
      mode: "active",
      webhookEventId: "evt-2",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "allowlist" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { groupPolicy: "allowlist" },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
  });

  (deftest "allows group messages when sender is in groupAllowFrom", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m3", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1", userId: "user-3" },
      mode: "active",
      webhookEventId: "evt-3",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: {
        channels: { line: { groupPolicy: "allowlist", groupAllowFrom: ["user-3"] } },
      },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          groupPolicy: "allowlist",
          groupAllowFrom: ["user-3"],
          groups: { "*": { requireMention: false } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "blocks group sender not in groupAllowFrom even when sender is paired in DM store", async () => {
    readAllowFromStoreMock.mockResolvedValueOnce(["user-store"]);
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m5", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1", userId: "user-store" },
      mode: "active",
      webhookEventId: "evt-5",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: {
        channels: { line: { groupPolicy: "allowlist", groupAllowFrom: ["user-group"] } },
      },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { groupPolicy: "allowlist", groupAllowFrom: ["user-group"] },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
    (expect* readAllowFromStoreMock).toHaveBeenCalledWith("line", undefined, "default");
  });

  (deftest "blocks group messages without sender id when groupPolicy is allowlist", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m5a", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1" },
      mode: "active",
      webhookEventId: "evt-5a",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: {
        channels: { line: { groupPolicy: "allowlist", groupAllowFrom: ["user-5"] } },
      },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { groupPolicy: "allowlist", groupAllowFrom: ["user-5"] },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
  });

  (deftest "does not authorize group messages from DM pairing-store entries when group allowlist is empty", async () => {
    readAllowFromStoreMock.mockResolvedValueOnce(["user-5"]);
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m5b", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1", userId: "user-5" },
      mode: "active",
      webhookEventId: "evt-5b",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "allowlist" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          dmPolicy: "pairing",
          allowFrom: [],
          groupPolicy: "allowlist",
          groupAllowFrom: [],
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
  });

  (deftest "blocks group messages when wildcard group config disables groups", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m4", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-2", userId: "user-4" },
      mode: "active",
      webhookEventId: "evt-4",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { groupPolicy: "open", groups: { "*": { enabled: false } } },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
  });

  (deftest "scopes DM pairing requests to accountId", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m5", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "user", userId: "user-5" },
      mode: "active",
      webhookEventId: "evt-5",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { dmPolicy: "pairing" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { dmPolicy: "pairing", allowFrom: ["user-owner"] },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* upsertPairingRequestMock).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "line",
        id: "user-5",
        accountId: "default",
      }),
    );
  });

  (deftest "does not authorize DM senders from another account's pairing-store entries", async () => {
    const processMessage = mock:fn();
    readAllowFromStoreMock.mockImplementation(async (...args: unknown[]) => {
      const accountId = args[2] as string | undefined;
      if (accountId === "work") {
        return [];
      }
      return ["cross-account-user"];
    });
    upsertPairingRequestMock.mockResolvedValue({ code: "CODE", created: false });

    const event = {
      type: "message",
      message: { id: "m6", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "user", userId: "cross-account-user" },
      mode: "active",
      webhookEventId: "evt-6",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { dmPolicy: "pairing" } } },
      account: {
        accountId: "work",
        enabled: true,
        channelAccessToken: "token-work", // pragma: allowlist secret
        channelSecret: "secret-work", // pragma: allowlist secret
        tokenSource: "config",
        config: { dmPolicy: "pairing" },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* readAllowFromStoreMock).toHaveBeenCalledWith("line", undefined, "work");
    (expect* processMessage).not.toHaveBeenCalled();
    (expect* upsertPairingRequestMock).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "line",
        id: "cross-account-user",
        accountId: "work",
      }),
    );
  });

  (deftest "deduplicates replayed webhook events by webhookEventId before processing", async () => {
    const processMessage = mock:fn();
    const event = createReplayMessageEvent({
      messageId: "m-replay",
      groupId: "group-replay",
      userId: "user-replay",
      webhookEventId: "evt-replay-1",
      isRedelivery: true,
    });
    const context = createOpenGroupReplayContext(processMessage, createLineWebhookReplayCache());

    await handleLineWebhookEvents([event], context);
    await handleLineWebhookEvents([event], context);

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "skips concurrent redeliveries while the first event is still processing", async () => {
    let resolveFirst: (() => void) | undefined;
    const firstDone = new deferred-result<void>((resolve) => {
      resolveFirst = resolve;
    });
    const processMessage = mock:fn(async () => {
      await firstDone;
    });
    const event = createReplayMessageEvent({
      messageId: "m-inflight",
      groupId: "group-inflight",
      userId: "user-inflight",
      webhookEventId: "evt-inflight-1",
      isRedelivery: true,
    });
    const context = createOpenGroupReplayContext(processMessage, createLineWebhookReplayCache());

    const firstRun = handleLineWebhookEvents([event], context);
    await Promise.resolve();
    const secondRun = handleLineWebhookEvents([event], context);
    resolveFirst?.();
    await Promise.all([firstRun, secondRun]);

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "mirrors in-flight replay failures so concurrent duplicates also fail", async () => {
    let rejectFirst: ((err: Error) => void) | undefined;
    const firstDone = new deferred-result<void>((_, reject) => {
      rejectFirst = reject;
    });
    const processMessage = mock:fn(async () => {
      await firstDone;
    });
    const event = createReplayMessageEvent({
      messageId: "m-inflight-fail",
      groupId: "group-inflight",
      userId: "user-inflight",
      webhookEventId: "evt-inflight-fail-1",
      isRedelivery: true,
    });
    const context = createOpenGroupReplayContext(processMessage, createLineWebhookReplayCache());

    const firstRun = handleLineWebhookEvents([event], context);
    await Promise.resolve();
    const secondRun = handleLineWebhookEvents([event], context);
    rejectFirst?.(new Error("transient inflight failure"));

    await (expect* firstRun).rejects.signals-error("transient inflight failure");
    await (expect* secondRun).rejects.signals-error("transient inflight failure");
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "deduplicates redeliveries by LINE message id when webhookEventId changes", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m-dup-1", type: "text", text: "hello" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-dup", userId: "user-dup" },
      mode: "active",
      webhookEventId: "evt-dup-1",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    const context: Parameters<typeof handleLineWebhookEvents>[1] = {
      cfg: {
        channels: { line: { groupPolicy: "allowlist", groupAllowFrom: ["user-dup"] } },
      },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          groupPolicy: "allowlist",
          groupAllowFrom: ["user-dup"],
          groups: { "*": { requireMention: false } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
      replayCache: createLineWebhookReplayCache(),
    };

    await handleLineWebhookEvents([event], context);
    await handleLineWebhookEvents(
      [
        {
          ...event,
          webhookEventId: "evt-dup-redelivery",
          deliveryContext: { isRedelivery: true },
        } as MessageEvent,
      ],
      context,
    );

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "deduplicates postback redeliveries by webhookEventId when replyToken changes", async () => {
    const processMessage = mock:fn();
    buildLinePostbackContextMock.mockResolvedValue({
      ctxPayload: { From: "line:user:user-postback" },
      route: { agentId: "default" },
      isGroup: false,
      accountId: "default",
    });
    const event = {
      type: "postback",
      postback: { data: "action=confirm" },
      replyToken: "reply-token-1",
      timestamp: Date.now(),
      source: { type: "user", userId: "user-postback" },
      mode: "active",
      webhookEventId: "evt-postback-1",
      deliveryContext: { isRedelivery: false },
    } as PostbackEvent;

    const context: Parameters<typeof handleLineWebhookEvents>[1] = {
      cfg: { channels: { line: { dmPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { dmPolicy: "open" },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
      replayCache: createLineWebhookReplayCache(),
    };

    await handleLineWebhookEvents([event], context);
    await handleLineWebhookEvents(
      [
        {
          ...event,
          replyToken: "reply-token-2",
          deliveryContext: { isRedelivery: true },
        } as PostbackEvent,
      ],
      context,
    );

    (expect* buildLinePostbackContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "skips group messages by default when requireMention is not configured", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m-default-skip", type: "text", text: "hi there" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-default", userId: "user-default" },
      mode: "active",
      webhookEventId: "evt-default-skip",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { groupPolicy: "open" },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
  });

  (deftest "records unmentioned group messages as pending history", async () => {
    const processMessage = mock:fn();
    const groupHistories = new Map<
      string,
      import("../auto-reply/reply/history.js").HistoryEntry[]
    >();
    const event = {
      type: "message",
      message: { id: "m-hist-1", type: "text", text: "hello history" },
      replyToken: "reply-token",
      timestamp: 1700000000000,
      source: { type: "group", groupId: "group-hist-1", userId: "user-hist" },
      mode: "active",
      webhookEventId: "evt-hist-1",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: { groupPolicy: "open" },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
      groupHistories,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    const entries = groupHistories.get("group-hist-1");
    (expect* entries).has-length(1);
    (expect* entries?.[0]).matches-object({
      sender: "user:user-hist",
      body: "hello history",
      timestamp: 1700000000000,
    });
  });

  (deftest "skips group messages without mention when requireMention is set", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m-mention-1", type: "text", text: "hi there" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-mention", userId: "user-mention" },
      mode: "active",
      webhookEventId: "evt-mention-1",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          groupPolicy: "open",
          groups: { "*": { requireMention: true } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* processMessage).not.toHaveBeenCalled();
    (expect* buildLineMessageContextMock).not.toHaveBeenCalled();
  });

  (deftest "processes group messages with bot mention when requireMention is set", async () => {
    const processMessage = mock:fn();
    // Simulate a LINE text message with mention.mentionees containing isSelf=true
    const event = {
      type: "message",
      message: {
        id: "m-mention-2",
        type: "text",
        text: "@Bot hi there",
        mention: {
          mentionees: [{ index: 0, length: 4, type: "user", isSelf: true }],
        },
      },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-mention", userId: "user-mention" },
      mode: "active",
      webhookEventId: "evt-mention-2",
      deliveryContext: { isRedelivery: false },
    } as unknown as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          groupPolicy: "open",
          groups: { "*": { requireMention: true } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "processes group messages with @all mention when requireMention is set", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: {
        id: "m-mention-3",
        type: "text",
        text: "@All hi there",
        mention: {
          mentionees: [{ index: 0, length: 4, type: "all" }],
        },
      },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-mention", userId: "user-mention" },
      mode: "active",
      webhookEventId: "evt-mention-3",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          groupPolicy: "open",
          groups: { "*": { requireMention: true } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "does not apply requireMention gating to DM messages", async () => {
    const processMessage = mock:fn();
    const event = {
      type: "message",
      message: { id: "m-mention-dm", type: "text", text: "hi" },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "user", userId: "user-dm" },
      mode: "active",
      webhookEventId: "evt-mention-dm",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { dmPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          dmPolicy: "open",
          groups: { "*": { requireMention: true } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "allows non-text group messages through when requireMention is set (cannot detect mention)", async () => {
    const processMessage = mock:fn();
    // Image message -- LINE only carries mention metadata on text messages.
    const event = {
      type: "message",
      message: { id: "m-mention-img", type: "image", contentProvider: { type: "line" } },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1", userId: "user-img" },
      mode: "active",
      webhookEventId: "evt-mention-img",
      deliveryContext: { isRedelivery: false },
    } as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          groupPolicy: "open",
          groups: { "*": { requireMention: true } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(1);
    (expect* processMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "does not bypass mention gating when non-bot mention is present with control command", async () => {
    const processMessage = mock:fn();
    // Text message mentions another user (not bot) together with a control command.
    const event = {
      type: "message",
      message: {
        id: "m-mention-other",
        type: "text",
        text: "@other !status",
        mention: { mentionees: [{ index: 0, length: 6, type: "user", isSelf: false }] },
      },
      replyToken: "reply-token",
      timestamp: Date.now(),
      source: { type: "group", groupId: "group-1", userId: "user-other" },
      mode: "active",
      webhookEventId: "evt-mention-other",
      deliveryContext: { isRedelivery: false },
    } as unknown as MessageEvent;

    await handleLineWebhookEvents([event], {
      cfg: { channels: { line: { groupPolicy: "open" } } },
      account: {
        accountId: "default",
        enabled: true,
        channelAccessToken: "token",
        channelSecret: "secret",
        tokenSource: "config",
        config: {
          groupPolicy: "open",
          groups: { "*": { requireMention: true } },
        },
      },
      runtime: createRuntime(),
      mediaMaxBytes: 1,
      processMessage,
    });

    // Should be skipped because there is a non-bot mention and the bot was not mentioned.
    (expect* processMessage).not.toHaveBeenCalled();
  });

  (deftest "does not mark replay cache when event processing fails", async () => {
    const processMessage = vi
      .fn()
      .mockRejectedValueOnce(new Error("transient failure"))
      .mockResolvedValueOnce(undefined);
    const event = createReplayMessageEvent({
      messageId: "m-fail-then-retry",
      groupId: "group-retry",
      userId: "user-retry",
      webhookEventId: "evt-fail-then-retry",
      isRedelivery: false,
    });
    const context = createOpenGroupReplayContext(processMessage, createLineWebhookReplayCache());

    await (expect* handleLineWebhookEvents([event], context)).rejects.signals-error("transient failure");
    await handleLineWebhookEvents([event], context);

    (expect* buildLineMessageContextMock).toHaveBeenCalledTimes(2);
    (expect* processMessage).toHaveBeenCalledTimes(2);
    (expect* context.runtime.error).toHaveBeenCalledWith(
      expect.stringContaining("line: event handler failed: Error: transient failure"),
    );
  });
});
