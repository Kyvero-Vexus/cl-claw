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

import path from "sbcl:path";
import type { Bot } from "grammy";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { STATE_DIR } from "../config/paths.js";
import {
  createSequencedTestDraftStream,
  createTestDraftStream,
} from "./draft-stream.test-helpers.js";

const createTelegramDraftStream = mock:hoisted(() => mock:fn());
const dispatchReplyWithBufferedBlockDispatcher = mock:hoisted(() => mock:fn());
const deliverReplies = mock:hoisted(() => mock:fn());
const editMessageTelegram = mock:hoisted(() => mock:fn());
const loadSessionStore = mock:hoisted(() => mock:fn());
const resolveStorePath = mock:hoisted(() => mock:fn(() => "/tmp/sessions.json"));

mock:mock("./draft-stream.js", () => ({
  createTelegramDraftStream,
}));

mock:mock("../auto-reply/reply/provider-dispatcher.js", () => ({
  dispatchReplyWithBufferedBlockDispatcher,
}));

mock:mock("./bot/delivery.js", () => ({
  deliverReplies,
}));

mock:mock("./send.js", () => ({
  editMessageTelegram,
}));

mock:mock("../config/sessions.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/sessions.js")>();
  return {
    ...actual,
    loadSessionStore,
    resolveStorePath,
  };
});

mock:mock("./sticker-cache.js", () => ({
  cacheSticker: mock:fn(),
  describeStickerImage: mock:fn(),
}));

import { dispatchTelegramMessage } from "./bot-message-dispatch.js";

(deftest-group "dispatchTelegramMessage draft streaming", () => {
  type TelegramMessageContext = Parameters<typeof dispatchTelegramMessage>[0]["context"];

  beforeEach(() => {
    createTelegramDraftStream.mockClear();
    dispatchReplyWithBufferedBlockDispatcher.mockClear();
    deliverReplies.mockClear();
    editMessageTelegram.mockClear();
    loadSessionStore.mockClear();
    resolveStorePath.mockClear();
    resolveStorePath.mockReturnValue("/tmp/sessions.json");
    loadSessionStore.mockReturnValue({});
  });

  const createDraftStream = (messageId?: number) => createTestDraftStream({ messageId });
  const createSequencedDraftStream = (startMessageId = 1001) =>
    createSequencedTestDraftStream(startMessageId);

  function setupDraftStreams(params?: { answerMessageId?: number; reasoningMessageId?: number }) {
    const answerDraftStream = createDraftStream(params?.answerMessageId);
    const reasoningDraftStream = createDraftStream(params?.reasoningMessageId);
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    return { answerDraftStream, reasoningDraftStream };
  }

  function createContext(overrides?: Partial<TelegramMessageContext>): TelegramMessageContext {
    const base = {
      ctxPayload: {},
      primaryCtx: { message: { chat: { id: 123, type: "private" } } },
      msg: {
        chat: { id: 123, type: "private" },
        message_id: 456,
        message_thread_id: 777,
      },
      chatId: 123,
      isGroup: false,
      resolvedThreadId: undefined,
      replyThreadId: 777,
      threadSpec: { id: 777, scope: "dm" },
      historyKey: undefined,
      historyLimit: 0,
      groupHistories: new Map(),
      route: { agentId: "default", accountId: "default" },
      skillFilter: undefined,
      sendTyping: mock:fn(),
      sendRecordVoice: mock:fn(),
      ackReactionPromise: null,
      reactionApi: null,
      removeAckAfterReply: false,
    } as unknown as TelegramMessageContext;

    return {
      ...base,
      ...overrides,
      // Merge nested fields when overrides provide partial objects.
      primaryCtx: {
        ...(base.primaryCtx as object),
        ...(overrides?.primaryCtx ? (overrides.primaryCtx as object) : null),
      } as TelegramMessageContext["primaryCtx"],
      msg: {
        ...(base.msg as object),
        ...(overrides?.msg ? (overrides.msg as object) : null),
      } as TelegramMessageContext["msg"],
      route: {
        ...(base.route as object),
        ...(overrides?.route ? (overrides.route as object) : null),
      } as TelegramMessageContext["route"],
    };
  }

  function createBot(): Bot {
    return {
      api: {
        sendMessage: mock:fn(),
        editMessageText: mock:fn(),
        deleteMessage: mock:fn().mockResolvedValue(true),
      },
    } as unknown as Bot;
  }

  function createRuntime(): Parameters<typeof dispatchTelegramMessage>[0]["runtime"] {
    return {
      log: mock:fn(),
      error: mock:fn(),
      exit: () => {
        error("exit");
      },
    };
  }

  async function dispatchWithContext(params: {
    context: TelegramMessageContext;
    telegramCfg?: Parameters<typeof dispatchTelegramMessage>[0]["telegramCfg"];
    streamMode?: Parameters<typeof dispatchTelegramMessage>[0]["streamMode"];
    bot?: Bot;
  }) {
    const bot = params.bot ?? createBot();
    await dispatchTelegramMessage({
      context: params.context,
      bot,
      cfg: {},
      runtime: createRuntime(),
      replyToMode: "first",
      streamMode: params.streamMode ?? "partial",
      textLimit: 4096,
      telegramCfg: params.telegramCfg ?? {},
      opts: { token: "token" },
    });
  }

  function createReasoningStreamContext(): TelegramMessageContext {
    loadSessionStore.mockReturnValue({
      s1: { reasoningLevel: "stream" },
    });
    return createContext({
      ctxPayload: { SessionKey: "s1" } as unknown as TelegramMessageContext["ctxPayload"],
    });
  }

  (deftest "streams drafts in private threads and forwards thread id", async () => {
    const draftStream = createDraftStream();
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Hello" });
        await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    const context = createContext({
      route: {
        agentId: "work",
      } as unknown as TelegramMessageContext["route"],
    });
    await dispatchWithContext({ context });

    (expect* createTelegramDraftStream).toHaveBeenCalledWith(
      expect.objectContaining({
        chatId: 123,
        thread: { id: 777, scope: "dm" },
        minInitialChars: 30,
      }),
    );
    (expect* draftStream.update).toHaveBeenCalledWith("Hello");
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        thread: { id: 777, scope: "dm" },
        mediaLocalRoots: expect.arrayContaining([path.join(STATE_DIR, "workspace-work")]),
      }),
    );
    (expect* dispatchReplyWithBufferedBlockDispatcher).toHaveBeenCalledWith(
      expect.objectContaining({
        replyOptions: expect.objectContaining({
          disableBlockStreaming: true,
        }),
      }),
    );
    (expect* editMessageTelegram).not.toHaveBeenCalled();
    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
  });

  (deftest "uses 30-char preview debounce for legacy block stream mode", async () => {
    const draftStream = createDraftStream();
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Hello" });
        await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext(), streamMode: "block" });

    (expect* createTelegramDraftStream).toHaveBeenCalledWith(
      expect.objectContaining({
        minInitialChars: 30,
      }),
    );
  });

  (deftest "keeps block streaming enabled when account config enables it", async () => {
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({
      context: createContext(),
      telegramCfg: { blockStreaming: true },
    });

    (expect* createTelegramDraftStream).not.toHaveBeenCalled();
    (expect* dispatchReplyWithBufferedBlockDispatcher).toHaveBeenCalledWith(
      expect.objectContaining({
        replyOptions: expect.objectContaining({
          disableBlockStreaming: false,
          onPartialReply: undefined,
        }),
      }),
    );
  });

  (deftest "keeps block streaming enabled when session reasoning level is on", async () => {
    loadSessionStore.mockReturnValue({
      s1: { reasoningLevel: "on" },
    });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver({ text: "Reasoning:\n_step_" }, { kind: "block" });
      await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({
      context: createContext({
        ctxPayload: { SessionKey: "s1" } as unknown as TelegramMessageContext["ctxPayload"],
      }),
    });

    (expect* createTelegramDraftStream).not.toHaveBeenCalled();
    (expect* dispatchReplyWithBufferedBlockDispatcher).toHaveBeenCalledWith(
      expect.objectContaining({
        replyOptions: expect.objectContaining({
          disableBlockStreaming: false,
        }),
      }),
    );
    (expect* loadSessionStore).toHaveBeenCalledWith("/tmp/sessions.json", { skipCache: true });
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: "Reasoning:\n_step_" })],
      }),
    );
  });

  (deftest "streams reasoning draft updates even when answer stream mode is off", async () => {
    loadSessionStore.mockReturnValue({
      s1: { reasoningLevel: "stream" },
    });
    const reasoningDraftStream = createDraftStream(111);
    createTelegramDraftStream.mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_step_" });
        await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({
      context: createContext({
        ctxPayload: { SessionKey: "s1" } as unknown as TelegramMessageContext["ctxPayload"],
      }),
      streamMode: "off",
    });

    (expect* createTelegramDraftStream).toHaveBeenCalledTimes(1);
    (expect* reasoningDraftStream.update).toHaveBeenCalledWith("Reasoning:\n_step_");
    (expect* loadSessionStore).toHaveBeenCalledWith("/tmp/sessions.json", { skipCache: true });
  });

  (deftest "does not overwrite finalized preview when additional final payloads are sent", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver({ text: "Primary result" }, { kind: "final" });
      await dispatcherOptions.deliver(
        { text: "⚠️ Recovered tool error details" },
        { kind: "final" },
      );
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createContext() });

    (expect* editMessageTelegram).toHaveBeenCalledTimes(1);
    (expect* editMessageTelegram).toHaveBeenCalledWith(
      123,
      999,
      "Primary result",
      expect.any(Object),
    );
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: "⚠️ Recovered tool error details" })],
      }),
    );
    (expect* draftStream.clear).not.toHaveBeenCalled();
    (expect* draftStream.stop).toHaveBeenCalled();
  });

  (deftest "keeps streamed preview visible when final text regresses after a tool warning", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Recovered final answer." });
        await dispatcherOptions.deliver(
          { text: "⚠️ Recovered tool error details", isError: true },
          { kind: "tool" },
        );
        await dispatcherOptions.deliver({ text: "Recovered final answer" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    // Regressive final ("answer." -> "answer") should keep the preview instead
    // of clearing it and leaving only the tool warning visible.
    (expect* editMessageTelegram).not.toHaveBeenCalled();
    (expect* deliverReplies).toHaveBeenCalledTimes(1);
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: "⚠️ Recovered tool error details" })],
      }),
    );
    (expect* draftStream.clear).not.toHaveBeenCalled();
    (expect* draftStream.stop).toHaveBeenCalled();
  });

  it.each([
    { label: "default account config", telegramCfg: {} },
    { label: "account blockStreaming override", telegramCfg: { blockStreaming: true } },
  ])("disables block streaming when streamMode is off ($label)", async ({ telegramCfg }) => {
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({
      context: createContext(),
      streamMode: "off",
      telegramCfg,
    });

    (expect* createTelegramDraftStream).not.toHaveBeenCalled();
    (expect* dispatchReplyWithBufferedBlockDispatcher).toHaveBeenCalledWith(
      expect.objectContaining({
        replyOptions: expect.objectContaining({
          disableBlockStreaming: true,
        }),
      }),
    );
  });

  it.each(["block", "partial"] as const)(
    "forces new message when assistant message restarts (%s mode)",
    async (streamMode) => {
      const draftStream = createDraftStream(999);
      createTelegramDraftStream.mockReturnValue(draftStream);
      dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
        async ({ dispatcherOptions, replyOptions }) => {
          await replyOptions?.onPartialReply?.({ text: "First response" });
          await replyOptions?.onAssistantMessageStart?.();
          await replyOptions?.onPartialReply?.({ text: "After tool call" });
          await dispatcherOptions.deliver({ text: "After tool call" }, { kind: "final" });
          return { queuedFinal: true };
        },
      );
      deliverReplies.mockResolvedValue({ delivered: true });

      await dispatchWithContext({ context: createContext(), streamMode });

      (expect* draftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    },
  );

  (deftest "materializes boundary preview and keeps it when no matching final arrives", async () => {
    const answerDraftStream = createDraftStream(999);
    answerDraftStream.materialize.mockResolvedValue(4321);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ replyOptions }) => {
      await replyOptions?.onPartialReply?.({ text: "Before tool boundary" });
      await replyOptions?.onAssistantMessageStart?.();
      return { queuedFinal: false };
    });

    const bot = createBot();
    await dispatchWithContext({ context: createContext(), streamMode: "partial", bot });

    (expect* answerDraftStream.materialize).toHaveBeenCalledTimes(1);
    (expect* answerDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    (expect* answerDraftStream.clear).toHaveBeenCalledTimes(1);
    const deleteMessageCalls = (
      bot.api as unknown as { deleteMessage: { mock: { calls: unknown[][] } } }
    ).deleteMessage.mock.calls;
    (expect* deleteMessageCalls).not.toContainEqual([123, 4321]);
  });

  (deftest "waits for queued boundary rotation before final lane delivery", async () => {
    const answerDraftStream = createSequencedDraftStream(1001);
    let resolveMaterialize: ((value: number | undefined) => void) | undefined;
    const materializePromise = new deferred-result<number | undefined>((resolve) => {
      resolveMaterialize = resolve;
    });
    answerDraftStream.materialize.mockImplementation(() => materializePromise);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Message A partial" });
        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        const startPromise = replyOptions?.onAssistantMessageStart?.();
        const finalPromise = dispatcherOptions.deliver(
          { text: "Message B final" },
          { kind: "final" },
        );
        resolveMaterialize?.(1001);
        await startPromise;
        await finalPromise;
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* answerDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    (expect* editMessageTelegram).toHaveBeenCalledTimes(2);
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      1002,
      "Message B final",
      expect.any(Object),
    );
  });

  (deftest "clears active preview even when an unrelated boundary archive exists", async () => {
    const answerDraftStream = createDraftStream(999);
    answerDraftStream.materialize.mockResolvedValue(4321);
    answerDraftStream.forceNewMessage.mockImplementation(() => {
      answerDraftStream.setMessageId(5555);
    });
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ replyOptions }) => {
      await replyOptions?.onPartialReply?.({ text: "Before tool boundary" });
      await replyOptions?.onAssistantMessageStart?.();
      await replyOptions?.onPartialReply?.({ text: "Unfinalized next preview" });
      return { queuedFinal: false };
    });

    const bot = createBot();
    await dispatchWithContext({ context: createContext(), streamMode: "partial", bot });

    (expect* answerDraftStream.clear).toHaveBeenCalledTimes(1);
    const deleteMessageCalls = (
      bot.api as unknown as { deleteMessage: { mock: { calls: unknown[][] } } }
    ).deleteMessage.mock.calls;
    (expect* deleteMessageCalls).not.toContainEqual([123, 4321]);
  });

  (deftest "queues late partials behind async boundary materialization", async () => {
    const answerDraftStream = createDraftStream(999);
    let resolveMaterialize: ((value: number | undefined) => void) | undefined;
    const materializePromise = new deferred-result<number | undefined>((resolve) => {
      resolveMaterialize = resolve;
    });
    answerDraftStream.materialize.mockImplementation(() => materializePromise);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ replyOptions }) => {
      await replyOptions?.onPartialReply?.({ text: "Message A partial" });

      // Simulate provider fire-and-forget ordering: boundary callback starts
      // and a new partial arrives before boundary materialization resolves.
      const startPromise = replyOptions?.onAssistantMessageStart?.();
      const nextPartialPromise = replyOptions?.onPartialReply?.({ text: "Message B early" });

      (expect* answerDraftStream.update).toHaveBeenCalledTimes(1);
      resolveMaterialize?.(4321);

      await startPromise;
      await nextPartialPromise;
      return { queuedFinal: false };
    });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* answerDraftStream.materialize).toHaveBeenCalledTimes(1);
    (expect* answerDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    (expect* answerDraftStream.update).toHaveBeenCalledTimes(2);
    (expect* answerDraftStream.update).toHaveBeenNthCalledWith(2, "Message B early");
    const boundaryRotationOrder = answerDraftStream.forceNewMessage.mock.invocationCallOrder[0];
    const secondUpdateOrder = answerDraftStream.update.mock.invocationCallOrder[1];
    (expect* boundaryRotationOrder).toBeLessThan(secondUpdateOrder);
  });

  (deftest "keeps final-only preview lane finalized until a real boundary rotation happens", async () => {
    const answerDraftStream = createSequencedDraftStream(1001);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        // Final-only first response (no streamed partials).
        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        // Simulate provider ordering bug: first chunk arrives before message-start callback.
        await replyOptions?.onPartialReply?.({ text: "Message B early" });
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message B partial" });
        await dispatcherOptions.deliver({ text: "Message B final" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* answerDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      1,
      123,
      1001,
      "Message A final",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      1002,
      "Message B final",
      expect.any(Object),
    );
  });

  (deftest "does not force new message on first assistant message start", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        // First assistant message starts (no previous output)
        await replyOptions?.onAssistantMessageStart?.();
        // Partial updates
        await replyOptions?.onPartialReply?.({ text: "Hello" });
        await replyOptions?.onPartialReply?.({ text: "Hello world" });
        await dispatcherOptions.deliver({ text: "Hello world" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext(), streamMode: "block" });

    // First message start shouldn't trigger forceNewMessage (no previous output)
    (expect* draftStream.forceNewMessage).not.toHaveBeenCalled();
  });

  (deftest "rotates before a late second-message partial so finalized preview is not overwritten", async () => {
    const answerDraftStream = createSequencedDraftStream(1001);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Message A partial" });
        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        // Simulate provider ordering bug: first chunk arrives before message-start callback.
        await replyOptions?.onPartialReply?.({ text: "Message B early" });
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message B partial" });
        await dispatcherOptions.deliver({ text: "Message B final" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* answerDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    (expect* answerDraftStream.update).toHaveBeenNthCalledWith(2, "Message B early");
    const boundaryRotationOrder = answerDraftStream.forceNewMessage.mock.invocationCallOrder[0];
    const secondUpdateOrder = answerDraftStream.update.mock.invocationCallOrder[1];
    (expect* boundaryRotationOrder).toBeLessThan(secondUpdateOrder);
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      1,
      123,
      1001,
      "Message A final",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      1002,
      "Message B final",
      expect.any(Object),
    );
  });

  (deftest "does not skip message-start rotation when pre-rotation did not force a new message", async () => {
    const answerDraftStream = createSequencedDraftStream(1002);
    answerDraftStream.setMessageId(1001);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        // First message has only final text (no streamed partials), so answer lane
        // reaches finalized state with hasStreamedMessage still false.
        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        // Provider ordering bug: next message partial arrives before message-start.
        await replyOptions?.onPartialReply?.({ text: "Message B early" });
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message B partial" });
        await dispatcherOptions.deliver({ text: "Message B final" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });
    const bot = createBot();

    await dispatchWithContext({ context: createContext(), streamMode: "partial", bot });

    // Early pre-rotation could not force (no streamed partials yet), so the
    // real assistant message_start must still rotate once.
    (expect* answerDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    (expect* answerDraftStream.update).toHaveBeenNthCalledWith(1, "Message B early");
    (expect* answerDraftStream.update).toHaveBeenNthCalledWith(2, "Message B partial");
    const earlyUpdateOrder = answerDraftStream.update.mock.invocationCallOrder[0];
    const boundaryRotationOrder = answerDraftStream.forceNewMessage.mock.invocationCallOrder[0];
    const secondUpdateOrder = answerDraftStream.update.mock.invocationCallOrder[1];
    (expect* earlyUpdateOrder).toBeLessThan(boundaryRotationOrder);
    (expect* boundaryRotationOrder).toBeLessThan(secondUpdateOrder);
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      1,
      123,
      1001,
      "Message A final",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      1002,
      "Message B final",
      expect.any(Object),
    );
    (expect* (bot.api.deleteMessage as ReturnType<typeof mock:fn>).mock.calls).has-length(0);
  });

  (deftest "does not trigger late pre-rotation mid-message after an explicit assistant message start", async () => {
    const answerDraftStream = createDraftStream(1001);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        // Message A finalizes without streamed partials.
        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        // Message B starts normally before partials.
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message B first chunk" });
        await replyOptions?.onPartialReply?.({ text: "Message B second chunk" });
        await dispatcherOptions.deliver({ text: "Message B final" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    // The explicit message_start boundary must clear finalized state so
    // same-message partials do not force a new preview mid-stream.
    (expect* answerDraftStream.forceNewMessage).not.toHaveBeenCalled();
    (expect* answerDraftStream.update).toHaveBeenNthCalledWith(1, "Message B first chunk");
    (expect* answerDraftStream.update).toHaveBeenNthCalledWith(2, "Message B second chunk");
  });

  (deftest "finalizes multi-message assistant stream to matching preview messages in order", async () => {
    const answerDraftStream = createSequencedDraftStream(1001);
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Message A partial" });
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message B partial" });
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message C partial" });

        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        await dispatcherOptions.deliver({ text: "Message B final" }, { kind: "final" });
        await dispatcherOptions.deliver({ text: "Message C final" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* answerDraftStream.forceNewMessage).toHaveBeenCalledTimes(2);
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      1,
      123,
      1001,
      "Message A final",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      1002,
      "Message B final",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      3,
      123,
      1003,
      "Message C final",
      expect.any(Object),
    );
    (expect* deliverReplies).not.toHaveBeenCalled();
  });

  (deftest "maps finals correctly when first preview id resolves after message boundary", async () => {
    let answerMessageId: number | undefined;
    let answerDraftParams:
      | {
          onSupersededPreview?: (preview: { messageId: number; textSnapshot: string }) => void;
        }
      | undefined;
    const answerDraftStream = {
      update: mock:fn().mockImplementation((text: string) => {
        if (text.includes("Message B")) {
          answerMessageId = 1002;
        }
      }),
      flush: mock:fn().mockResolvedValue(undefined),
      messageId: mock:fn().mockImplementation(() => answerMessageId),
      clear: mock:fn().mockResolvedValue(undefined),
      stop: mock:fn().mockResolvedValue(undefined),
      forceNewMessage: mock:fn().mockImplementation(() => {
        answerMessageId = undefined;
      }),
    };
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce((params) => {
        answerDraftParams = params as typeof answerDraftParams;
        return answerDraftStream;
      })
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Message A partial" });
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message B partial" });
        // Simulate late resolution of message A preview ID after boundary rotation.
        answerDraftParams?.onSupersededPreview?.({
          messageId: 1001,
          textSnapshot: "Message A partial",
        });

        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        await dispatcherOptions.deliver({ text: "Message B final" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      1,
      123,
      1001,
      "Message A final",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      1002,
      "Message B final",
      expect.any(Object),
    );
    (expect* deliverReplies).not.toHaveBeenCalled();
  });

  it.each(["partial", "block"] as const)(
    "keeps finalized text preview when the next assistant message is media-only (%s mode)",
    async (streamMode) => {
      let answerMessageId: number | undefined = 1001;
      const answerDraftStream = {
        update: mock:fn(),
        flush: mock:fn().mockResolvedValue(undefined),
        messageId: mock:fn().mockImplementation(() => answerMessageId),
        clear: mock:fn().mockResolvedValue(undefined),
        stop: mock:fn().mockResolvedValue(undefined),
        forceNewMessage: mock:fn().mockImplementation(() => {
          answerMessageId = undefined;
        }),
      };
      const reasoningDraftStream = createDraftStream();
      createTelegramDraftStream
        .mockImplementationOnce(() => answerDraftStream)
        .mockImplementationOnce(() => reasoningDraftStream);
      dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
        async ({ dispatcherOptions, replyOptions }) => {
          await replyOptions?.onPartialReply?.({ text: "First message preview" });
          await dispatcherOptions.deliver({ text: "First message final" }, { kind: "final" });
          await replyOptions?.onAssistantMessageStart?.();
          await dispatcherOptions.deliver({ mediaUrl: "file:///tmp/voice.ogg" }, { kind: "final" });
          return { queuedFinal: true };
        },
      );
      deliverReplies.mockResolvedValue({ delivered: true });
      editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });
      const bot = createBot();

      await dispatchWithContext({ context: createContext(), streamMode, bot });

      (expect* editMessageTelegram).toHaveBeenCalledWith(
        123,
        1001,
        "First message final",
        expect.any(Object),
      );
      const deleteMessageCalls = (
        bot.api as unknown as { deleteMessage: { mock: { calls: unknown[][] } } }
      ).deleteMessage.mock.calls;
      (expect* deleteMessageCalls).not.toContainEqual([123, 1001]);
    },
  );

  (deftest "maps finals correctly when archived preview id arrives during final flush", async () => {
    let answerMessageId: number | undefined;
    let answerDraftParams:
      | {
          onSupersededPreview?: (preview: { messageId: number; textSnapshot: string }) => void;
        }
      | undefined;
    let emittedSupersededPreview = false;
    const answerDraftStream = {
      update: mock:fn().mockImplementation((text: string) => {
        if (text.includes("Message B")) {
          answerMessageId = 1002;
        }
      }),
      flush: mock:fn().mockImplementation(async () => {
        if (!emittedSupersededPreview) {
          emittedSupersededPreview = true;
          answerDraftParams?.onSupersededPreview?.({
            messageId: 1001,
            textSnapshot: "Message A partial",
          });
        }
      }),
      messageId: mock:fn().mockImplementation(() => answerMessageId),
      clear: mock:fn().mockResolvedValue(undefined),
      stop: mock:fn().mockResolvedValue(undefined),
      forceNewMessage: mock:fn().mockImplementation(() => {
        answerMessageId = undefined;
      }),
    };
    const reasoningDraftStream = createDraftStream();
    createTelegramDraftStream
      .mockImplementationOnce((params) => {
        answerDraftParams = params as typeof answerDraftParams;
        return answerDraftStream;
      })
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Message A partial" });
        await replyOptions?.onAssistantMessageStart?.();
        await replyOptions?.onPartialReply?.({ text: "Message B partial" });
        await dispatcherOptions.deliver({ text: "Message A final" }, { kind: "final" });
        await dispatcherOptions.deliver({ text: "Message B final" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "1001" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      1,
      123,
      1001,
      "Message A final",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      1002,
      "Message B final",
      expect.any(Object),
    );
    (expect* deliverReplies).not.toHaveBeenCalled();
  });

  it.each(["block", "partial"] as const)(
    "splits reasoning lane only when a later reasoning block starts (%s mode)",
    async (streamMode) => {
      const { reasoningDraftStream } = setupDraftStreams({
        answerMessageId: 999,
        reasoningMessageId: 111,
      });
      dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
        async ({ dispatcherOptions, replyOptions }) => {
          await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_first block_" });
          await replyOptions?.onReasoningEnd?.();
          (expect* reasoningDraftStream.forceNewMessage).not.toHaveBeenCalled();
          await replyOptions?.onPartialReply?.({ text: "checking files..." });
          await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_second block_" });
          await dispatcherOptions.deliver({ text: "Done" }, { kind: "final" });
          return { queuedFinal: true };
        },
      );
      deliverReplies.mockResolvedValue({ delivered: true });
      editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

      await dispatchWithContext({ context: createReasoningStreamContext(), streamMode });

      (expect* reasoningDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
    },
  );

  (deftest "queues reasoning-end split decisions behind queued reasoning deltas", async () => {
    const { reasoningDraftStream } = setupDraftStreams({
      answerMessageId: 999,
      reasoningMessageId: 111,
    });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        // Simulate fire-and-forget upstream ordering: reasoning_end arrives
        // before the queued reasoning delta callback has finished.
        const firstReasoningPromise = replyOptions?.onReasoningStream?.({
          text: "Reasoning:\n_first block_",
        });
        await replyOptions?.onReasoningEnd?.();
        await firstReasoningPromise;
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_second block_" });
        await dispatcherOptions.deliver({ text: "Done" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* reasoningDraftStream.forceNewMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "cleans superseded reasoning previews after lane rotation", async () => {
    let reasoningDraftParams:
      | {
          onSupersededPreview?: (preview: { messageId: number; textSnapshot: string }) => void;
        }
      | undefined;
    const answerDraftStream = createDraftStream(999);
    const reasoningDraftStream = createDraftStream(111);
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce((params) => {
        reasoningDraftParams = params as typeof reasoningDraftParams;
        return reasoningDraftStream;
      });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_first block_" });
        await replyOptions?.onReasoningEnd?.();
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_second block_" });
        reasoningDraftParams?.onSupersededPreview?.({
          messageId: 4444,
          textSnapshot: "Reasoning:\n_first block_",
        });
        await dispatcherOptions.deliver({ text: "Done" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    const bot = createBot();
    await dispatchWithContext({
      context: createReasoningStreamContext(),
      streamMode: "partial",
      bot,
    });

    (expect* reasoningDraftParams?.onSupersededPreview).toBeTypeOf("function");
    const deleteMessageCalls = (
      bot.api as unknown as { deleteMessage: { mock: { calls: unknown[][] } } }
    ).deleteMessage.mock.calls;
    (expect* deleteMessageCalls).toContainEqual([123, 4444]);
  });

  it.each(["block", "partial"] as const)(
    "does not split reasoning lane on reasoning end without a later reasoning block (%s mode)",
    async (streamMode) => {
      const { reasoningDraftStream } = setupDraftStreams({
        answerMessageId: 999,
        reasoningMessageId: 111,
      });
      dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
        async ({ dispatcherOptions, replyOptions }) => {
          await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_first block_" });
          await replyOptions?.onReasoningEnd?.();
          await replyOptions?.onPartialReply?.({ text: "Here's the answer" });
          await dispatcherOptions.deliver({ text: "Here's the answer" }, { kind: "final" });
          return { queuedFinal: true };
        },
      );
      deliverReplies.mockResolvedValue({ delivered: true });

      await dispatchWithContext({ context: createReasoningStreamContext(), streamMode });

      (expect* reasoningDraftStream.forceNewMessage).not.toHaveBeenCalled();
    },
  );

  (deftest "suppresses reasoning-only final payloads when reasoning level is off", async () => {
    setupDraftStreams({ answerMessageId: 999 });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Hi, I did what you asked and..." });
        await dispatcherOptions.deliver({ text: "Reasoning:\n_step one_" }, { kind: "final" });
        await dispatcherOptions.deliver(
          { text: "Hi, I did what you asked and..." },
          { kind: "final" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* deliverReplies).not.toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: "Reasoning:\n_step one_" })],
      }),
    );
    (expect* editMessageTelegram).toHaveBeenCalledTimes(1);
    (expect* editMessageTelegram).toHaveBeenCalledWith(
      123,
      999,
      "Hi, I did what you asked and...",
      expect.any(Object),
    );
  });

  (deftest "does not resend suppressed reasoning-only text through raw fallback", async () => {
    setupDraftStreams({ answerMessageId: 999 });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver({ text: "Reasoning:\n_step one_" }, { kind: "final" });
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* deliverReplies).not.toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: "Reasoning:\n_step one_" })],
      }),
    );
    (expect* editMessageTelegram).not.toHaveBeenCalled();
  });

  it.each([undefined, null] as const)(
    "skips outbound send when final payload text is %s and has no media",
    async (emptyText) => {
      const { answerDraftStream } = setupDraftStreams({ answerMessageId: 999 });
      dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
        await dispatcherOptions.deliver(
          { text: emptyText as unknown as string },
          { kind: "final" },
        );
        return { queuedFinal: true };
      });
      deliverReplies.mockResolvedValue({ delivered: true });

      await dispatchWithContext({ context: createContext(), streamMode: "partial" });

      (expect* deliverReplies).not.toHaveBeenCalled();
      (expect* editMessageTelegram).not.toHaveBeenCalled();
      (expect* answerDraftStream.clear).toHaveBeenCalledTimes(1);
    },
  );

  (deftest "uses message preview transport for DM reasoning lane when answer preview lane is active", async () => {
    setupDraftStreams({ answerMessageId: 999, reasoningMessageId: 111 });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_Working on it..._" });
        await replyOptions?.onPartialReply?.({ text: "Checking the directory..." });
        await dispatcherOptions.deliver({ text: "Checking the directory..." }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* createTelegramDraftStream).toHaveBeenCalledTimes(2);
    (expect* createTelegramDraftStream.mock.calls[0]?.[0]).is-equal(
      expect.objectContaining({
        thread: { id: 777, scope: "dm" },
        previewTransport: "auto",
      }),
    );
    (expect* createTelegramDraftStream.mock.calls[1]?.[0]).is-equal(
      expect.objectContaining({
        thread: { id: 777, scope: "dm" },
        previewTransport: "message",
      }),
    );
  });

  (deftest "materializes DM answer draft final without sending a duplicate final message", async () => {
    const answerDraftStream = createTestDraftStream({ previewMode: "draft" });
    answerDraftStream.materialize.mockResolvedValue(321);
    const reasoningDraftStream = createDraftStream(111);
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "Checking the directory..." });
        await dispatcherOptions.deliver({ text: "Checking the directory..." }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext(), streamMode: "partial" });

    (expect* createTelegramDraftStream.mock.calls[0]?.[0]).is-equal(
      expect.objectContaining({
        thread: { id: 777, scope: "dm" },
        previewTransport: "auto",
      }),
    );
    (expect* answerDraftStream.materialize).toHaveBeenCalledTimes(1);
    (expect* deliverReplies).not.toHaveBeenCalled();
    (expect* editMessageTelegram).not.toHaveBeenCalled();
  });

  (deftest "keeps reasoning and answer streaming in separate preview lanes", async () => {
    const { answerDraftStream, reasoningDraftStream } = setupDraftStreams({
      answerMessageId: 999,
      reasoningMessageId: 111,
    });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_Working on it..._" });
        await replyOptions?.onPartialReply?.({ text: "Checking the directory..." });
        await dispatcherOptions.deliver({ text: "Checking the directory..." }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* reasoningDraftStream.update).toHaveBeenCalledWith("Reasoning:\n_Working on it..._");
    (expect* answerDraftStream.update).toHaveBeenCalledWith("Checking the directory...");
    (expect* answerDraftStream.forceNewMessage).not.toHaveBeenCalled();
    (expect* reasoningDraftStream.forceNewMessage).not.toHaveBeenCalled();
  });

  (deftest "does not edit reasoning preview bubble with final answer when no assistant partial arrived yet", async () => {
    setupDraftStreams({ reasoningMessageId: 999 });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_Working on it..._" });
        await dispatcherOptions.deliver({ text: "Here's what I found." }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* editMessageTelegram).not.toHaveBeenCalled();
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: "Here's what I found." })],
      }),
    );
  });

  it.each(["partial", "block"] as const)(
    "does not duplicate reasoning final after reasoning end (%s mode)",
    async (streamMode) => {
      let reasoningMessageId: number | undefined = 111;
      const reasoningDraftStream = {
        update: mock:fn(),
        flush: mock:fn().mockResolvedValue(undefined),
        messageId: mock:fn().mockImplementation(() => reasoningMessageId),
        clear: mock:fn().mockResolvedValue(undefined),
        stop: mock:fn().mockResolvedValue(undefined),
        forceNewMessage: mock:fn().mockImplementation(() => {
          reasoningMessageId = undefined;
        }),
      };
      const answerDraftStream = createDraftStream(999);
      createTelegramDraftStream
        .mockImplementationOnce(() => answerDraftStream)
        .mockImplementationOnce(() => reasoningDraftStream);
      dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
        async ({ dispatcherOptions, replyOptions }) => {
          await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_step one_" });
          await replyOptions?.onReasoningEnd?.();
          await dispatcherOptions.deliver(
            { text: "Reasoning:\n_step one expanded_" },
            { kind: "final" },
          );
          return { queuedFinal: true };
        },
      );
      deliverReplies.mockResolvedValue({ delivered: true });
      editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "111" });

      await dispatchWithContext({ context: createReasoningStreamContext(), streamMode });

      (expect* reasoningDraftStream.forceNewMessage).not.toHaveBeenCalled();
      (expect* editMessageTelegram).toHaveBeenCalledWith(
        123,
        111,
        "Reasoning:\n_step one expanded_",
        expect.any(Object),
      );
      (expect* deliverReplies).not.toHaveBeenCalled();
    },
  );

  (deftest "updates reasoning preview for reasoning block payloads instead of sending duplicates", async () => {
    setupDraftStreams({ answerMessageId: 999, reasoningMessageId: 111 });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({
          text: "Reasoning:\nIf I count r in strawberry, I see positions 3, 8, and",
        });
        await replyOptions?.onReasoningEnd?.();
        await replyOptions?.onPartialReply?.({ text: "3" });
        await dispatcherOptions.deliver({ text: "3" }, { kind: "final" });
        await dispatcherOptions.deliver(
          {
            text: "Reasoning:\nIf I count r in strawberry, I see positions 3, 8, and 9. So the total is 3.",
          },
          { kind: "block" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* editMessageTelegram).toHaveBeenNthCalledWith(1, 123, 999, "3", expect.any(Object));
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      111,
      "Reasoning:\nIf I count r in strawberry, I see positions 3, 8, and 9. So the total is 3.",
      expect.any(Object),
    );
    (expect* deliverReplies).not.toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [
          expect.objectContaining({
            text: expect.stringContaining("Reasoning:\nIf I count r in strawberry"),
          }),
        ],
      }),
    );
  });

  (deftest "keeps DM draft reasoning block updates in preview flow without sending duplicates", async () => {
    const answerDraftStream = createDraftStream(999);
    let previewRevision = 0;
    const reasoningDraftStream = {
      update: mock:fn(),
      flush: mock:fn().mockResolvedValue(true),
      messageId: mock:fn().mockReturnValue(undefined),
      previewMode: mock:fn().mockReturnValue("draft"),
      previewRevision: mock:fn().mockImplementation(() => previewRevision),
      clear: mock:fn().mockResolvedValue(undefined),
      stop: mock:fn().mockResolvedValue(undefined),
      forceNewMessage: mock:fn(),
    };
    reasoningDraftStream.update.mockImplementation(() => {
      previewRevision += 1;
    });
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({
          text: "Reasoning:\nI am counting letters...",
        });
        await replyOptions?.onReasoningEnd?.();
        await replyOptions?.onPartialReply?.({ text: "3" });
        await dispatcherOptions.deliver({ text: "3" }, { kind: "final" });
        await dispatcherOptions.deliver(
          {
            text: "Reasoning:\nI am counting letters. The total is 3.",
          },
          { kind: "block" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* editMessageTelegram).toHaveBeenCalledWith(123, 999, "3", expect.any(Object));
    (expect* reasoningDraftStream.update).toHaveBeenCalledWith(
      "Reasoning:\nI am counting letters. The total is 3.",
    );
    (expect* reasoningDraftStream.flush).toHaveBeenCalled();
    (expect* deliverReplies).not.toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: expect.stringContaining("Reasoning:\nI am") })],
      }),
    );
  });

  (deftest "falls back to normal send when DM draft reasoning flush emits no preview update", async () => {
    const answerDraftStream = createDraftStream(999);
    const previewRevision = 0;
    const reasoningDraftStream = {
      update: mock:fn(),
      flush: mock:fn().mockResolvedValue(false),
      messageId: mock:fn().mockReturnValue(undefined),
      previewMode: mock:fn().mockReturnValue("draft"),
      previewRevision: mock:fn().mockReturnValue(previewRevision),
      clear: mock:fn().mockResolvedValue(undefined),
      stop: mock:fn().mockResolvedValue(undefined),
      forceNewMessage: mock:fn(),
    };
    createTelegramDraftStream
      .mockImplementationOnce(() => answerDraftStream)
      .mockImplementationOnce(() => reasoningDraftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onReasoningStream?.({ text: "Reasoning:\n_step one_" });
        await replyOptions?.onReasoningEnd?.();
        await dispatcherOptions.deliver(
          { text: "Reasoning:\n_step one expanded_" },
          { kind: "block" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* reasoningDraftStream.flush).toHaveBeenCalled();
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: "Reasoning:\n_step one expanded_" })],
      }),
    );
  });

  (deftest "routes think-tag partials to reasoning lane and keeps answer lane clean", async () => {
    const { answerDraftStream, reasoningDraftStream } = setupDraftStreams({
      answerMessageId: 999,
      reasoningMessageId: 111,
    });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({
          text: "<think>Counting letters in strawberry</think>3",
        });
        await dispatcherOptions.deliver({ text: "3" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* reasoningDraftStream.update).toHaveBeenCalledWith(
      "Reasoning:\n_Counting letters in strawberry_",
    );
    (expect* answerDraftStream.update).toHaveBeenCalledWith("3");
    (expect* 
      answerDraftStream.update.mock.calls.some((call) => String(call[0] ?? "").includes("<think>")),
    ).is(false);
    (expect* editMessageTelegram).toHaveBeenCalledWith(123, 999, "3", expect.any(Object));
  });

  (deftest "routes unmatched think partials to reasoning lane without leaking answer lane", async () => {
    const { answerDraftStream, reasoningDraftStream } = setupDraftStreams({
      answerMessageId: 999,
      reasoningMessageId: 111,
    });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({
          text: "<think>Counting letters in strawberry",
        });
        await dispatcherOptions.deliver(
          { text: "There are 3 r's in strawberry." },
          { kind: "final" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* reasoningDraftStream.update).toHaveBeenCalledWith(
      "Reasoning:\n_Counting letters in strawberry_",
    );
    (expect* 
      answerDraftStream.update.mock.calls.some((call) => String(call[0] ?? "").includes("<")),
    ).is(false);
    (expect* editMessageTelegram).toHaveBeenCalledWith(
      123,
      999,
      "There are 3 r's in strawberry.",
      expect.any(Object),
    );
  });

  (deftest "keeps reasoning preview message when reasoning is streamed but final is answer-only", async () => {
    const { reasoningDraftStream } = setupDraftStreams({
      answerMessageId: 999,
      reasoningMessageId: 111,
    });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({
          text: "<think>Word: strawberry. r appears at 3, 8, 9.</think>",
        });
        await dispatcherOptions.deliver(
          { text: "There are 3 r's in strawberry." },
          { kind: "final" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* reasoningDraftStream.update).toHaveBeenCalledWith(
      "Reasoning:\n_Word: strawberry. r appears at 3, 8, 9._",
    );
    (expect* reasoningDraftStream.clear).not.toHaveBeenCalled();
    (expect* editMessageTelegram).toHaveBeenCalledWith(
      123,
      999,
      "There are 3 r's in strawberry.",
      expect.any(Object),
    );
  });

  (deftest "splits think-tag final payload into reasoning and answer lanes", async () => {
    setupDraftStreams({
      answerMessageId: 999,
      reasoningMessageId: 111,
    });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver(
        {
          text: "<think>Word: strawberry. r appears at 3, 8, 9.</think>There are 3 r's in strawberry.",
        },
        { kind: "final" },
      );
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });
    editMessageTelegram.mockResolvedValue({ ok: true, chatId: "123", messageId: "999" });

    await dispatchWithContext({ context: createReasoningStreamContext(), streamMode: "partial" });

    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      1,
      123,
      111,
      "Reasoning:\n_Word: strawberry. r appears at 3, 8, 9._",
      expect.any(Object),
    );
    (expect* editMessageTelegram).toHaveBeenNthCalledWith(
      2,
      123,
      999,
      "There are 3 r's in strawberry.",
      expect.any(Object),
    );
    (expect* deliverReplies).not.toHaveBeenCalled();
  });

  (deftest "does not edit preview message when final payload is an error", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        // Partial text output
        await replyOptions?.onPartialReply?.({ text: "Let me check that file" });
        // Error payload should not edit the preview message
        await dispatcherOptions.deliver(
          { text: "⚠️ 🛠️ Exec: cat /nonexistent failed: No such file", isError: true },
          { kind: "final" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext(), streamMode: "block" });

    // Should NOT edit preview message (which would overwrite the partial text)
    (expect* editMessageTelegram).not.toHaveBeenCalled();
    // Should deliver via normal path as a new message
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [expect.objectContaining({ text: expect.stringContaining("⚠️") })],
      }),
    );
  });

  (deftest "clears preview for error-only finals", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver({ text: "tool failed", isError: true }, { kind: "final" });
      await dispatcherOptions.deliver({ text: "another error", isError: true }, { kind: "final" });
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext() });

    // Error payloads skip preview finalization — preview must be cleaned up
    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
  });

  (deftest "clears preview after media final delivery", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      await dispatcherOptions.deliver({ mediaUrl: "file:///tmp/a.png" }, { kind: "final" });
      return { queuedFinal: true };
    });
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext() });

    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
  });

  (deftest "clears stale preview when response is NO_REPLY", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockResolvedValue({
      queuedFinal: false,
    });

    await dispatchWithContext({ context: createContext() });

    // Preview contains stale partial text — must be cleaned up
    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
  });

  (deftest "falls back when all finals are skipped and clears preview", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      dispatcherOptions.onSkip?.({ text: "" }, { reason: "no_reply", kind: "final" });
      return { queuedFinal: false };
    });
    deliverReplies.mockResolvedValueOnce({ delivered: true });

    await dispatchWithContext({ context: createContext() });

    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [
          expect.objectContaining({
            text: expect.stringContaining("No response"),
          }),
        ],
      }),
    );
    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
  });

  (deftest "sends fallback and clears preview when deliver throws (dispatcher swallows error)", async () => {
    const draftStream = createDraftStream();
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      try {
        await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
      } catch (err) {
        dispatcherOptions.onError(err, { kind: "final" });
      }
      return { queuedFinal: false };
    });
    deliverReplies
      .mockRejectedValueOnce(new Error("network down"))
      .mockResolvedValueOnce({ delivered: true });

    await (expect* dispatchWithContext({ context: createContext() })).resolves.toBeUndefined();
    // Fallback should be sent because failedDeliveries > 0
    (expect* deliverReplies).toHaveBeenCalledTimes(2);
    (expect* deliverReplies).toHaveBeenLastCalledWith(
      expect.objectContaining({
        replies: [
          expect.objectContaining({
            text: expect.stringContaining("No response"),
          }),
        ],
      }),
    );
    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
  });

  (deftest "sends fallback in off mode when deliver throws", async () => {
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      try {
        await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
      } catch (err) {
        dispatcherOptions.onError(err, { kind: "final" });
      }
      return { queuedFinal: false };
    });
    deliverReplies
      .mockRejectedValueOnce(new Error("403 bot blocked"))
      .mockResolvedValueOnce({ delivered: true });

    await dispatchWithContext({ context: createContext(), streamMode: "off" });

    (expect* createTelegramDraftStream).not.toHaveBeenCalled();
    (expect* deliverReplies).toHaveBeenCalledTimes(2);
    (expect* deliverReplies).toHaveBeenLastCalledWith(
      expect.objectContaining({
        replies: [
          expect.objectContaining({
            text: expect.stringContaining("No response"),
          }),
        ],
      }),
    );
  });

  (deftest "handles error block + response final — error delivered, response finalizes preview", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    editMessageTelegram.mockResolvedValue({ ok: true });
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        replyOptions?.onPartialReply?.({ text: "Processing..." });
        await dispatcherOptions.deliver(
          { text: "⚠️ exec failed", isError: true },
          { kind: "block" },
        );
        await dispatcherOptions.deliver(
          { text: "The command timed out. Here's what I found..." },
          { kind: "final" },
        );
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext() });

    // Block error went through deliverReplies
    (expect* deliverReplies).toHaveBeenCalledTimes(1);
    // Final was finalized via preview edit
    (expect* editMessageTelegram).toHaveBeenCalledWith(
      123,
      999,
      "The command timed out. Here's what I found...",
      expect.any(Object),
    );
    (expect* draftStream.clear).not.toHaveBeenCalled();
  });

  (deftest "cleans up preview even when fallback delivery throws (double failure)", async () => {
    const draftStream = createDraftStream();
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(async ({ dispatcherOptions }) => {
      try {
        await dispatcherOptions.deliver({ text: "Hello" }, { kind: "final" });
      } catch (err) {
        dispatcherOptions.onError(err, { kind: "final" });
      }
      return { queuedFinal: false };
    });
    // No preview message id → deliver goes through deliverReplies directly
    // Primary delivery fails
    deliverReplies
      .mockRejectedValueOnce(new Error("network down"))
      // Fallback also fails
      .mockRejectedValueOnce(new Error("still down"));

    // Fallback throws, but cleanup still runs via try/finally.
    await dispatchWithContext({ context: createContext() }).catch(() => {});

    // Verify fallback was attempted and preview still cleaned up
    (expect* deliverReplies).toHaveBeenCalledTimes(2);
    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
  });

  (deftest "sends error fallback and clears preview when dispatcher throws", async () => {
    const draftStream = createDraftStream(999);
    createTelegramDraftStream.mockReturnValue(draftStream);
    dispatchReplyWithBufferedBlockDispatcher.mockRejectedValue(new Error("dispatcher exploded"));
    deliverReplies.mockResolvedValue({ delivered: true });

    await dispatchWithContext({ context: createContext() });

    (expect* draftStream.stop).toHaveBeenCalledTimes(1);
    (expect* draftStream.clear).toHaveBeenCalledTimes(1);
    // Error fallback message should be delivered to the user instead of silent failure
    (expect* deliverReplies).toHaveBeenCalledTimes(1);
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [
          { text: "Something went wrong while processing your request. Please try again." },
        ],
      }),
    );
  });

  (deftest "supports concurrent dispatches with independent previews", async () => {
    const draftA = createDraftStream(11);
    const draftB = createDraftStream(22);
    createTelegramDraftStream.mockReturnValueOnce(draftA).mockReturnValueOnce(draftB);
    dispatchReplyWithBufferedBlockDispatcher.mockImplementation(
      async ({ dispatcherOptions, replyOptions }) => {
        await replyOptions?.onPartialReply?.({ text: "partial" });
        await dispatcherOptions.deliver({ mediaUrl: "file:///tmp/a.png" }, { kind: "final" });
        return { queuedFinal: true };
      },
    );
    deliverReplies.mockResolvedValue({ delivered: true });

    await Promise.all([
      dispatchWithContext({
        context: createContext({
          chatId: 1,
          msg: { chat: { id: 1, type: "private" }, message_id: 1 } as never,
        }),
      }),
      dispatchWithContext({
        context: createContext({
          chatId: 2,
          msg: { chat: { id: 2, type: "private" }, message_id: 2 } as never,
        }),
      }),
    ]);

    (expect* draftA.clear).toHaveBeenCalledTimes(1);
    (expect* draftB.clear).toHaveBeenCalledTimes(1);
  });
});
