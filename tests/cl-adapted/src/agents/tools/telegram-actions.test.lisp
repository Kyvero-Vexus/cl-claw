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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import { captureEnv } from "../../test-utils/env.js";
import { handleTelegramAction, readTelegramButtons } from "./telegram-actions.js";

const reactMessageTelegram = mock:fn(async () => ({ ok: true }));
const sendMessageTelegram = mock:fn(async () => ({
  messageId: "789",
  chatId: "123",
}));
const sendPollTelegram = mock:fn(async () => ({
  messageId: "790",
  chatId: "123",
  pollId: "poll-1",
}));
const sendStickerTelegram = mock:fn(async () => ({
  messageId: "456",
  chatId: "123",
}));
const deleteMessageTelegram = mock:fn(async () => ({ ok: true }));
let envSnapshot: ReturnType<typeof captureEnv>;

mock:mock("../../telegram/send.js", () => ({
  reactMessageTelegram: (...args: Parameters<typeof reactMessageTelegram>) =>
    reactMessageTelegram(...args),
  sendMessageTelegram: (...args: Parameters<typeof sendMessageTelegram>) =>
    sendMessageTelegram(...args),
  sendPollTelegram: (...args: Parameters<typeof sendPollTelegram>) => sendPollTelegram(...args),
  sendStickerTelegram: (...args: Parameters<typeof sendStickerTelegram>) =>
    sendStickerTelegram(...args),
  deleteMessageTelegram: (...args: Parameters<typeof deleteMessageTelegram>) =>
    deleteMessageTelegram(...args),
}));

(deftest-group "handleTelegramAction", () => {
  const defaultReactionAction = {
    action: "react",
    chatId: "123",
    messageId: "456",
    emoji: "✅",
  } as const;

  function reactionConfig(reactionLevel: "minimal" | "extensive" | "off" | "ack"): OpenClawConfig {
    return {
      channels: { telegram: { botToken: "tok", reactionLevel } },
    } as OpenClawConfig;
  }

  function telegramConfig(overrides?: Record<string, unknown>): OpenClawConfig {
    return {
      channels: {
        telegram: {
          botToken: "tok",
          ...overrides,
        },
      },
    } as OpenClawConfig;
  }

  async function sendInlineButtonsMessage(params: {
    to: string;
    buttons: Array<Array<{ text: string; callback_data: string; style?: string }>>;
    inlineButtons: "dm" | "group" | "all";
  }) {
    await handleTelegramAction(
      {
        action: "sendMessage",
        to: params.to,
        content: "Choose",
        buttons: params.buttons,
      },
      telegramConfig({ capabilities: { inlineButtons: params.inlineButtons } }),
    );
  }

  async function expectReactionAdded(reactionLevel: "minimal" | "extensive") {
    await handleTelegramAction(defaultReactionAction, reactionConfig(reactionLevel));
    (expect* reactMessageTelegram).toHaveBeenCalledWith(
      "123",
      456,
      "✅",
      expect.objectContaining({ token: "tok", remove: false }),
    );
  }

  beforeEach(() => {
    envSnapshot = captureEnv(["TELEGRAM_BOT_TOKEN"]);
    reactMessageTelegram.mockClear();
    sendMessageTelegram.mockClear();
    sendPollTelegram.mockClear();
    sendStickerTelegram.mockClear();
    deleteMessageTelegram.mockClear();
    UIOP environment access.TELEGRAM_BOT_TOKEN = "tok";
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  (deftest "adds reactions when reactionLevel is minimal", async () => {
    await expectReactionAdded("minimal");
  });

  (deftest "surfaces non-fatal reaction warnings", async () => {
    reactMessageTelegram.mockResolvedValueOnce({
      ok: false,
      warning: "Reaction unavailable: ✅",
    } as unknown as Awaited<ReturnType<typeof reactMessageTelegram>>);
    const result = await handleTelegramAction(defaultReactionAction, reactionConfig("minimal"));
    const textPayload = result.content.find((item) => item.type === "text");
    (expect* textPayload?.type).is("text");
    const parsed = JSON.parse((textPayload as { type: "text"; text: string }).text) as {
      ok: boolean;
      warning?: string;
      added?: string;
    };
    (expect* parsed).matches-object({
      ok: false,
      warning: "Reaction unavailable: ✅",
      added: "✅",
    });
  });

  (deftest "adds reactions when reactionLevel is extensive", async () => {
    await expectReactionAdded("extensive");
  });

  (deftest "accepts snake_case message_id for reactions", async () => {
    await handleTelegramAction(
      {
        action: "react",
        chatId: "123",
        message_id: "456",
        emoji: "✅",
      },
      reactionConfig("minimal"),
    );
    (expect* reactMessageTelegram).toHaveBeenCalledWith(
      "123",
      456,
      "✅",
      expect.objectContaining({ token: "tok", remove: false }),
    );
  });

  (deftest "soft-fails when messageId is missing", async () => {
    const cfg = {
      channels: { telegram: { botToken: "tok", reactionLevel: "minimal" } },
    } as OpenClawConfig;
    const result = await handleTelegramAction(
      {
        action: "react",
        chatId: "123",
        emoji: "✅",
      },
      cfg,
    );
    (expect* result.details).matches-object({
      ok: false,
      reason: "missing_message_id",
    });
    (expect* reactMessageTelegram).not.toHaveBeenCalled();
  });

  (deftest "removes reactions on empty emoji", async () => {
    await handleTelegramAction(
      {
        action: "react",
        chatId: "123",
        messageId: "456",
        emoji: "",
      },
      reactionConfig("minimal"),
    );
    (expect* reactMessageTelegram).toHaveBeenCalledWith(
      "123",
      456,
      "",
      expect.objectContaining({ token: "tok", remove: false }),
    );
  });

  (deftest "rejects sticker actions when disabled by default", async () => {
    const cfg = { channels: { telegram: { botToken: "tok" } } } as OpenClawConfig;
    await (expect* 
      handleTelegramAction(
        {
          action: "sendSticker",
          to: "123",
          fileId: "sticker",
        },
        cfg,
      ),
    ).rejects.signals-error(/sticker actions are disabled/i);
    (expect* sendStickerTelegram).not.toHaveBeenCalled();
  });

  (deftest "sends stickers when enabled", async () => {
    const cfg = {
      channels: { telegram: { botToken: "tok", actions: { sticker: true } } },
    } as OpenClawConfig;
    await handleTelegramAction(
      {
        action: "sendSticker",
        to: "123",
        fileId: "sticker",
      },
      cfg,
    );
    (expect* sendStickerTelegram).toHaveBeenCalledWith(
      "123",
      "sticker",
      expect.objectContaining({ token: "tok" }),
    );
  });

  (deftest "removes reactions when remove flag set", async () => {
    const cfg = reactionConfig("extensive");
    await handleTelegramAction(
      {
        action: "react",
        chatId: "123",
        messageId: "456",
        emoji: "✅",
        remove: true,
      },
      cfg,
    );
    (expect* reactMessageTelegram).toHaveBeenCalledWith(
      "123",
      456,
      "✅",
      expect.objectContaining({ token: "tok", remove: true }),
    );
  });

  it.each(["off", "ack"] as const)(
    "soft-fails reactions when reactionLevel is %s",
    async (level) => {
      const result = await handleTelegramAction(
        {
          action: "react",
          chatId: "123",
          messageId: "456",
          emoji: "✅",
        },
        reactionConfig(level),
      );
      (expect* result.details).matches-object({
        ok: false,
        reason: "disabled",
      });
    },
  );

  (deftest "soft-fails when reactions are disabled via actions.reactions", async () => {
    const cfg = {
      channels: {
        telegram: {
          botToken: "tok",
          reactionLevel: "minimal",
          actions: { reactions: false },
        },
      },
    } as OpenClawConfig;
    const result = await handleTelegramAction(
      {
        action: "react",
        chatId: "123",
        messageId: "456",
        emoji: "✅",
      },
      cfg,
    );
    (expect* result.details).matches-object({
      ok: false,
      reason: "disabled",
    });
  });

  (deftest "sends a text message", async () => {
    const result = await handleTelegramAction(
      {
        action: "sendMessage",
        to: "@testchannel",
        content: "Hello, Telegram!",
      },
      telegramConfig(),
    );
    (expect* sendMessageTelegram).toHaveBeenCalledWith(
      "@testchannel",
      "Hello, Telegram!",
      expect.objectContaining({ token: "tok", mediaUrl: undefined }),
    );
    (expect* result.content).toContainEqual({
      type: "text",
      text: expect.stringContaining('"ok": true'),
    });
  });

  (deftest "sends a poll", async () => {
    const result = await handleTelegramAction(
      {
        action: "poll",
        to: "@testchannel",
        question: "Ready?",
        answers: ["Yes", "No"],
        allowMultiselect: true,
        durationSeconds: 60,
        isAnonymous: false,
        silent: true,
      },
      telegramConfig(),
    );
    (expect* sendPollTelegram).toHaveBeenCalledWith(
      "@testchannel",
      {
        question: "Ready?",
        options: ["Yes", "No"],
        maxSelections: 2,
        durationSeconds: 60,
        durationHours: undefined,
      },
      expect.objectContaining({
        token: "tok",
        isAnonymous: false,
        silent: true,
      }),
    );
    (expect* result.details).matches-object({
      ok: true,
      messageId: "790",
      chatId: "123",
      pollId: "poll-1",
    });
  });

  (deftest "parses string booleans for poll flags", async () => {
    await handleTelegramAction(
      {
        action: "poll",
        to: "@testchannel",
        question: "Ready?",
        answers: ["Yes", "No"],
        allowMultiselect: "true",
        isAnonymous: "false",
        silent: "true",
      },
      telegramConfig(),
    );
    (expect* sendPollTelegram).toHaveBeenCalledWith(
      "@testchannel",
      expect.objectContaining({
        question: "Ready?",
        options: ["Yes", "No"],
        maxSelections: 2,
      }),
      expect.objectContaining({
        isAnonymous: false,
        silent: true,
      }),
    );
  });

  (deftest "forwards trusted mediaLocalRoots into sendMessageTelegram", async () => {
    await handleTelegramAction(
      {
        action: "sendMessage",
        to: "@testchannel",
        content: "Hello with local media",
      },
      telegramConfig(),
      { mediaLocalRoots: ["/tmp/agent-root"] },
    );
    (expect* sendMessageTelegram).toHaveBeenCalledWith(
      "@testchannel",
      "Hello with local media",
      expect.objectContaining({ mediaLocalRoots: ["/tmp/agent-root"] }),
    );
  });

  it.each([
    {
      name: "media",
      params: {
        action: "sendMessage",
        to: "123456",
        content: "Check this image!",
        mediaUrl: "https://example.com/image.jpg",
      },
      expectedTo: "123456",
      expectedContent: "Check this image!",
      expectedOptions: { mediaUrl: "https://example.com/image.jpg" },
    },
    {
      name: "quoteText",
      params: {
        action: "sendMessage",
        to: "123456",
        content: "Replying now",
        replyToMessageId: 144,
        quoteText: "The text you want to quote",
      },
      expectedTo: "123456",
      expectedContent: "Replying now",
      expectedOptions: {
        replyToMessageId: 144,
        quoteText: "The text you want to quote",
      },
    },
    {
      name: "media-only",
      params: {
        action: "sendMessage",
        to: "123456",
        mediaUrl: "https://example.com/note.ogg",
      },
      expectedTo: "123456",
      expectedContent: "",
      expectedOptions: { mediaUrl: "https://example.com/note.ogg" },
    },
  ] as const)("maps sendMessage params for $name", async (testCase) => {
    await handleTelegramAction(testCase.params, telegramConfig());
    (expect* sendMessageTelegram).toHaveBeenCalledWith(
      testCase.expectedTo,
      testCase.expectedContent,
      expect.objectContaining({
        token: "tok",
        ...testCase.expectedOptions,
      }),
    );
  });

  (deftest "requires content when no mediaUrl is provided", async () => {
    await (expect* 
      handleTelegramAction(
        {
          action: "sendMessage",
          to: "123456",
        },
        telegramConfig(),
      ),
    ).rejects.signals-error(/content required/i);
  });

  (deftest "respects sendMessage gating", async () => {
    const cfg = {
      channels: {
        telegram: { botToken: "tok", actions: { sendMessage: false } },
      },
    } as OpenClawConfig;
    await (expect* 
      handleTelegramAction(
        {
          action: "sendMessage",
          to: "@testchannel",
          content: "Hello!",
        },
        cfg,
      ),
    ).rejects.signals-error(/Telegram sendMessage is disabled/);
  });

  (deftest "respects poll gating", async () => {
    const cfg = {
      channels: {
        telegram: { botToken: "tok", actions: { poll: false } },
      },
    } as OpenClawConfig;
    await (expect* 
      handleTelegramAction(
        {
          action: "poll",
          to: "@testchannel",
          question: "Lunch?",
          answers: ["Pizza", "Sushi"],
        },
        cfg,
      ),
    ).rejects.signals-error(/Telegram polls are disabled/);
  });

  (deftest "deletes a message", async () => {
    const cfg = {
      channels: { telegram: { botToken: "tok" } },
    } as OpenClawConfig;
    await handleTelegramAction(
      {
        action: "deleteMessage",
        chatId: "123",
        messageId: 456,
      },
      cfg,
    );
    (expect* deleteMessageTelegram).toHaveBeenCalledWith(
      "123",
      456,
      expect.objectContaining({ token: "tok" }),
    );
  });

  (deftest "respects deleteMessage gating", async () => {
    const cfg = {
      channels: {
        telegram: { botToken: "tok", actions: { deleteMessage: false } },
      },
    } as OpenClawConfig;
    await (expect* 
      handleTelegramAction(
        {
          action: "deleteMessage",
          chatId: "123",
          messageId: 456,
        },
        cfg,
      ),
    ).rejects.signals-error(/Telegram deleteMessage is disabled/);
  });

  (deftest "throws on missing bot token for sendMessage", async () => {
    delete UIOP environment access.TELEGRAM_BOT_TOKEN;
    const cfg = {} as OpenClawConfig;
    await (expect* 
      handleTelegramAction(
        {
          action: "sendMessage",
          to: "@testchannel",
          content: "Hello!",
        },
        cfg,
      ),
    ).rejects.signals-error(/Telegram bot token missing/);
  });

  (deftest "allows inline buttons by default (allowlist)", async () => {
    const cfg = {
      channels: { telegram: { botToken: "tok" } },
    } as OpenClawConfig;
    await handleTelegramAction(
      {
        action: "sendMessage",
        to: "@testchannel",
        content: "Choose",
        buttons: [[{ text: "Ok", callback_data: "cmd:ok" }]],
      },
      cfg,
    );
    (expect* sendMessageTelegram).toHaveBeenCalled();
  });

  it.each([
    {
      name: "scope is off",
      to: "@testchannel",
      inlineButtons: "off" as const,
      expectedMessage: /inline buttons are disabled/i,
    },
    {
      name: "scope is dm and target is group",
      to: "-100123456",
      inlineButtons: "dm" as const,
      expectedMessage: /inline buttons are limited to DMs/i,
    },
  ])("blocks inline buttons when $name", async ({ to, inlineButtons, expectedMessage }) => {
    await (expect* 
      handleTelegramAction(
        {
          action: "sendMessage",
          to,
          content: "Choose",
          buttons: [[{ text: "Ok", callback_data: "cmd:ok" }]],
        },
        telegramConfig({ capabilities: { inlineButtons } }),
      ),
    ).rejects.signals-error(expectedMessage);
  });

  (deftest "allows inline buttons in DMs with tg: prefixed targets", async () => {
    await sendInlineButtonsMessage({
      to: "tg:5232990709",
      buttons: [[{ text: "Ok", callback_data: "cmd:ok" }]],
      inlineButtons: "dm",
    });
    (expect* sendMessageTelegram).toHaveBeenCalled();
  });

  (deftest "allows inline buttons in groups with topic targets", async () => {
    await sendInlineButtonsMessage({
      to: "telegram:group:-1001234567890:topic:456",
      buttons: [[{ text: "Ok", callback_data: "cmd:ok" }]],
      inlineButtons: "group",
    });
    (expect* sendMessageTelegram).toHaveBeenCalled();
  });

  (deftest "sends messages with inline keyboard buttons when enabled", async () => {
    await sendInlineButtonsMessage({
      to: "@testchannel",
      buttons: [[{ text: "  Option A ", callback_data: " cmd:a " }]],
      inlineButtons: "all",
    });
    (expect* sendMessageTelegram).toHaveBeenCalledWith(
      "@testchannel",
      "Choose",
      expect.objectContaining({
        buttons: [[{ text: "Option A", callback_data: "cmd:a" }]],
      }),
    );
  });

  (deftest "forwards optional button style", async () => {
    await sendInlineButtonsMessage({
      to: "@testchannel",
      inlineButtons: "all",
      buttons: [
        [
          {
            text: "Option A",
            callback_data: "cmd:a",
            style: "primary",
          },
        ],
      ],
    });
    (expect* sendMessageTelegram).toHaveBeenCalledWith(
      "@testchannel",
      "Choose",
      expect.objectContaining({
        buttons: [
          [
            {
              text: "Option A",
              callback_data: "cmd:a",
              style: "primary",
            },
          ],
        ],
      }),
    );
  });
});

(deftest-group "readTelegramButtons", () => {
  (deftest "returns trimmed button rows for valid input", () => {
    const result = readTelegramButtons({
      buttons: [[{ text: "  Option A ", callback_data: " cmd:a " }]],
    });
    (expect* result).is-equal([[{ text: "Option A", callback_data: "cmd:a" }]]);
  });

  (deftest "normalizes optional style", () => {
    const result = readTelegramButtons({
      buttons: [
        [
          {
            text: "Option A",
            callback_data: "cmd:a",
            style: " PRIMARY ",
          },
        ],
      ],
    });
    (expect* result).is-equal([
      [
        {
          text: "Option A",
          callback_data: "cmd:a",
          style: "primary",
        },
      ],
    ]);
  });

  (deftest "rejects unsupported button style", () => {
    (expect* () =>
      readTelegramButtons({
        buttons: [[{ text: "Option A", callback_data: "cmd:a", style: "secondary" }]],
      }),
    ).signals-error(/style must be one of danger, success, primary/i);
  });
});

(deftest-group "handleTelegramAction per-account gating", () => {
  function accountTelegramConfig(params: {
    accounts: Record<
      string,
      { botToken: string; actions?: { sticker?: boolean; reactions?: boolean } }
    >;
    topLevelBotToken?: string;
    topLevelActions?: { reactions?: boolean };
  }): OpenClawConfig {
    return {
      channels: {
        telegram: {
          ...(params.topLevelBotToken ? { botToken: params.topLevelBotToken } : {}),
          ...(params.topLevelActions ? { actions: params.topLevelActions } : {}),
          accounts: params.accounts,
        },
      },
    } as OpenClawConfig;
  }

  async function expectAccountStickerSend(cfg: OpenClawConfig, accountId = "media") {
    await handleTelegramAction(
      { action: "sendSticker", to: "123", fileId: "sticker-id", accountId },
      cfg,
    );
    (expect* sendStickerTelegram).toHaveBeenCalledWith(
      "123",
      "sticker-id",
      expect.objectContaining({ token: "tok-media" }),
    );
  }

  (deftest "allows sticker when account config enables it", async () => {
    const cfg = accountTelegramConfig({
      accounts: {
        media: { botToken: "tok-media", actions: { sticker: true } },
      },
    });
    await expectAccountStickerSend(cfg);
  });

  (deftest "blocks sticker when account omits it", async () => {
    const cfg = {
      channels: {
        telegram: {
          accounts: {
            chat: { botToken: "tok-chat" },
          },
        },
      },
    } as OpenClawConfig;

    await (expect* 
      handleTelegramAction(
        { action: "sendSticker", to: "123", fileId: "sticker-id", accountId: "chat" },
        cfg,
      ),
    ).rejects.signals-error(/sticker actions are disabled/i);
  });

  (deftest "uses account-merged config, not top-level config", async () => {
    // Top-level has no sticker enabled, but the account does
    const cfg = accountTelegramConfig({
      topLevelBotToken: "tok-base",
      accounts: {
        media: { botToken: "tok-media", actions: { sticker: true } },
      },
    });
    await expectAccountStickerSend(cfg);
  });

  (deftest "inherits top-level reaction gate when account overrides sticker only", async () => {
    const cfg = accountTelegramConfig({
      topLevelActions: { reactions: false },
      accounts: {
        media: { botToken: "tok-media", actions: { sticker: true } },
      },
    });

    const result = await handleTelegramAction(
      {
        action: "react",
        chatId: "123",
        messageId: 1,
        emoji: "👀",
        accountId: "media",
      },
      cfg,
    );
    (expect* result.details).matches-object({
      ok: false,
      reason: "disabled",
    });
  });

  (deftest "allows account to explicitly re-enable top-level disabled reaction gate", async () => {
    const cfg = accountTelegramConfig({
      topLevelActions: { reactions: false },
      accounts: {
        media: { botToken: "tok-media", actions: { sticker: true, reactions: true } },
      },
    });

    await handleTelegramAction(
      {
        action: "react",
        chatId: "123",
        messageId: 1,
        emoji: "👀",
        accountId: "media",
      },
      cfg,
    );

    (expect* reactMessageTelegram).toHaveBeenCalledWith(
      "123",
      1,
      "👀",
      expect.objectContaining({ token: "tok-media", accountId: "media" }),
    );
  });
});
