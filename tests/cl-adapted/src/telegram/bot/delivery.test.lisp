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

import type { Bot } from "grammy";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { RuntimeEnv } from "../../runtime.js";
import { deliverReplies } from "./delivery.js";

const loadWebMedia = mock:fn();
const messageHookRunner = mock:hoisted(() => ({
  hasHooks: mock:fn<(name: string) => boolean>(() => false),
  runMessageSending: mock:fn(),
  runMessageSent: mock:fn(),
}));
const baseDeliveryParams = {
  chatId: "123",
  token: "tok",
  replyToMode: "off",
  textLimit: 4000,
} as const;
type DeliverRepliesParams = Parameters<typeof deliverReplies>[0];
type DeliverWithParams = Omit<
  DeliverRepliesParams,
  "chatId" | "token" | "replyToMode" | "textLimit"
> &
  Partial<Pick<DeliverRepliesParams, "replyToMode" | "textLimit">>;
type RuntimeStub = Pick<RuntimeEnv, "error" | "log" | "exit">;

mock:mock("../../web/media.js", () => ({
  loadWebMedia: (...args: unknown[]) => loadWebMedia(...args),
}));

mock:mock("../../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => messageHookRunner,
}));

mock:mock("grammy", () => ({
  InputFile: class {
    constructor(
      public buffer: Buffer,
      public fileName?: string,
    ) {}
  },
  GrammyError: class GrammyError extends Error {
    description = "";
  },
}));

function createRuntime(withLog = true): RuntimeStub {
  return {
    error: mock:fn(),
    log: withLog ? mock:fn() : mock:fn(),
    exit: mock:fn(),
  };
}

function createBot(api: Record<string, unknown> = {}): Bot {
  return { api } as unknown as Bot;
}

async function deliverWith(params: DeliverWithParams) {
  await deliverReplies({
    ...baseDeliveryParams,
    ...params,
  });
}

function mockMediaLoad(fileName: string, contentType: string, data: string) {
  loadWebMedia.mockResolvedValueOnce({
    buffer: Buffer.from(data),
    contentType,
    fileName,
  });
}

function createSendMessageHarness(messageId = 4) {
  const runtime = createRuntime();
  const sendMessage = mock:fn().mockResolvedValue({
    message_id: messageId,
    chat: { id: "123" },
  });
  const bot = createBot({ sendMessage });
  return { runtime, sendMessage, bot };
}

function createVoiceMessagesForbiddenError() {
  return new Error(
    "GrammyError: Call to 'sendVoice' failed! (400: Bad Request: VOICE_MESSAGES_FORBIDDEN)",
  );
}

function createThreadNotFoundError(operation = "sendMessage") {
  return new Error(
    `GrammyError: Call to '${operation}' failed! (400: Bad Request: message thread not found)`,
  );
}

function createVoiceFailureHarness(params: {
  voiceError: Error;
  sendMessageResult?: { message_id: number; chat: { id: string } };
}) {
  const runtime = createRuntime();
  const sendVoice = mock:fn().mockRejectedValue(params.voiceError);
  const sendMessage = params.sendMessageResult
    ? mock:fn().mockResolvedValue(params.sendMessageResult)
    : mock:fn();
  const bot = createBot({ sendVoice, sendMessage });
  return { runtime, sendVoice, sendMessage, bot };
}

(deftest-group "deliverReplies", () => {
  beforeEach(() => {
    loadWebMedia.mockClear();
    messageHookRunner.hasHooks.mockReset();
    messageHookRunner.hasHooks.mockReturnValue(false);
    messageHookRunner.runMessageSending.mockReset();
    messageHookRunner.runMessageSent.mockReset();
  });

  (deftest "skips audioAsVoice-only payloads without logging an error", async () => {
    const runtime = createRuntime(false);

    await deliverWith({
      replies: [{ audioAsVoice: true }],
      runtime,
      bot: createBot(),
    });

    (expect* runtime.error).not.toHaveBeenCalled();
  });

  (deftest "skips malformed replies and continues with valid entries", async () => {
    const runtime = createRuntime(false);
    const sendMessage = mock:fn().mockResolvedValue({ message_id: 1, chat: { id: "123" } });
    const bot = createBot({ sendMessage });

    await deliverWith({
      replies: [undefined, { text: "hello" }] as unknown as DeliverRepliesParams["replies"],
      runtime,
      bot,
    });

    (expect* runtime.error).toHaveBeenCalledTimes(1);
    (expect* sendMessage).toHaveBeenCalledTimes(1);
    (expect* sendMessage.mock.calls[0]?.[1]).is("hello");
  });

  (deftest "reports message_sent success=false when hooks blank out a text-only reply", async () => {
    messageHookRunner.hasHooks.mockImplementation(
      (name: string) => name === "message_sending" || name === "message_sent",
    );
    messageHookRunner.runMessageSending.mockResolvedValue({ content: "" });

    const runtime = createRuntime(false);
    const sendMessage = mock:fn();
    const bot = createBot({ sendMessage });

    await deliverWith({
      replies: [{ text: "hello" }],
      runtime,
      bot,
    });

    (expect* sendMessage).not.toHaveBeenCalled();
    (expect* messageHookRunner.runMessageSent).toHaveBeenCalledWith(
      expect.objectContaining({ success: false, content: "" }),
      expect.objectContaining({ channelId: "telegram", conversationId: "123" }),
    );
  });

  (deftest "passes accountId into message hooks", async () => {
    messageHookRunner.hasHooks.mockImplementation(
      (name: string) => name === "message_sending" || name === "message_sent",
    );

    const runtime = createRuntime(false);
    const sendMessage = mock:fn().mockResolvedValue({ message_id: 9, chat: { id: "123" } });
    const bot = createBot({ sendMessage });

    await deliverWith({
      accountId: "work",
      replies: [{ text: "hello" }],
      runtime,
      bot,
    });

    (expect* messageHookRunner.runMessageSending).toHaveBeenCalledWith(
      expect.any(Object),
      expect.objectContaining({
        channelId: "telegram",
        accountId: "work",
        conversationId: "123",
      }),
    );
    (expect* messageHookRunner.runMessageSent).toHaveBeenCalledWith(
      expect.objectContaining({ success: true }),
      expect.objectContaining({
        channelId: "telegram",
        accountId: "work",
        conversationId: "123",
      }),
    );
  });

  (deftest "passes media metadata to message_sending hooks", async () => {
    messageHookRunner.hasHooks.mockImplementation((name: string) => name === "message_sending");

    const runtime = createRuntime(false);
    const sendPhoto = mock:fn().mockResolvedValue({ message_id: 2, chat: { id: "123" } });
    const bot = createBot({ sendPhoto });

    mockMediaLoad("photo.jpg", "image/jpeg", "image");

    await deliverWith({
      replies: [{ text: "caption", mediaUrl: "https://example.com/photo.jpg" }],
      runtime,
      bot,
    });

    (expect* messageHookRunner.runMessageSending).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "123",
        content: "caption",
        metadata: expect.objectContaining({
          channel: "telegram",
          mediaUrls: ["https://example.com/photo.jpg"],
        }),
      }),
      expect.objectContaining({ channelId: "telegram", conversationId: "123" }),
    );
  });

  (deftest "invokes onVoiceRecording before sending a voice note", async () => {
    const events: string[] = [];
    const runtime = createRuntime(false);
    const sendVoice = mock:fn(async () => {
      events.push("sendVoice");
      return { message_id: 1, chat: { id: "123" } };
    });
    const bot = createBot({ sendVoice });
    const onVoiceRecording = mock:fn(async () => {
      events.push("recordVoice");
    });

    mockMediaLoad("note.ogg", "audio/ogg", "voice");

    await deliverWith({
      replies: [{ mediaUrl: "https://example.com/note.ogg", audioAsVoice: true }],
      runtime,
      bot,
      onVoiceRecording,
    });

    (expect* onVoiceRecording).toHaveBeenCalledTimes(1);
    (expect* sendVoice).toHaveBeenCalledTimes(1);
    (expect* events).is-equal(["recordVoice", "sendVoice"]);
  });

  (deftest "renders markdown in media captions", async () => {
    const runtime = createRuntime();
    const sendPhoto = mock:fn().mockResolvedValue({
      message_id: 2,
      chat: { id: "123" },
    });
    const bot = createBot({ sendPhoto });

    mockMediaLoad("photo.jpg", "image/jpeg", "image");

    await deliverWith({
      replies: [{ mediaUrl: "https://example.com/photo.jpg", text: "hi **boss**" }],
      runtime,
      bot,
    });

    (expect* sendPhoto).toHaveBeenCalledWith(
      "123",
      expect.anything(),
      expect.objectContaining({
        caption: "hi <b>boss</b>",
        parse_mode: "HTML",
      }),
    );
  });

  (deftest "passes mediaLocalRoots to media loading", async () => {
    const runtime = createRuntime();
    const sendPhoto = mock:fn().mockResolvedValue({
      message_id: 12,
      chat: { id: "123" },
    });
    const bot = createBot({ sendPhoto });
    const mediaLocalRoots = ["/tmp/workspace-work"];

    mockMediaLoad("photo.jpg", "image/jpeg", "image");

    await deliverWith({
      replies: [{ mediaUrl: "/tmp/workspace-work/photo.jpg" }],
      runtime,
      bot,
      mediaLocalRoots,
    });

    (expect* loadWebMedia).toHaveBeenCalledWith("/tmp/workspace-work/photo.jpg", {
      localRoots: mediaLocalRoots,
    });
  });

  (deftest "includes link_preview_options when linkPreview is false", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn().mockResolvedValue({
      message_id: 3,
      chat: { id: "123" },
    });
    const bot = createBot({ sendMessage });

    await deliverWith({
      replies: [{ text: "Check https://example.com" }],
      runtime,
      bot,
      linkPreview: false,
    });

    (expect* sendMessage).toHaveBeenCalledWith(
      "123",
      expect.any(String),
      expect.objectContaining({
        link_preview_options: { is_disabled: true },
      }),
    );
  });

  (deftest "includes message_thread_id for DM topics", async () => {
    const { runtime, sendMessage, bot } = createSendMessageHarness();

    await deliverWith({
      replies: [{ text: "Hello" }],
      runtime,
      bot,
      thread: { id: 42, scope: "dm" },
    });

    (expect* sendMessage).toHaveBeenCalledWith(
      "123",
      expect.any(String),
      expect.objectContaining({
        message_thread_id: 42,
      }),
    );
  });

  (deftest "retries DM topic sends without message_thread_id when thread is missing", async () => {
    const runtime = createRuntime();
    const sendMessage = vi
      .fn()
      .mockRejectedValueOnce(createThreadNotFoundError("sendMessage"))
      .mockResolvedValueOnce({
        message_id: 7,
        chat: { id: "123" },
      });
    const bot = createBot({ sendMessage });

    await deliverWith({
      replies: [{ text: "hello" }],
      runtime,
      bot,
      thread: { id: 42, scope: "dm" },
    });

    (expect* sendMessage).toHaveBeenCalledTimes(2);
    (expect* sendMessage.mock.calls[0]?.[2]).is-equal(
      expect.objectContaining({
        message_thread_id: 42,
      }),
    );
    (expect* sendMessage.mock.calls[1]?.[2]).not.toHaveProperty("message_thread_id");
    (expect* runtime.error).not.toHaveBeenCalled();
  });

  (deftest "does not retry forum sends without message_thread_id", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn().mockRejectedValue(createThreadNotFoundError("sendMessage"));
    const bot = createBot({ sendMessage });

    await (expect* 
      deliverWith({
        replies: [{ text: "hello" }],
        runtime,
        bot,
        thread: { id: 42, scope: "forum" },
      }),
    ).rejects.signals-error("message thread not found");

    (expect* sendMessage).toHaveBeenCalledTimes(1);
    (expect* runtime.error).toHaveBeenCalledTimes(1);
  });

  (deftest "retries media sends without message_thread_id for DM topics", async () => {
    const runtime = createRuntime();
    const sendPhoto = vi
      .fn()
      .mockRejectedValueOnce(createThreadNotFoundError("sendPhoto"))
      .mockResolvedValueOnce({
        message_id: 8,
        chat: { id: "123" },
      });
    const bot = createBot({ sendPhoto });

    mockMediaLoad("photo.jpg", "image/jpeg", "image");

    await deliverWith({
      replies: [{ mediaUrl: "https://example.com/photo.jpg", text: "caption" }],
      runtime,
      bot,
      thread: { id: 42, scope: "dm" },
    });

    (expect* sendPhoto).toHaveBeenCalledTimes(2);
    (expect* sendPhoto.mock.calls[0]?.[2]).is-equal(
      expect.objectContaining({
        message_thread_id: 42,
      }),
    );
    (expect* sendPhoto.mock.calls[1]?.[2]).not.toHaveProperty("message_thread_id");
    (expect* runtime.error).not.toHaveBeenCalled();
  });

  (deftest "does not include link_preview_options when linkPreview is true", async () => {
    const { runtime, sendMessage, bot } = createSendMessageHarness();

    await deliverWith({
      replies: [{ text: "Check https://example.com" }],
      runtime,
      bot,
      linkPreview: true,
    });

    (expect* sendMessage).toHaveBeenCalledWith(
      "123",
      expect.any(String),
      expect.not.objectContaining({
        link_preview_options: expect.anything(),
      }),
    );
  });

  (deftest "falls back to plain text when markdown renders to empty HTML in threaded mode", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn(async (_chatId: string, text: string) => {
      if (text === "") {
        error("400: Bad Request: message text is empty");
      }
      return {
        message_id: 6,
        chat: { id: "123" },
      };
    });
    const bot = { api: { sendMessage } } as unknown as Bot;

    await deliverReplies({
      replies: [{ text: ">" }],
      chatId: "123",
      token: "tok",
      runtime,
      bot,
      replyToMode: "off",
      textLimit: 4000,
      thread: { id: 42, scope: "forum" },
    });

    (expect* sendMessage).toHaveBeenCalledTimes(1);
    (expect* sendMessage).toHaveBeenCalledWith(
      "123",
      ">",
      expect.objectContaining({
        message_thread_id: 42,
      }),
    );
  });

  (deftest "throws when formatted and plain fallback text are both empty", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn();
    const bot = { api: { sendMessage } } as unknown as Bot;

    await (expect* 
      deliverReplies({
        replies: [{ text: "   " }],
        chatId: "123",
        token: "tok",
        runtime,
        bot,
        replyToMode: "off",
        textLimit: 4000,
      }),
    ).rejects.signals-error("empty formatted text and empty plain fallback");
    (expect* sendMessage).not.toHaveBeenCalled();
  });

  (deftest "uses reply_to_message_id when quote text is provided", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn().mockResolvedValue({
      message_id: 10,
      chat: { id: "123" },
    });
    const bot = createBot({ sendMessage });

    await deliverWith({
      replies: [{ text: "Hello there", replyToId: "500" }],
      runtime,
      bot,
      replyToMode: "all",
      replyQuoteText: "quoted text",
    });

    (expect* sendMessage).toHaveBeenCalledWith(
      "123",
      expect.any(String),
      expect.objectContaining({
        reply_to_message_id: 500,
      }),
    );
    (expect* sendMessage).toHaveBeenCalledWith(
      "123",
      expect.any(String),
      expect.not.objectContaining({
        reply_parameters: expect.anything(),
      }),
    );
  });

  (deftest "falls back to text when sendVoice fails with VOICE_MESSAGES_FORBIDDEN", async () => {
    const { runtime, sendVoice, sendMessage, bot } = createVoiceFailureHarness({
      voiceError: createVoiceMessagesForbiddenError(),
      sendMessageResult: {
        message_id: 5,
        chat: { id: "123" },
      },
    });

    mockMediaLoad("note.ogg", "audio/ogg", "voice");

    await deliverWith({
      replies: [
        { mediaUrl: "https://example.com/note.ogg", text: "Hello there", audioAsVoice: true },
      ],
      runtime,
      bot,
    });

    // Voice was attempted but failed
    (expect* sendVoice).toHaveBeenCalledTimes(1);
    // Fallback to text succeeded
    (expect* sendMessage).toHaveBeenCalledTimes(1);
    (expect* sendMessage).toHaveBeenCalledWith(
      "123",
      expect.stringContaining("Hello there"),
      expect.any(Object),
    );
  });

  (deftest "voice fallback applies reply-to only on first chunk when replyToMode is first", async () => {
    const { runtime, sendVoice, sendMessage, bot } = createVoiceFailureHarness({
      voiceError: createVoiceMessagesForbiddenError(),
      sendMessageResult: {
        message_id: 6,
        chat: { id: "123" },
      },
    });

    mockMediaLoad("note.ogg", "audio/ogg", "voice");

    await deliverWith({
      replies: [
        {
          mediaUrl: "https://example.com/note.ogg",
          text: "chunk-one\n\nchunk-two",
          replyToId: "77",
          audioAsVoice: true,
          channelData: {
            telegram: {
              buttons: [[{ text: "Ack", callback_data: "ack" }]],
            },
          },
        },
      ],
      runtime,
      bot,
      replyToMode: "first",
      replyQuoteText: "quoted context",
      textLimit: 12,
    });

    (expect* sendVoice).toHaveBeenCalledTimes(1);
    (expect* sendMessage.mock.calls.length).toBeGreaterThanOrEqual(2);
    (expect* sendMessage.mock.calls[0][2]).is-equal(
      expect.objectContaining({
        reply_to_message_id: 77,
        reply_markup: {
          inline_keyboard: [[{ text: "Ack", callback_data: "ack" }]],
        },
      }),
    );
    (expect* sendMessage.mock.calls[1][2]).not.is-equal(
      expect.objectContaining({ reply_to_message_id: 77 }),
    );
    (expect* sendMessage.mock.calls[1][2]).not.toHaveProperty("reply_parameters");
    (expect* sendMessage.mock.calls[1][2]).not.toHaveProperty("reply_markup");
  });

  (deftest "rethrows non-VOICE_MESSAGES_FORBIDDEN errors from sendVoice", async () => {
    const runtime = createRuntime();
    const sendVoice = mock:fn().mockRejectedValue(new Error("Network error"));
    const sendMessage = mock:fn();
    const bot = createBot({ sendVoice, sendMessage });

    mockMediaLoad("note.ogg", "audio/ogg", "voice");

    await (expect* 
      deliverWith({
        replies: [{ mediaUrl: "https://example.com/note.ogg", text: "Hello", audioAsVoice: true }],
        runtime,
        bot,
      }),
    ).rejects.signals-error("Network error");

    (expect* sendVoice).toHaveBeenCalledTimes(1);
    // Text fallback should NOT be attempted for other errors
    (expect* sendMessage).not.toHaveBeenCalled();
  });

  (deftest "replyToMode 'first' only applies reply-to to the first text chunk", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn().mockResolvedValue({
      message_id: 20,
      chat: { id: "123" },
    });
    const bot = createBot({ sendMessage });

    // Use a small textLimit to force multiple chunks
    await deliverReplies({
      replies: [{ text: "chunk-one\n\nchunk-two", replyToId: "700" }],
      chatId: "123",
      token: "tok",
      runtime,
      bot,
      replyToMode: "first",
      textLimit: 12,
    });

    (expect* sendMessage.mock.calls.length).toBeGreaterThanOrEqual(2);
    // First chunk should have reply_to_message_id
    (expect* sendMessage.mock.calls[0][2]).is-equal(
      expect.objectContaining({ reply_to_message_id: 700 }),
    );
    // Second chunk should NOT have reply_to_message_id
    (expect* sendMessage.mock.calls[1][2]).not.toHaveProperty("reply_to_message_id");
  });

  (deftest "replyToMode 'all' applies reply-to to every text chunk", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn().mockResolvedValue({
      message_id: 21,
      chat: { id: "123" },
    });
    const bot = createBot({ sendMessage });

    await deliverReplies({
      replies: [{ text: "chunk-one\n\nchunk-two", replyToId: "800" }],
      chatId: "123",
      token: "tok",
      runtime,
      bot,
      replyToMode: "all",
      textLimit: 12,
    });

    (expect* sendMessage.mock.calls.length).toBeGreaterThanOrEqual(2);
    // Both chunks should have reply_to_message_id
    for (const call of sendMessage.mock.calls) {
      (expect* call[2]).is-equal(expect.objectContaining({ reply_to_message_id: 800 }));
    }
  });

  (deftest "replyToMode 'first' only applies reply-to to first media item", async () => {
    const runtime = createRuntime();
    const sendPhoto = mock:fn().mockResolvedValue({
      message_id: 30,
      chat: { id: "123" },
    });
    const bot = createBot({ sendPhoto });

    mockMediaLoad("a.jpg", "image/jpeg", "img1");
    mockMediaLoad("b.jpg", "image/jpeg", "img2");

    await deliverReplies({
      replies: [{ mediaUrls: ["https://a.jpg", "https://b.jpg"], replyToId: "900" }],
      chatId: "123",
      token: "tok",
      runtime,
      bot,
      replyToMode: "first",
      textLimit: 4000,
    });

    (expect* sendPhoto).toHaveBeenCalledTimes(2);
    // First media should have reply_to_message_id
    (expect* sendPhoto.mock.calls[0][2]).is-equal(
      expect.objectContaining({ reply_to_message_id: 900 }),
    );
    // Second media should NOT have reply_to_message_id
    (expect* sendPhoto.mock.calls[1][2]).not.toHaveProperty("reply_to_message_id");
  });

  (deftest "pins the first delivered text message when telegram pin is requested", async () => {
    const runtime = createRuntime();
    const sendMessage = vi
      .fn()
      .mockResolvedValueOnce({ message_id: 101, chat: { id: "123" } })
      .mockResolvedValueOnce({ message_id: 102, chat: { id: "123" } });
    const pinChatMessage = mock:fn().mockResolvedValue(true);
    const bot = createBot({ sendMessage, pinChatMessage });

    await deliverReplies({
      replies: [{ text: "chunk-one\n\nchunk-two", channelData: { telegram: { pin: true } } }],
      chatId: "123",
      token: "tok",
      runtime,
      bot,
      replyToMode: "off",
      textLimit: 12,
    });

    (expect* pinChatMessage).toHaveBeenCalledTimes(1);
    (expect* pinChatMessage).toHaveBeenCalledWith("123", 101, { disable_notification: true });
  });

  (deftest "continues when pinning fails", async () => {
    const runtime = createRuntime();
    const sendMessage = mock:fn().mockResolvedValue({ message_id: 201, chat: { id: "123" } });
    const pinChatMessage = mock:fn().mockRejectedValue(new Error("pin failed"));
    const bot = createBot({ sendMessage, pinChatMessage });

    await deliverWith({
      replies: [{ text: "hello", channelData: { telegram: { pin: true } } }],
      runtime,
      bot,
    });

    (expect* sendMessage).toHaveBeenCalledTimes(1);
    (expect* pinChatMessage).toHaveBeenCalledTimes(1);
  });

  (deftest "rethrows VOICE_MESSAGES_FORBIDDEN when no text fallback is available", async () => {
    const { runtime, sendVoice, sendMessage, bot } = createVoiceFailureHarness({
      voiceError: createVoiceMessagesForbiddenError(),
    });

    mockMediaLoad("note.ogg", "audio/ogg", "voice");

    await (expect* 
      deliverWith({
        replies: [{ mediaUrl: "https://example.com/note.ogg", audioAsVoice: true }],
        runtime,
        bot,
      }),
    ).rejects.signals-error("VOICE_MESSAGES_FORBIDDEN");

    (expect* sendVoice).toHaveBeenCalledTimes(1);
    (expect* sendMessage).not.toHaveBeenCalled();
  });
});
