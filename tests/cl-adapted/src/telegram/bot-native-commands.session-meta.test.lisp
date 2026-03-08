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
import type { OpenClawConfig } from "../config/config.js";
import {
  registerTelegramNativeCommands,
  type RegisterTelegramHandlerParams,
} from "./bot-native-commands.js";
import { createNativeCommandTestParams } from "./bot-native-commands.test-helpers.js";

// All mocks scoped to this file only — does not affect bot-native-commands.test.lisp

type ResolveConfiguredAcpBindingRecordFn =
  typeof import("../acp/persistent-bindings.js").resolveConfiguredAcpBindingRecord;
type EnsureConfiguredAcpBindingSessionFn =
  typeof import("../acp/persistent-bindings.js").ensureConfiguredAcpBindingSession;

const persistentBindingMocks = mock:hoisted(() => ({
  resolveConfiguredAcpBindingRecord: mock:fn<ResolveConfiguredAcpBindingRecordFn>(() => null),
  ensureConfiguredAcpBindingSession: mock:fn<EnsureConfiguredAcpBindingSessionFn>(async () => ({
    ok: true,
    sessionKey: "agent:codex:acp:binding:telegram:default:seed",
  })),
}));
const sessionMocks = mock:hoisted(() => ({
  recordSessionMetaFromInbound: mock:fn(),
  resolveStorePath: mock:fn(),
}));
const replyMocks = mock:hoisted(() => ({
  dispatchReplyWithBufferedBlockDispatcher: mock:fn(async () => undefined),
}));
const sessionBindingMocks = mock:hoisted(() => ({
  resolveByConversation: mock:fn<
    (ref: unknown) => { bindingId: string; targetSessionKey: string } | null
  >(() => null),
  touch: mock:fn(),
}));

mock:mock("../acp/persistent-bindings.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../acp/persistent-bindings.js")>();
  return {
    ...actual,
    resolveConfiguredAcpBindingRecord: persistentBindingMocks.resolveConfiguredAcpBindingRecord,
    ensureConfiguredAcpBindingSession: persistentBindingMocks.ensureConfiguredAcpBindingSession,
  };
});
mock:mock("../config/sessions.js", () => ({
  recordSessionMetaFromInbound: sessionMocks.recordSessionMetaFromInbound,
  resolveStorePath: sessionMocks.resolveStorePath,
}));
mock:mock("../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: mock:fn(async () => []),
}));
mock:mock("../auto-reply/reply/inbound-context.js", () => ({
  finalizeInboundContext: mock:fn((ctx: unknown) => ctx),
}));
mock:mock("../auto-reply/reply/provider-dispatcher.js", () => ({
  dispatchReplyWithBufferedBlockDispatcher: replyMocks.dispatchReplyWithBufferedBlockDispatcher,
}));
mock:mock("../channels/reply-prefix.js", () => ({
  createReplyPrefixOptions: mock:fn(() => ({ onModelSelected: () => {} })),
}));
mock:mock("../infra/outbound/session-binding-service.js", () => ({
  getSessionBindingService: () => ({
    bind: mock:fn(),
    getCapabilities: mock:fn(),
    listBySession: mock:fn(),
    resolveByConversation: (ref: unknown) => sessionBindingMocks.resolveByConversation(ref),
    touch: (bindingId: string, at?: number) => sessionBindingMocks.touch(bindingId, at),
    unbind: mock:fn(),
  }),
}));
mock:mock("../auto-reply/skill-commands.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../auto-reply/skill-commands.js")>();
  return { ...actual, listSkillCommandsForAgents: mock:fn(() => []) };
});
mock:mock("../plugins/commands.js", () => ({
  getPluginCommandSpecs: mock:fn(() => []),
  matchPluginCommand: mock:fn(() => null),
  executePluginCommand: mock:fn(async () => ({ text: "ok" })),
}));
mock:mock("./bot/delivery.js", () => ({
  deliverReplies: mock:fn(async () => ({ delivered: true })),
}));

function createDeferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new deferred-result<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

type TelegramCommandHandler = (ctx: unknown) => deferred-result<void>;

function buildStatusCommandContext() {
  return {
    match: "",
    message: {
      message_id: 1,
      date: Math.floor(Date.now() / 1000),
      chat: { id: 100, type: "private" as const },
      from: { id: 200, username: "bob" },
    },
  };
}

function buildStatusTopicCommandContext() {
  return {
    match: "",
    message: {
      message_id: 2,
      date: Math.floor(Date.now() / 1000),
      chat: {
        id: -1001234567890,
        type: "supergroup" as const,
        title: "OpenClaw",
        is_forum: true,
      },
      message_thread_id: 42,
      from: { id: 200, username: "bob" },
    },
  };
}

function registerAndResolveStatusHandler(params: {
  cfg: OpenClawConfig;
  allowFrom?: string[];
  groupAllowFrom?: string[];
  resolveTelegramGroupConfig?: RegisterTelegramHandlerParams["resolveTelegramGroupConfig"];
}): {
  handler: TelegramCommandHandler;
  sendMessage: ReturnType<typeof mock:fn>;
} {
  const { cfg, allowFrom, groupAllowFrom, resolveTelegramGroupConfig } = params;
  return registerAndResolveCommandHandlerBase({
    commandName: "status",
    cfg,
    allowFrom: allowFrom ?? ["*"],
    groupAllowFrom: groupAllowFrom ?? [],
    useAccessGroups: true,
    resolveTelegramGroupConfig,
  });
}

function registerAndResolveCommandHandlerBase(params: {
  commandName: string;
  cfg: OpenClawConfig;
  allowFrom: string[];
  groupAllowFrom: string[];
  useAccessGroups: boolean;
  resolveTelegramGroupConfig?: RegisterTelegramHandlerParams["resolveTelegramGroupConfig"];
}): {
  handler: TelegramCommandHandler;
  sendMessage: ReturnType<typeof mock:fn>;
} {
  const {
    commandName,
    cfg,
    allowFrom,
    groupAllowFrom,
    useAccessGroups,
    resolveTelegramGroupConfig,
  } = params;
  const commandHandlers = new Map<string, TelegramCommandHandler>();
  const sendMessage = mock:fn().mockResolvedValue(undefined);
  registerTelegramNativeCommands({
    ...createNativeCommandTestParams({
      bot: {
        api: {
          setMyCommands: mock:fn().mockResolvedValue(undefined),
          sendMessage,
        },
        command: mock:fn((name: string, cb: TelegramCommandHandler) => {
          commandHandlers.set(name, cb);
        }),
      } as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
      cfg,
      allowFrom,
      groupAllowFrom,
      useAccessGroups,
      resolveTelegramGroupConfig,
    }),
  });

  const handler = commandHandlers.get(commandName);
  (expect* handler).is-truthy();
  return { handler: handler as TelegramCommandHandler, sendMessage };
}

function registerAndResolveCommandHandler(params: {
  commandName: string;
  cfg: OpenClawConfig;
  allowFrom?: string[];
  groupAllowFrom?: string[];
  useAccessGroups?: boolean;
  resolveTelegramGroupConfig?: RegisterTelegramHandlerParams["resolveTelegramGroupConfig"];
}): {
  handler: TelegramCommandHandler;
  sendMessage: ReturnType<typeof mock:fn>;
} {
  const {
    commandName,
    cfg,
    allowFrom,
    groupAllowFrom,
    useAccessGroups,
    resolveTelegramGroupConfig,
  } = params;
  return registerAndResolveCommandHandlerBase({
    commandName,
    cfg,
    allowFrom: allowFrom ?? [],
    groupAllowFrom: groupAllowFrom ?? [],
    useAccessGroups: useAccessGroups ?? true,
    resolveTelegramGroupConfig,
  });
}

function createConfiguredAcpTopicBinding(boundSessionKey: string) {
  return {
    spec: {
      channel: "telegram",
      accountId: "default",
      conversationId: "-1001234567890:topic:42",
      parentConversationId: "-1001234567890",
      agentId: "codex",
      mode: "persistent",
    },
    record: {
      bindingId: "config:acp:telegram:default:-1001234567890:topic:42",
      targetSessionKey: boundSessionKey,
      targetKind: "session",
      conversation: {
        channel: "telegram",
        accountId: "default",
        conversationId: "-1001234567890:topic:42",
        parentConversationId: "-1001234567890",
      },
      status: "active",
      boundAt: 0,
    },
  } satisfies import("../acp/persistent-bindings.js").ResolvedConfiguredAcpBinding;
}

function expectUnauthorizedNewCommandBlocked(sendMessage: ReturnType<typeof mock:fn>) {
  (expect* replyMocks.dispatchReplyWithBufferedBlockDispatcher).not.toHaveBeenCalled();
  (expect* persistentBindingMocks.resolveConfiguredAcpBindingRecord).not.toHaveBeenCalled();
  (expect* persistentBindingMocks.ensureConfiguredAcpBindingSession).not.toHaveBeenCalled();
  (expect* sendMessage).toHaveBeenCalledWith(
    -1001234567890,
    "You are not authorized to use this command.",
    expect.objectContaining({ message_thread_id: 42 }),
  );
}

(deftest-group "registerTelegramNativeCommands — session metadata", () => {
  beforeEach(() => {
    persistentBindingMocks.resolveConfiguredAcpBindingRecord.mockClear();
    persistentBindingMocks.resolveConfiguredAcpBindingRecord.mockReturnValue(null);
    persistentBindingMocks.ensureConfiguredAcpBindingSession.mockClear();
    persistentBindingMocks.ensureConfiguredAcpBindingSession.mockResolvedValue({
      ok: true,
      sessionKey: "agent:codex:acp:binding:telegram:default:seed",
    });
    sessionMocks.recordSessionMetaFromInbound.mockClear().mockResolvedValue(undefined);
    sessionMocks.resolveStorePath.mockClear().mockReturnValue("/tmp/openclaw-sessions.json");
    replyMocks.dispatchReplyWithBufferedBlockDispatcher.mockClear().mockResolvedValue(undefined);
    sessionBindingMocks.resolveByConversation.mockReset().mockReturnValue(null);
    sessionBindingMocks.touch.mockReset();
  });

  (deftest "calls recordSessionMetaFromInbound after a native slash command", async () => {
    const cfg: OpenClawConfig = {};
    const { handler } = registerAndResolveStatusHandler({ cfg });
    await handler(buildStatusCommandContext());

    (expect* sessionMocks.recordSessionMetaFromInbound).toHaveBeenCalledTimes(1);
    const call = (
      sessionMocks.recordSessionMetaFromInbound.mock.calls as unknown as Array<
        [{ sessionKey?: string; ctx?: { OriginatingChannel?: string; Provider?: string } }]
      >
    )[0]?.[0];
    (expect* call?.ctx?.OriginatingChannel).is("telegram");
    (expect* call?.ctx?.Provider).is("telegram");
    (expect* call?.sessionKey).is("agent:main:telegram:slash:200");
  });

  (deftest "awaits session metadata persistence before dispatch", async () => {
    const deferred = createDeferred<void>();
    sessionMocks.recordSessionMetaFromInbound.mockReturnValue(deferred.promise);

    const cfg: OpenClawConfig = {};
    const { handler } = registerAndResolveStatusHandler({ cfg });
    const runPromise = handler(buildStatusCommandContext());

    await mock:waitFor(() => {
      (expect* sessionMocks.recordSessionMetaFromInbound).toHaveBeenCalledTimes(1);
    });
    (expect* replyMocks.dispatchReplyWithBufferedBlockDispatcher).not.toHaveBeenCalled();

    deferred.resolve();
    await runPromise;

    (expect* replyMocks.dispatchReplyWithBufferedBlockDispatcher).toHaveBeenCalledTimes(1);
  });

  (deftest "routes Telegram native commands through configured ACP topic bindings", async () => {
    const boundSessionKey = "agent:codex:acp:binding:telegram:default:feedface";
    persistentBindingMocks.resolveConfiguredAcpBindingRecord.mockReturnValue(
      createConfiguredAcpTopicBinding(boundSessionKey),
    );
    persistentBindingMocks.ensureConfiguredAcpBindingSession.mockResolvedValue({
      ok: true,
      sessionKey: boundSessionKey,
    });

    const { handler } = registerAndResolveStatusHandler({
      cfg: {},
      allowFrom: ["200"],
      groupAllowFrom: ["200"],
    });
    await handler(buildStatusTopicCommandContext());

    (expect* persistentBindingMocks.resolveConfiguredAcpBindingRecord).toHaveBeenCalledTimes(1);
    (expect* persistentBindingMocks.ensureConfiguredAcpBindingSession).toHaveBeenCalledTimes(1);
    const dispatchCall = (
      replyMocks.dispatchReplyWithBufferedBlockDispatcher.mock.calls as unknown as Array<
        [{ ctx?: { CommandTargetSessionKey?: string } }]
      >
    )[0]?.[0];
    (expect* dispatchCall?.ctx?.CommandTargetSessionKey).is(boundSessionKey);
    const sessionMetaCall = (
      sessionMocks.recordSessionMetaFromInbound.mock.calls as unknown as Array<
        [{ sessionKey?: string }]
      >
    )[0]?.[0];
    (expect* sessionMetaCall?.sessionKey).is("agent:codex:telegram:slash:200");
  });

  (deftest "routes Telegram native commands through topic-specific agent sessions", async () => {
    const { handler } = registerAndResolveStatusHandler({
      cfg: {},
      allowFrom: ["200"],
      groupAllowFrom: ["200"],
      resolveTelegramGroupConfig: () => ({
        groupConfig: { requireMention: false },
        topicConfig: { agentId: "zu" },
      }),
    });
    await handler(buildStatusTopicCommandContext());

    const dispatchCall = (
      replyMocks.dispatchReplyWithBufferedBlockDispatcher.mock.calls as unknown as Array<
        [{ ctx?: { CommandTargetSessionKey?: string } }]
      >
    )[0]?.[0];
    (expect* dispatchCall?.ctx?.CommandTargetSessionKey).is(
      "agent:zu:telegram:group:-1001234567890:topic:42",
    );
  });

  (deftest "routes Telegram native commands through bound topic sessions", async () => {
    sessionBindingMocks.resolveByConversation.mockReturnValue({
      bindingId: "default:-1001234567890:topic:42",
      targetSessionKey: "agent:codex-acp:session-1",
    });

    const { handler } = registerAndResolveStatusHandler({
      cfg: {},
      allowFrom: ["200"],
      groupAllowFrom: ["200"],
    });
    await handler(buildStatusTopicCommandContext());

    (expect* sessionBindingMocks.resolveByConversation).toHaveBeenCalledWith({
      channel: "telegram",
      accountId: "default",
      conversationId: "-1001234567890:topic:42",
    });
    const dispatchCall = (
      replyMocks.dispatchReplyWithBufferedBlockDispatcher.mock.calls as unknown as Array<
        [{ ctx?: { CommandTargetSessionKey?: string } }]
      >
    )[0]?.[0];
    (expect* dispatchCall?.ctx?.CommandTargetSessionKey).is("agent:codex-acp:session-1");
    (expect* sessionBindingMocks.touch).toHaveBeenCalledWith(
      "default:-1001234567890:topic:42",
      undefined,
    );
  });

  (deftest "aborts native command dispatch when configured ACP topic binding cannot initialize", async () => {
    const boundSessionKey = "agent:codex:acp:binding:telegram:default:feedface";
    persistentBindingMocks.resolveConfiguredAcpBindingRecord.mockReturnValue(
      createConfiguredAcpTopicBinding(boundSessionKey),
    );
    persistentBindingMocks.ensureConfiguredAcpBindingSession.mockResolvedValue({
      ok: false,
      sessionKey: boundSessionKey,
      error: "gateway unavailable",
    });

    const { handler, sendMessage } = registerAndResolveStatusHandler({
      cfg: {},
      allowFrom: ["200"],
      groupAllowFrom: ["200"],
    });
    await handler(buildStatusTopicCommandContext());

    (expect* replyMocks.dispatchReplyWithBufferedBlockDispatcher).not.toHaveBeenCalled();
    (expect* sendMessage).toHaveBeenCalledWith(
      -1001234567890,
      "Configured ACP binding is unavailable right now. Please try again.",
      expect.objectContaining({ message_thread_id: 42 }),
    );
  });

  (deftest "keeps /new blocked in ACP-bound Telegram topics when sender is unauthorized", async () => {
    const boundSessionKey = "agent:codex:acp:binding:telegram:default:feedface";
    persistentBindingMocks.resolveConfiguredAcpBindingRecord.mockReturnValue(
      createConfiguredAcpTopicBinding(boundSessionKey),
    );
    persistentBindingMocks.ensureConfiguredAcpBindingSession.mockResolvedValue({
      ok: true,
      sessionKey: boundSessionKey,
    });

    const { handler, sendMessage } = registerAndResolveCommandHandler({
      commandName: "new",
      cfg: {},
      allowFrom: [],
      groupAllowFrom: [],
      useAccessGroups: true,
    });
    await handler(buildStatusTopicCommandContext());

    expectUnauthorizedNewCommandBlocked(sendMessage);
  });

  (deftest "keeps /new blocked for unbound Telegram topics when sender is unauthorized", async () => {
    persistentBindingMocks.resolveConfiguredAcpBindingRecord.mockReturnValue(null);

    const { handler, sendMessage } = registerAndResolveCommandHandler({
      commandName: "new",
      cfg: {},
      allowFrom: [],
      groupAllowFrom: [],
      useAccessGroups: true,
    });
    await handler(buildStatusTopicCommandContext());

    expectUnauthorizedNewCommandBlocked(sendMessage);
  });
});
