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
import { DEFAULT_EMOJIS } from "../../channels/status-reactions.js";
import {
  createBaseDiscordMessageContext,
  createDiscordDirectMessageContextOverrides,
} from "./message-handler.test-harness.js";
import {
  __testing as threadBindingTesting,
  createThreadBindingManager,
} from "./thread-bindings.js";

const sendMocks = mock:hoisted(() => ({
  reactMessageDiscord: mock:fn(async () => {}),
  removeReactionDiscord: mock:fn(async () => {}),
}));
function createMockDraftStream() {
  return {
    update: mock:fn<(text: string) => void>(() => {}),
    flush: mock:fn(async () => {}),
    messageId: mock:fn(() => "preview-1"),
    clear: mock:fn(async () => {}),
    stop: mock:fn(async () => {}),
    forceNewMessage: mock:fn(() => {}),
  };
}

const deliveryMocks = mock:hoisted(() => ({
  editMessageDiscord: mock:fn(async () => ({})),
  deliverDiscordReply: mock:fn(async () => {}),
  createDiscordDraftStream: mock:fn(() => createMockDraftStream()),
}));
const editMessageDiscord = deliveryMocks.editMessageDiscord;
const deliverDiscordReply = deliveryMocks.deliverDiscordReply;
const createDiscordDraftStream = deliveryMocks.createDiscordDraftStream;
type DispatchInboundParams = {
  dispatcher: {
    sendBlockReply: (payload: {
      text?: string;
      isReasoning?: boolean;
    }) => boolean | deferred-result<boolean>;
    sendFinalReply: (payload: {
      text?: string;
      isReasoning?: boolean;
    }) => boolean | deferred-result<boolean>;
  };
  replyOptions?: {
    onReasoningStream?: () => deferred-result<void> | void;
    onReasoningEnd?: () => deferred-result<void> | void;
    onToolStart?: (payload: { name?: string }) => deferred-result<void> | void;
    onPartialReply?: (payload: { text?: string }) => deferred-result<void> | void;
    onAssistantMessageStart?: () => deferred-result<void> | void;
  };
};
const dispatchInboundMessage = mock:fn(async (_params?: DispatchInboundParams) => ({
  queuedFinal: false,
  counts: { final: 0, tool: 0, block: 0 },
}));
const recordInboundSession = mock:fn(async () => {});
const configSessionsMocks = mock:hoisted(() => ({
  readSessionUpdatedAt: mock:fn(() => undefined),
  resolveStorePath: mock:fn(() => "/tmp/openclaw-discord-process-test-sessions.json"),
}));
const readSessionUpdatedAt = configSessionsMocks.readSessionUpdatedAt;
const resolveStorePath = configSessionsMocks.resolveStorePath;

mock:mock("../send.js", () => ({
  reactMessageDiscord: sendMocks.reactMessageDiscord,
  removeReactionDiscord: sendMocks.removeReactionDiscord,
}));

mock:mock("../send.messages.js", () => ({
  editMessageDiscord: deliveryMocks.editMessageDiscord,
}));

mock:mock("../draft-stream.js", () => ({
  createDiscordDraftStream: deliveryMocks.createDiscordDraftStream,
}));

mock:mock("./reply-delivery.js", () => ({
  deliverDiscordReply: deliveryMocks.deliverDiscordReply,
}));

mock:mock("../../auto-reply/dispatch.js", () => ({
  dispatchInboundMessage,
}));

mock:mock("../../auto-reply/reply/reply-dispatcher.js", () => ({
  createReplyDispatcherWithTyping: mock:fn(
    (opts: { deliver: (payload: unknown, info: { kind: string }) => deferred-result<void> | void }) => ({
      dispatcher: {
        sendToolResult: mock:fn(() => true),
        sendBlockReply: mock:fn((payload: unknown) => {
          void opts.deliver(payload as never, { kind: "block" });
          return true;
        }),
        sendFinalReply: mock:fn((payload: unknown) => {
          void opts.deliver(payload as never, { kind: "final" });
          return true;
        }),
        waitForIdle: mock:fn(async () => {}),
        getQueuedCounts: mock:fn(() => ({ tool: 0, block: 0, final: 0 })),
        markComplete: mock:fn(),
      },
      replyOptions: {},
      markDispatchIdle: mock:fn(),
      markRunComplete: mock:fn(),
    }),
  ),
}));

mock:mock("../../channels/session.js", () => ({
  recordInboundSession,
}));

mock:mock("../../config/sessions.js", () => ({
  readSessionUpdatedAt: configSessionsMocks.readSessionUpdatedAt,
  resolveStorePath: configSessionsMocks.resolveStorePath,
}));

const { processDiscordMessage } = await import("./message-handler.process.js");

const createBaseContext = createBaseDiscordMessageContext;
const BASE_CHANNEL_ROUTE = {
  agentId: "main",
  channel: "discord",
  accountId: "default",
  sessionKey: "agent:main:discord:channel:c1",
  mainSessionKey: "agent:main:main",
} as const;

function mockDispatchSingleBlockReply(payload: { text: string; isReasoning?: boolean }) {
  dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
    await params?.dispatcher.sendBlockReply(payload);
    return { queuedFinal: false, counts: { final: 0, tool: 0, block: 1 } };
  });
}

function createNoQueuedDispatchResult() {
  return { queuedFinal: false, counts: { final: 0, tool: 0, block: 0 } };
}

async function processStreamOffDiscordMessage() {
  const ctx = await createBaseContext({ discordConfig: { streamMode: "off" } });
  // oxlint-disable-next-line typescript/no-explicit-any
  await processDiscordMessage(ctx as any);
}

beforeEach(() => {
  mock:useRealTimers();
  sendMocks.reactMessageDiscord.mockClear();
  sendMocks.removeReactionDiscord.mockClear();
  editMessageDiscord.mockClear();
  deliverDiscordReply.mockClear();
  createDiscordDraftStream.mockClear();
  dispatchInboundMessage.mockClear();
  recordInboundSession.mockClear();
  readSessionUpdatedAt.mockClear();
  resolveStorePath.mockClear();
  dispatchInboundMessage.mockResolvedValue(createNoQueuedDispatchResult());
  recordInboundSession.mockResolvedValue(undefined);
  readSessionUpdatedAt.mockReturnValue(undefined);
  resolveStorePath.mockReturnValue("/tmp/openclaw-discord-process-test-sessions.json");
  threadBindingTesting.resetThreadBindingsForTests();
});

function getLastRouteUpdate():
  | { sessionKey?: string; channel?: string; to?: string; accountId?: string }
  | undefined {
  const callArgs = recordInboundSession.mock.calls.at(-1) as unknown[] | undefined;
  const params = callArgs?.[0] as
    | {
        updateLastRoute?: {
          sessionKey?: string;
          channel?: string;
          to?: string;
          accountId?: string;
        };
      }
    | undefined;
  return params?.updateLastRoute;
}

function getLastDispatchCtx():
  | { SessionKey?: string; MessageThreadId?: string | number }
  | undefined {
  const callArgs = dispatchInboundMessage.mock.calls.at(-1) as unknown[] | undefined;
  const params = callArgs?.[0] as
    | { ctx?: { SessionKey?: string; MessageThreadId?: string | number } }
    | undefined;
  return params?.ctx;
}

async function runProcessDiscordMessage(ctx: unknown): deferred-result<void> {
  // oxlint-disable-next-line typescript/no-explicit-any
  await processDiscordMessage(ctx as any);
}

async function runInPartialStreamMode(): deferred-result<void> {
  const ctx = await createBaseContext({
    discordConfig: { streamMode: "partial" },
  });
  await runProcessDiscordMessage(ctx);
}

function getReactionEmojis(): string[] {
  return (
    sendMocks.reactMessageDiscord.mock.calls as unknown as Array<[unknown, unknown, string]>
  ).map((call) => call[2]);
}

function createMockDraftStreamForTest() {
  const draftStream = createMockDraftStream();
  createDiscordDraftStream.mockReturnValueOnce(draftStream);
  return draftStream;
}

function expectSinglePreviewEdit() {
  (expect* editMessageDiscord).toHaveBeenCalledWith(
    "c1",
    "preview-1",
    { content: "Hello\nWorld" },
    { rest: {} },
  );
  (expect* deliverDiscordReply).not.toHaveBeenCalled();
}

(deftest-group "processDiscordMessage ack reactions", () => {
  (deftest "skips ack reactions for group-mentions when mentions are not required", async () => {
    const ctx = await createBaseContext({
      shouldRequireMention: false,
      effectiveWasMentioned: false,
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* sendMocks.reactMessageDiscord).not.toHaveBeenCalled();
  });

  (deftest "sends ack reactions for mention-gated guild messages when mentioned", async () => {
    const ctx = await createBaseContext({
      shouldRequireMention: true,
      effectiveWasMentioned: true,
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* sendMocks.reactMessageDiscord.mock.calls[0]).is-equal(["c1", "m1", "👀", { rest: {} }]);
  });

  (deftest "uses preflight-resolved messageChannelId when message.channelId is missing", async () => {
    const ctx = await createBaseContext({
      message: {
        id: "m1",
        timestamp: new Date().toISOString(),
        attachments: [],
      },
      messageChannelId: "fallback-channel",
      shouldRequireMention: true,
      effectiveWasMentioned: true,
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* sendMocks.reactMessageDiscord.mock.calls[0]).is-equal([
      "fallback-channel",
      "m1",
      "👀",
      { rest: {} },
    ]);
  });

  (deftest "debounces intermediate phase reactions and jumps to done for short runs", async () => {
    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.replyOptions?.onReasoningStream?.();
      await params?.replyOptions?.onToolStart?.({ name: "exec" });
      return createNoQueuedDispatchResult();
    });

    const ctx = await createBaseContext();

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    const emojis = getReactionEmojis();
    (expect* emojis).contains("👀");
    (expect* emojis).contains(DEFAULT_EMOJIS.done);
    (expect* emojis).not.contains(DEFAULT_EMOJIS.thinking);
    (expect* emojis).not.contains(DEFAULT_EMOJIS.coding);
  });

  (deftest "shows stall emojis for long no-progress runs", async () => {
    mock:useFakeTimers();
    let releaseDispatch!: () => void;
    const dispatchGate = new deferred-result<void>((resolve) => {
      releaseDispatch = () => resolve();
    });
    dispatchInboundMessage.mockImplementationOnce(async () => {
      await dispatchGate;
      return createNoQueuedDispatchResult();
    });

    const ctx = await createBaseContext();
    // oxlint-disable-next-line typescript/no-explicit-any
    const runPromise = processDiscordMessage(ctx as any);

    await mock:advanceTimersByTimeAsync(30_001);
    releaseDispatch();
    await mock:runAllTimersAsync();

    await runPromise;
    const emojis = (
      sendMocks.reactMessageDiscord.mock.calls as unknown as Array<[unknown, unknown, string]>
    ).map((call) => call[2]);
    (expect* emojis).contains(DEFAULT_EMOJIS.stallSoft);
    (expect* emojis).contains(DEFAULT_EMOJIS.stallHard);
    (expect* emojis).contains(DEFAULT_EMOJIS.done);
  });

  (deftest "applies status reaction emoji/timing overrides from config", async () => {
    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.replyOptions?.onReasoningStream?.();
      return createNoQueuedDispatchResult();
    });

    const ctx = await createBaseContext({
      cfg: {
        messages: {
          ackReaction: "👀",
          statusReactions: {
            emojis: { queued: "🟦", thinking: "🧪", done: "🏁" },
            timing: { debounceMs: 0 },
          },
        },
        session: { store: "/tmp/openclaw-discord-process-test-sessions.json" },
      },
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    const emojis = getReactionEmojis();
    (expect* emojis).contains("🟦");
    (expect* emojis).contains("🏁");
  });

  (deftest "clears status reactions when dispatch aborts and removeAckAfterReply is enabled", async () => {
    const abortController = new AbortController();
    dispatchInboundMessage.mockImplementationOnce(async () => {
      abortController.abort();
      error("aborted");
    });

    const ctx = await createBaseContext({
      abortSignal: abortController.signal,
      cfg: {
        messages: {
          ackReaction: "👀",
          removeAckAfterReply: true,
        },
        session: { store: "/tmp/openclaw-discord-process-test-sessions.json" },
      },
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    await mock:waitFor(() => {
      (expect* sendMocks.removeReactionDiscord).toHaveBeenCalledWith("c1", "m1", "👀", { rest: {} });
    });
  });
});

(deftest-group "processDiscordMessage session routing", () => {
  (deftest "stores DM lastRoute with user target for direct-session continuity", async () => {
    const ctx = await createBaseContext({
      ...createDiscordDirectMessageContextOverrides(),
      message: {
        id: "m1",
        channelId: "dm1",
        timestamp: new Date().toISOString(),
        attachments: [],
      },
      messageChannelId: "dm1",
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* getLastRouteUpdate()).is-equal({
      sessionKey: "agent:main:discord:direct:u1",
      channel: "discord",
      to: "user:U1",
      accountId: "default",
    });
  });

  (deftest "stores group lastRoute with channel target", async () => {
    const ctx = await createBaseContext({
      baseSessionKey: "agent:main:discord:channel:c1",
      route: BASE_CHANNEL_ROUTE,
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* getLastRouteUpdate()).is-equal({
      sessionKey: "agent:main:discord:channel:c1",
      channel: "discord",
      to: "channel:c1",
      accountId: "default",
    });
  });

  (deftest "prefers bound session keys and sets MessageThreadId for bound thread messages", async () => {
    const threadBindings = createThreadBindingManager({
      accountId: "default",
      persist: false,
      enableSweeper: false,
    });
    await threadBindings.bindTarget({
      threadId: "thread-1",
      channelId: "c-parent",
      targetKind: "subagent",
      targetSessionKey: "agent:main:subagent:child",
      agentId: "main",
      webhookId: "wh_1",
      webhookToken: "tok_1",
      introText: "",
    });

    const ctx = await createBaseContext({
      messageChannelId: "thread-1",
      threadChannel: { id: "thread-1", name: "subagent-thread" },
      boundSessionKey: "agent:main:subagent:child",
      threadBindings,
      route: BASE_CHANNEL_ROUTE,
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* getLastDispatchCtx()).matches-object({
      SessionKey: "agent:main:subagent:child",
      MessageThreadId: "thread-1",
    });
    (expect* getLastRouteUpdate()).is-equal({
      sessionKey: "agent:main:subagent:child",
      channel: "discord",
      to: "channel:thread-1",
      accountId: "default",
    });
  });
});

(deftest-group "processDiscordMessage draft streaming", () => {
  async function runSingleChunkFinalScenario(discordConfig: Record<string, unknown>) {
    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.dispatcher.sendFinalReply({ text: "Hello\nWorld" });
      return { queuedFinal: true, counts: { final: 1, tool: 0, block: 0 } };
    });

    const ctx = await createBaseContext({
      discordConfig,
    });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);
  }

  async function createBlockModeContext() {
    return await createBaseContext({
      cfg: {
        messages: { ackReaction: "👀" },
        session: { store: "/tmp/openclaw-discord-process-test-sessions.json" },
        channels: {
          discord: {
            draftChunk: { minChars: 1, maxChars: 5, breakPreference: "newline" },
          },
        },
      },
      discordConfig: { streamMode: "block" },
    });
  }

  (deftest "finalizes via preview edit when final fits one chunk", async () => {
    await runSingleChunkFinalScenario({ streamMode: "partial", maxLinesPerMessage: 5 });
    expectSinglePreviewEdit();
  });

  (deftest "accepts streaming=true alias for partial preview mode", async () => {
    await runSingleChunkFinalScenario({ streaming: true, maxLinesPerMessage: 5 });
    expectSinglePreviewEdit();
  });

  (deftest "falls back to standard send when final needs multiple chunks", async () => {
    await runSingleChunkFinalScenario({ streamMode: "partial", maxLinesPerMessage: 1 });

    (expect* editMessageDiscord).not.toHaveBeenCalled();
    (expect* deliverDiscordReply).toHaveBeenCalledTimes(1);
  });

  (deftest "suppresses reasoning payload delivery to Discord", async () => {
    mockDispatchSingleBlockReply({ text: "thinking...", isReasoning: true });
    await processStreamOffDiscordMessage();

    (expect* deliverDiscordReply).not.toHaveBeenCalled();
  });

  (deftest "suppresses reasoning-tagged final payload delivery to Discord", async () => {
    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.dispatcher.sendFinalReply({
        text: "Reasoning:\nthis should stay internal",
        isReasoning: true,
      });
      return { queuedFinal: true, counts: { final: 1, tool: 0, block: 0 } };
    });

    const ctx = await createBaseContext({ discordConfig: { streamMode: "off" } });

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* deliverDiscordReply).not.toHaveBeenCalled();
    (expect* editMessageDiscord).not.toHaveBeenCalled();
  });

  (deftest "delivers non-reasoning block payloads to Discord", async () => {
    mockDispatchSingleBlockReply({ text: "hello from block stream" });
    await processStreamOffDiscordMessage();

    (expect* deliverDiscordReply).toHaveBeenCalledTimes(1);
  });

  (deftest "streams block previews using draft chunking", async () => {
    const draftStream = createMockDraftStreamForTest();

    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.replyOptions?.onPartialReply?.({ text: "HelloWorld" });
      return createNoQueuedDispatchResult();
    });

    const ctx = await createBlockModeContext();

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    const updates = draftStream.update.mock.calls.map((call) => call[0]);
    (expect* updates).is-equal(["Hello", "HelloWorld"]);
  });

  (deftest "forces new preview messages on assistant boundaries in block mode", async () => {
    const draftStream = createMockDraftStreamForTest();

    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.replyOptions?.onPartialReply?.({ text: "Hello" });
      await params?.replyOptions?.onAssistantMessageStart?.();
      return createNoQueuedDispatchResult();
    });

    const ctx = await createBlockModeContext();

    // oxlint-disable-next-line typescript/no-explicit-any
    await processDiscordMessage(ctx as any);

    (expect* draftStream.forceNewMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "strips reasoning tags from partial stream updates", async () => {
    const draftStream = createMockDraftStreamForTest();

    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.replyOptions?.onPartialReply?.({
        text: "<thinking>Let me think about this</thinking>\nThe answer is 42",
      });
      return createNoQueuedDispatchResult();
    });

    await runInPartialStreamMode();

    const updates = draftStream.update.mock.calls.map((call) => call[0]);
    for (const text of updates) {
      (expect* text).not.contains("<thinking>");
    }
  });

  (deftest "skips pure-reasoning partial updates without updating draft", async () => {
    const draftStream = createMockDraftStreamForTest();

    dispatchInboundMessage.mockImplementationOnce(async (params?: DispatchInboundParams) => {
      await params?.replyOptions?.onPartialReply?.({
        text: "Reasoning:\nThe user asked about X so I need to consider Y",
      });
      return createNoQueuedDispatchResult();
    });

    await runInPartialStreamMode();

    (expect* draftStream.update).not.toHaveBeenCalled();
  });
});
