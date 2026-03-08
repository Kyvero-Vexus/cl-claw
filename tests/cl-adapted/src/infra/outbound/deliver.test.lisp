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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { signalOutbound } from "../../channels/plugins/outbound/signal.js";
import { telegramOutbound } from "../../channels/plugins/outbound/telegram.js";
import { whatsappOutbound } from "../../channels/plugins/outbound/whatsapp.js";
import type { OpenClawConfig } from "../../config/config.js";
import { STATE_DIR } from "../../config/paths.js";
import { setActivePluginRegistry } from "../../plugins/runtime.js";
import { markdownToSignalTextChunks } from "../../signal/format.js";
import { createOutboundTestPlugin, createTestRegistry } from "../../test-utils/channel-plugins.js";
import { withEnvAsync } from "../../test-utils/env.js";
import { createIMessageTestPlugin } from "../../test-utils/imessage-test-plugin.js";
import { createInternalHookEventPayload } from "../../test-utils/internal-hook-event-payload.js";
import { resolvePreferredOpenClawTmpDir } from "../tmp-openclaw-dir.js";

const mocks = mock:hoisted(() => ({
  appendAssistantMessageToSessionTranscript: mock:fn(async () => ({ ok: true, sessionFile: "x" })),
}));
const hookMocks = mock:hoisted(() => ({
  runner: {
    hasHooks: mock:fn(() => false),
    runMessageSent: mock:fn(async () => {}),
  },
}));
const internalHookMocks = mock:hoisted(() => ({
  createInternalHookEvent: mock:fn(),
  triggerInternalHook: mock:fn(async () => {}),
}));
const queueMocks = mock:hoisted(() => ({
  enqueueDelivery: mock:fn(async () => "mock-queue-id"),
  ackDelivery: mock:fn(async () => {}),
  failDelivery: mock:fn(async () => {}),
}));
const logMocks = mock:hoisted(() => ({
  warn: mock:fn(),
}));

mock:mock("../../config/sessions.js", async () => {
  const actual = await mock:importActual<typeof import("../../config/sessions.js")>(
    "../../config/sessions.js",
  );
  return {
    ...actual,
    appendAssistantMessageToSessionTranscript: mocks.appendAssistantMessageToSessionTranscript,
  };
});
mock:mock("../../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => hookMocks.runner,
}));
mock:mock("../../hooks/internal-hooks.js", () => ({
  createInternalHookEvent: internalHookMocks.createInternalHookEvent,
  triggerInternalHook: internalHookMocks.triggerInternalHook,
}));
mock:mock("./delivery-queue.js", () => ({
  enqueueDelivery: queueMocks.enqueueDelivery,
  ackDelivery: queueMocks.ackDelivery,
  failDelivery: queueMocks.failDelivery,
}));
mock:mock("../../logging/subsystem.js", () => ({
  createSubsystemLogger: () => {
    const makeLogger = () => ({
      warn: logMocks.warn,
      info: mock:fn(),
      error: mock:fn(),
      debug: mock:fn(),
      child: mock:fn(() => makeLogger()),
    });
    return makeLogger();
  },
}));

const { deliverOutboundPayloads, normalizeOutboundPayloads } = await import("./deliver.js");

const telegramChunkConfig: OpenClawConfig = {
  channels: { telegram: { botToken: "tok-1", textChunkLimit: 2 } },
};

const whatsappChunkConfig: OpenClawConfig = {
  channels: { whatsapp: { textChunkLimit: 4000 } },
};

type DeliverOutboundArgs = Parameters<typeof deliverOutboundPayloads>[0];
type DeliverOutboundPayload = DeliverOutboundArgs["payloads"][number];
type DeliverSession = DeliverOutboundArgs["session"];

async function deliverWhatsAppPayload(params: {
  sendWhatsApp: NonNullable<
    NonNullable<Parameters<typeof deliverOutboundPayloads>[0]["deps"]>["sendWhatsApp"]
  >;
  payload: { text: string; mediaUrl?: string };
  cfg?: OpenClawConfig;
}) {
  return deliverOutboundPayloads({
    cfg: params.cfg ?? whatsappChunkConfig,
    channel: "whatsapp",
    to: "+1555",
    payloads: [params.payload],
    deps: { sendWhatsApp: params.sendWhatsApp },
  });
}

async function deliverTelegramPayload(params: {
  sendTelegram: NonNullable<NonNullable<DeliverOutboundArgs["deps"]>["sendTelegram"]>;
  payload: DeliverOutboundPayload;
  cfg?: OpenClawConfig;
  accountId?: string;
  session?: DeliverSession;
}) {
  return deliverOutboundPayloads({
    cfg: params.cfg ?? telegramChunkConfig,
    channel: "telegram",
    to: "123",
    payloads: [params.payload],
    deps: { sendTelegram: params.sendTelegram },
    ...(params.accountId ? { accountId: params.accountId } : {}),
    ...(params.session ? { session: params.session } : {}),
  });
}

async function runChunkedWhatsAppDelivery(params?: {
  mirror?: Parameters<typeof deliverOutboundPayloads>[0]["mirror"];
}) {
  const sendWhatsApp = vi
    .fn()
    .mockResolvedValueOnce({ messageId: "w1", toJid: "jid" })
    .mockResolvedValueOnce({ messageId: "w2", toJid: "jid" });
  const cfg: OpenClawConfig = {
    channels: { whatsapp: { textChunkLimit: 2 } },
  };
  const results = await deliverOutboundPayloads({
    cfg,
    channel: "whatsapp",
    to: "+1555",
    payloads: [{ text: "abcd" }],
    deps: { sendWhatsApp },
    ...(params?.mirror ? { mirror: params.mirror } : {}),
  });
  return { sendWhatsApp, results };
}

async function deliverSingleWhatsAppForHookTest(params?: { sessionKey?: string }) {
  const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
  await deliverOutboundPayloads({
    cfg: whatsappChunkConfig,
    channel: "whatsapp",
    to: "+1555",
    payloads: [{ text: "hello" }],
    deps: { sendWhatsApp },
    ...(params?.sessionKey ? { session: { key: params.sessionKey } } : {}),
  });
}

async function runBestEffortPartialFailureDelivery() {
  const sendWhatsApp = vi
    .fn()
    .mockRejectedValueOnce(new Error("fail"))
    .mockResolvedValueOnce({ messageId: "w2", toJid: "jid" });
  const onError = mock:fn();
  const cfg: OpenClawConfig = {};
  const results = await deliverOutboundPayloads({
    cfg,
    channel: "whatsapp",
    to: "+1555",
    payloads: [{ text: "a" }, { text: "b" }],
    deps: { sendWhatsApp },
    bestEffort: true,
    onError,
  });
  return { sendWhatsApp, onError, results };
}

function expectSuccessfulWhatsAppInternalHookPayload(
  expected: Partial<{
    content: string;
    messageId: string;
    isGroup: boolean;
    groupId: string;
  }>,
) {
  return expect.objectContaining({
    to: "+1555",
    success: true,
    channelId: "whatsapp",
    conversationId: "+1555",
    ...expected,
  });
}

(deftest-group "deliverOutboundPayloads", () => {
  beforeEach(() => {
    setActivePluginRegistry(defaultRegistry);
    hookMocks.runner.hasHooks.mockClear();
    hookMocks.runner.hasHooks.mockReturnValue(false);
    hookMocks.runner.runMessageSent.mockClear();
    hookMocks.runner.runMessageSent.mockResolvedValue(undefined);
    internalHookMocks.createInternalHookEvent.mockClear();
    internalHookMocks.createInternalHookEvent.mockImplementation(createInternalHookEventPayload);
    internalHookMocks.triggerInternalHook.mockClear();
    queueMocks.enqueueDelivery.mockClear();
    queueMocks.enqueueDelivery.mockResolvedValue("mock-queue-id");
    queueMocks.ackDelivery.mockClear();
    queueMocks.ackDelivery.mockResolvedValue(undefined);
    queueMocks.failDelivery.mockClear();
    queueMocks.failDelivery.mockResolvedValue(undefined);
    logMocks.warn.mockClear();
  });

  afterEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });
  (deftest "chunks telegram markdown and passes through accountId", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });
    await withEnvAsync({ TELEGRAM_BOT_TOKEN: "" }, async () => {
      const results = await deliverOutboundPayloads({
        cfg: telegramChunkConfig,
        channel: "telegram",
        to: "123",
        payloads: [{ text: "abcd" }],
        deps: { sendTelegram },
      });

      (expect* sendTelegram).toHaveBeenCalledTimes(2);
      for (const call of sendTelegram.mock.calls) {
        (expect* call[2]).is-equal(
          expect.objectContaining({ accountId: undefined, verbose: false, textMode: "html" }),
        );
      }
      (expect* results).has-length(2);
      (expect* results[0]).matches-object({ channel: "telegram", chatId: "c1" });
    });
  });

  (deftest "clamps telegram text chunk size to protocol max even with higher config", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });
    const cfg: OpenClawConfig = {
      channels: { telegram: { botToken: "tok-1", textChunkLimit: 10_000 } },
    };
    const text = "<".repeat(3_000);
    await withEnvAsync({ TELEGRAM_BOT_TOKEN: "" }, async () => {
      await deliverOutboundPayloads({
        cfg,
        channel: "telegram",
        to: "123",
        payloads: [{ text }],
        deps: { sendTelegram },
      });
    });

    (expect* sendTelegram.mock.calls.length).toBeGreaterThan(1);
    const sentHtmlChunks = sendTelegram.mock.calls
      .map((call) => call[1])
      .filter((message): message is string => typeof message === "string");
    (expect* sentHtmlChunks.length).toBeGreaterThan(1);
    (expect* sentHtmlChunks.every((message) => message.length <= 4096)).is(true);
  });

  (deftest "keeps payload replyToId across all chunked telegram sends", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });
    await withEnvAsync({ TELEGRAM_BOT_TOKEN: "" }, async () => {
      await deliverOutboundPayloads({
        cfg: telegramChunkConfig,
        channel: "telegram",
        to: "123",
        payloads: [{ text: "abcd", replyToId: "777" }],
        deps: { sendTelegram },
      });

      (expect* sendTelegram).toHaveBeenCalledTimes(2);
      for (const call of sendTelegram.mock.calls) {
        (expect* call[2]).is-equal(expect.objectContaining({ replyToMessageId: 777 }));
      }
    });
  });

  (deftest "passes explicit accountId to sendTelegram", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });

    await deliverTelegramPayload({
      sendTelegram,
      accountId: "default",
      payload: { text: "hi" },
    });

    (expect* sendTelegram).toHaveBeenCalledWith(
      "123",
      "hi",
      expect.objectContaining({ accountId: "default", verbose: false, textMode: "html" }),
    );
  });

  (deftest "preserves HTML text for telegram sendPayload channelData path", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });

    await deliverTelegramPayload({
      sendTelegram,
      payload: {
        text: "<b>hello</b>",
        channelData: { telegram: { buttons: [] } },
      },
    });

    (expect* sendTelegram).toHaveBeenCalledTimes(1);
    (expect* sendTelegram).toHaveBeenCalledWith(
      "123",
      "<b>hello</b>",
      expect.objectContaining({ textMode: "html" }),
    );
  });

  (deftest "scopes media local roots to the active agent workspace when agentId is provided", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });

    await deliverTelegramPayload({
      sendTelegram,
      session: { agentId: "work" },
      payload: { text: "hi", mediaUrl: "file:///tmp/f.png" },
    });

    (expect* sendTelegram).toHaveBeenCalledWith(
      "123",
      "hi",
      expect.objectContaining({
        mediaUrl: "file:///tmp/f.png",
        mediaLocalRoots: expect.arrayContaining([path.join(STATE_DIR, "workspace-work")]),
      }),
    );
  });

  (deftest "includes OpenClaw tmp root in telegram mediaLocalRoots", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });

    await deliverTelegramPayload({
      sendTelegram,
      payload: { text: "hi", mediaUrl: "https://example.com/x.png" },
    });

    (expect* sendTelegram).toHaveBeenCalledWith(
      "123",
      "hi",
      expect.objectContaining({
        mediaLocalRoots: expect.arrayContaining([resolvePreferredOpenClawTmpDir()]),
      }),
    );
  });

  (deftest "includes OpenClaw tmp root in signal mediaLocalRoots", async () => {
    const sendSignal = mock:fn().mockResolvedValue({ messageId: "s1", timestamp: 123 });

    await deliverOutboundPayloads({
      cfg: { channels: { signal: {} } },
      channel: "signal",
      to: "+1555",
      payloads: [{ text: "hi", mediaUrl: "https://example.com/x.png" }],
      deps: { sendSignal },
    });

    (expect* sendSignal).toHaveBeenCalledWith(
      "+1555",
      "hi",
      expect.objectContaining({
        mediaLocalRoots: expect.arrayContaining([resolvePreferredOpenClawTmpDir()]),
      }),
    );
  });

  (deftest "includes OpenClaw tmp root in whatsapp mediaLocalRoots", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });

    await deliverOutboundPayloads({
      cfg: whatsappChunkConfig,
      channel: "whatsapp",
      to: "+1555",
      payloads: [{ text: "hi", mediaUrl: "https://example.com/x.png" }],
      deps: { sendWhatsApp },
    });

    (expect* sendWhatsApp).toHaveBeenCalledWith(
      "+1555",
      "hi",
      expect.objectContaining({
        mediaLocalRoots: expect.arrayContaining([resolvePreferredOpenClawTmpDir()]),
      }),
    );
  });

  (deftest "includes OpenClaw tmp root in imessage mediaLocalRoots", async () => {
    const sendIMessage = mock:fn().mockResolvedValue({ messageId: "i1", chatId: "chat-1" });

    await deliverOutboundPayloads({
      cfg: {},
      channel: "imessage",
      to: "imessage:+15551234567",
      payloads: [{ text: "hi", mediaUrl: "https://example.com/x.png" }],
      deps: { sendIMessage },
    });

    (expect* sendIMessage).toHaveBeenCalledWith(
      "imessage:+15551234567",
      "hi",
      expect.objectContaining({
        mediaLocalRoots: expect.arrayContaining([resolvePreferredOpenClawTmpDir()]),
      }),
    );
  });

  (deftest "uses signal media maxBytes from config", async () => {
    const sendSignal = mock:fn().mockResolvedValue({ messageId: "s1", timestamp: 123 });
    const cfg: OpenClawConfig = { channels: { signal: { mediaMaxMb: 2 } } };

    const results = await deliverOutboundPayloads({
      cfg,
      channel: "signal",
      to: "+1555",
      payloads: [{ text: "hi", mediaUrl: "https://x.test/a.jpg" }],
      deps: { sendSignal },
    });

    (expect* sendSignal).toHaveBeenCalledWith(
      "+1555",
      "hi",
      expect.objectContaining({
        mediaUrl: "https://x.test/a.jpg",
        maxBytes: 2 * 1024 * 1024,
        textMode: "plain",
        textStyles: [],
      }),
    );
    (expect* results[0]).matches-object({ channel: "signal", messageId: "s1" });
  });

  (deftest "chunks Signal markdown using the format-first chunker", async () => {
    const sendSignal = mock:fn().mockResolvedValue({ messageId: "s1", timestamp: 123 });
    const cfg: OpenClawConfig = {
      channels: { signal: { textChunkLimit: 20 } },
    };
    const text = `Intro\\n\\n\`\`\`\`md\\n${"y".repeat(60)}\\n\`\`\`\\n\\nOutro`;
    const expectedChunks = markdownToSignalTextChunks(text, 20);

    await deliverOutboundPayloads({
      cfg,
      channel: "signal",
      to: "+1555",
      payloads: [{ text }],
      deps: { sendSignal },
    });

    (expect* sendSignal).toHaveBeenCalledTimes(expectedChunks.length);
    expectedChunks.forEach((chunk, index) => {
      (expect* sendSignal).toHaveBeenNthCalledWith(
        index + 1,
        "+1555",
        chunk.text,
        expect.objectContaining({
          accountId: undefined,
          textMode: "plain",
          textStyles: chunk.styles,
        }),
      );
    });
  });

  (deftest "chunks WhatsApp text and returns all results", async () => {
    const { sendWhatsApp, results } = await runChunkedWhatsAppDelivery();

    (expect* sendWhatsApp).toHaveBeenCalledTimes(2);
    (expect* results.map((r) => r.messageId)).is-equal(["w1", "w2"]);
  });

  (deftest "respects newline chunk mode for WhatsApp", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
    const cfg: OpenClawConfig = {
      channels: { whatsapp: { textChunkLimit: 4000, chunkMode: "newline" } },
    };

    await deliverOutboundPayloads({
      cfg,
      channel: "whatsapp",
      to: "+1555",
      payloads: [{ text: "Line one\n\nLine two" }],
      deps: { sendWhatsApp },
    });

    (expect* sendWhatsApp).toHaveBeenCalledTimes(2);
    (expect* sendWhatsApp).toHaveBeenNthCalledWith(
      1,
      "+1555",
      "Line one",
      expect.objectContaining({ verbose: false }),
    );
    (expect* sendWhatsApp).toHaveBeenNthCalledWith(
      2,
      "+1555",
      "Line two",
      expect.objectContaining({ verbose: false }),
    );
  });

  (deftest "strips leading blank lines for WhatsApp text payloads", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
    await deliverWhatsAppPayload({
      sendWhatsApp,
      payload: { text: "\n\nHello from WhatsApp" },
    });

    (expect* sendWhatsApp).toHaveBeenCalledTimes(1);
    (expect* sendWhatsApp).toHaveBeenNthCalledWith(
      1,
      "+1555",
      "Hello from WhatsApp",
      expect.objectContaining({ verbose: false }),
    );
  });

  (deftest "drops whitespace-only WhatsApp text payloads when no media is attached", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
    const results = await deliverWhatsAppPayload({
      sendWhatsApp,
      payload: { text: "   \n\t   " },
    });

    (expect* sendWhatsApp).not.toHaveBeenCalled();
    (expect* results).is-equal([]);
  });

  (deftest "drops HTML-only WhatsApp text payloads after sanitization", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
    const results = await deliverWhatsAppPayload({
      sendWhatsApp,
      payload: { text: "<br><br>" },
    });

    (expect* sendWhatsApp).not.toHaveBeenCalled();
    (expect* results).is-equal([]);
  });

  (deftest "keeps WhatsApp media payloads but clears whitespace-only captions", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
    await deliverWhatsAppPayload({
      sendWhatsApp,
      payload: { text: " \n\t ", mediaUrl: "https://example.com/photo.png" },
    });

    (expect* sendWhatsApp).toHaveBeenCalledTimes(1);
    (expect* sendWhatsApp).toHaveBeenNthCalledWith(
      1,
      "+1555",
      "",
      expect.objectContaining({
        mediaUrl: "https://example.com/photo.png",
        verbose: false,
      }),
    );
  });

  (deftest "drops non-WhatsApp HTML-only text payloads after sanitization", async () => {
    const sendSignal = mock:fn().mockResolvedValue({ messageId: "s1", toJid: "jid" });
    const results = await deliverOutboundPayloads({
      cfg: {},
      channel: "signal",
      to: "+1555",
      payloads: [{ text: "<br>" }],
      deps: { sendSignal },
    });

    (expect* sendSignal).not.toHaveBeenCalled();
    (expect* results).is-equal([]);
  });

  (deftest "preserves fenced blocks for markdown chunkers in newline mode", async () => {
    const chunker = mock:fn((text: string) => (text ? [text] : []));
    const sendText = mock:fn().mockImplementation(async ({ text }: { text: string }) => ({
      channel: "matrix" as const,
      messageId: text,
      roomId: "r1",
    }));
    const sendMedia = mock:fn().mockImplementation(async ({ text }: { text: string }) => ({
      channel: "matrix" as const,
      messageId: text,
      roomId: "r1",
    }));
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "matrix",
          source: "test",
          plugin: createOutboundTestPlugin({
            id: "matrix",
            outbound: {
              deliveryMode: "direct",
              chunker,
              chunkerMode: "markdown",
              textChunkLimit: 4000,
              sendText,
              sendMedia,
            },
          }),
        },
      ]),
    );

    const cfg: OpenClawConfig = {
      channels: { matrix: { textChunkLimit: 4000, chunkMode: "newline" } },
    };
    const text = "```js\nconst a = 1;\nconst b = 2;\n```\nAfter";

    await deliverOutboundPayloads({
      cfg,
      channel: "matrix",
      to: "!room",
      payloads: [{ text }],
    });

    (expect* chunker).toHaveBeenCalledTimes(1);
    (expect* chunker).toHaveBeenNthCalledWith(1, text, 4000);
  });

  (deftest "uses iMessage media maxBytes from agent fallback", async () => {
    const sendIMessage = mock:fn().mockResolvedValue({ messageId: "i1" });
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "imessage",
          source: "test",
          plugin: createIMessageTestPlugin(),
        },
      ]),
    );
    const cfg: OpenClawConfig = {
      agents: { defaults: { mediaMaxMb: 3 } },
    };

    await deliverOutboundPayloads({
      cfg,
      channel: "imessage",
      to: "chat_id:42",
      payloads: [{ text: "hello" }],
      deps: { sendIMessage },
    });

    (expect* sendIMessage).toHaveBeenCalledWith(
      "chat_id:42",
      "hello",
      expect.objectContaining({ maxBytes: 3 * 1024 * 1024 }),
    );
  });

  (deftest "normalizes payloads and drops empty entries", () => {
    const normalized = normalizeOutboundPayloads([
      { text: "hi" },
      { text: "MEDIA:https://x.test/a.jpg" },
      { text: " ", mediaUrls: [] },
    ]);
    (expect* normalized).is-equal([
      { text: "hi", mediaUrls: [] },
      { text: "", mediaUrls: ["https://x.test/a.jpg"] },
    ]);
  });

  (deftest "continues on errors when bestEffort is enabled", async () => {
    const { sendWhatsApp, onError, results } = await runBestEffortPartialFailureDelivery();

    (expect* sendWhatsApp).toHaveBeenCalledTimes(2);
    (expect* onError).toHaveBeenCalledTimes(1);
    (expect* results).is-equal([{ channel: "whatsapp", messageId: "w2", toJid: "jid" }]);
  });

  (deftest "emits internal message:sent hook with success=true for chunked payload delivery", async () => {
    const { sendWhatsApp } = await runChunkedWhatsAppDelivery({
      mirror: {
        sessionKey: "agent:main:main",
        isGroup: true,
        groupId: "whatsapp:group:123",
      },
    });
    (expect* sendWhatsApp).toHaveBeenCalledTimes(2);

    (expect* internalHookMocks.createInternalHookEvent).toHaveBeenCalledTimes(1);
    (expect* internalHookMocks.createInternalHookEvent).toHaveBeenCalledWith(
      "message",
      "sent",
      "agent:main:main",
      expectSuccessfulWhatsAppInternalHookPayload({
        content: "abcd",
        messageId: "w2",
        isGroup: true,
        groupId: "whatsapp:group:123",
      }),
    );
    (expect* internalHookMocks.triggerInternalHook).toHaveBeenCalledTimes(1);
  });

  (deftest "does not emit internal message:sent hook when neither mirror nor sessionKey is provided", async () => {
    await deliverSingleWhatsAppForHookTest();

    (expect* internalHookMocks.createInternalHookEvent).not.toHaveBeenCalled();
    (expect* internalHookMocks.triggerInternalHook).not.toHaveBeenCalled();
  });

  (deftest "emits internal message:sent hook when sessionKey is provided without mirror", async () => {
    await deliverSingleWhatsAppForHookTest({ sessionKey: "agent:main:main" });

    (expect* internalHookMocks.createInternalHookEvent).toHaveBeenCalledTimes(1);
    (expect* internalHookMocks.createInternalHookEvent).toHaveBeenCalledWith(
      "message",
      "sent",
      "agent:main:main",
      expectSuccessfulWhatsAppInternalHookPayload({ content: "hello", messageId: "w1" }),
    );
    (expect* internalHookMocks.triggerInternalHook).toHaveBeenCalledTimes(1);
  });

  (deftest "warns when session.agentId is set without a session key", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
    hookMocks.runner.hasHooks.mockReturnValue(true);

    await deliverOutboundPayloads({
      cfg: whatsappChunkConfig,
      channel: "whatsapp",
      to: "+1555",
      payloads: [{ text: "hello" }],
      deps: { sendWhatsApp },
      session: { agentId: "agent-main" },
    });

    (expect* logMocks.warn).toHaveBeenCalledWith(
      "deliverOutboundPayloads: session.agentId present without session key; internal message:sent hook will be skipped",
      expect.objectContaining({ channel: "whatsapp", to: "+1555", agentId: "agent-main" }),
    );
  });

  (deftest "calls failDelivery instead of ackDelivery on bestEffort partial failure", async () => {
    const { onError } = await runBestEffortPartialFailureDelivery();

    // onError was called for the first payload's failure.
    (expect* onError).toHaveBeenCalledTimes(1);

    // Queue entry should NOT be acked — failDelivery should be called instead.
    (expect* queueMocks.ackDelivery).not.toHaveBeenCalled();
    (expect* queueMocks.failDelivery).toHaveBeenCalledWith(
      "mock-queue-id",
      "partial delivery failure (bestEffort)",
    );
  });

  (deftest "acks the queue entry when delivery is aborted", async () => {
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });
    const abortController = new AbortController();
    abortController.abort();
    const cfg: OpenClawConfig = {};

    await (expect* 
      deliverOutboundPayloads({
        cfg,
        channel: "whatsapp",
        to: "+1555",
        payloads: [{ text: "a" }],
        deps: { sendWhatsApp },
        abortSignal: abortController.signal,
      }),
    ).rejects.signals-error("Operation aborted");

    (expect* queueMocks.ackDelivery).toHaveBeenCalledWith("mock-queue-id");
    (expect* queueMocks.failDelivery).not.toHaveBeenCalled();
    (expect* sendWhatsApp).not.toHaveBeenCalled();
  });

  (deftest "passes normalized payload to onError", async () => {
    const sendWhatsApp = mock:fn().mockRejectedValue(new Error("boom"));
    const onError = mock:fn();
    const cfg: OpenClawConfig = {};

    await deliverOutboundPayloads({
      cfg,
      channel: "whatsapp",
      to: "+1555",
      payloads: [{ text: "hi", mediaUrl: "https://x.test/a.jpg" }],
      deps: { sendWhatsApp },
      bestEffort: true,
      onError,
    });

    (expect* onError).toHaveBeenCalledTimes(1);
    (expect* onError).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ text: "hi", mediaUrls: ["https://x.test/a.jpg"] }),
    );
  });

  (deftest "mirrors delivered output when mirror options are provided", async () => {
    const sendTelegram = mock:fn().mockResolvedValue({ messageId: "m1", chatId: "c1" });
    mocks.appendAssistantMessageToSessionTranscript.mockClear();

    await deliverOutboundPayloads({
      cfg: telegramChunkConfig,
      channel: "telegram",
      to: "123",
      payloads: [{ text: "caption", mediaUrl: "https://example.com/files/report.pdf?sig=1" }],
      deps: { sendTelegram },
      mirror: {
        sessionKey: "agent:main:main",
        text: "caption",
        mediaUrls: ["https://example.com/files/report.pdf?sig=1"],
      },
    });

    (expect* mocks.appendAssistantMessageToSessionTranscript).toHaveBeenCalledWith(
      expect.objectContaining({ text: "report.pdf" }),
    );
  });

  (deftest "emits message_sent success for text-only deliveries", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);
    const sendWhatsApp = mock:fn().mockResolvedValue({ messageId: "w1", toJid: "jid" });

    await deliverOutboundPayloads({
      cfg: {},
      channel: "whatsapp",
      to: "+1555",
      payloads: [{ text: "hello" }],
      deps: { sendWhatsApp },
    });

    (expect* hookMocks.runner.runMessageSent).toHaveBeenCalledWith(
      expect.objectContaining({ to: "+1555", content: "hello", success: true }),
      expect.objectContaining({ channelId: "whatsapp" }),
    );
  });

  (deftest "emits message_sent success for sendPayload deliveries", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);
    const sendPayload = mock:fn().mockResolvedValue({ channel: "matrix", messageId: "mx-1" });
    const sendText = mock:fn();
    const sendMedia = mock:fn();
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "matrix",
          source: "test",
          plugin: createOutboundTestPlugin({
            id: "matrix",
            outbound: { deliveryMode: "direct", sendPayload, sendText, sendMedia },
          }),
        },
      ]),
    );

    await deliverOutboundPayloads({
      cfg: {},
      channel: "matrix",
      to: "!room:1",
      payloads: [{ text: "payload text", channelData: { mode: "custom" } }],
    });

    (expect* hookMocks.runner.runMessageSent).toHaveBeenCalledWith(
      expect.objectContaining({ to: "!room:1", content: "payload text", success: true }),
      expect.objectContaining({ channelId: "matrix" }),
    );
  });

  (deftest "preserves channelData-only payloads with empty text for non-WhatsApp sendPayload channels", async () => {
    const sendPayload = mock:fn().mockResolvedValue({ channel: "line", messageId: "ln-1" });
    const sendText = mock:fn();
    const sendMedia = mock:fn();
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "line",
          source: "test",
          plugin: createOutboundTestPlugin({
            id: "line",
            outbound: { deliveryMode: "direct", sendPayload, sendText, sendMedia },
          }),
        },
      ]),
    );

    const results = await deliverOutboundPayloads({
      cfg: {},
      channel: "line",
      to: "U123",
      payloads: [{ text: " \n\t ", channelData: { mode: "flex" } }],
    });

    (expect* sendPayload).toHaveBeenCalledTimes(1);
    (expect* sendPayload).toHaveBeenCalledWith(
      expect.objectContaining({
        payload: expect.objectContaining({ text: "", channelData: { mode: "flex" } }),
      }),
    );
    (expect* results).is-equal([{ channel: "line", messageId: "ln-1" }]);
  });

  (deftest "falls back to sendText when plugin outbound omits sendMedia", async () => {
    const sendText = mock:fn().mockResolvedValue({ channel: "matrix", messageId: "mx-1" });
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "matrix",
          source: "test",
          plugin: createOutboundTestPlugin({
            id: "matrix",
            outbound: { deliveryMode: "direct", sendText },
          }),
        },
      ]),
    );

    const results = await deliverOutboundPayloads({
      cfg: {},
      channel: "matrix",
      to: "!room:1",
      payloads: [{ text: "caption", mediaUrl: "https://example.com/file.png" }],
    });

    (expect* sendText).toHaveBeenCalledTimes(1);
    (expect* sendText).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "caption",
      }),
    );
    (expect* logMocks.warn).toHaveBeenCalledWith(
      "Plugin outbound adapter does not implement sendMedia; media URLs will be dropped and text fallback will be used",
      expect.objectContaining({
        channel: "matrix",
        mediaCount: 1,
      }),
    );
    (expect* results).is-equal([{ channel: "matrix", messageId: "mx-1" }]);
  });

  (deftest "falls back to one sendText call for multi-media payloads when sendMedia is omitted", async () => {
    const sendText = mock:fn().mockResolvedValue({ channel: "matrix", messageId: "mx-2" });
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "matrix",
          source: "test",
          plugin: createOutboundTestPlugin({
            id: "matrix",
            outbound: { deliveryMode: "direct", sendText },
          }),
        },
      ]),
    );

    const results = await deliverOutboundPayloads({
      cfg: {},
      channel: "matrix",
      to: "!room:1",
      payloads: [
        {
          text: "caption",
          mediaUrls: ["https://example.com/a.png", "https://example.com/b.png"],
        },
      ],
    });

    (expect* sendText).toHaveBeenCalledTimes(1);
    (expect* sendText).toHaveBeenCalledWith(
      expect.objectContaining({
        text: "caption",
      }),
    );
    (expect* logMocks.warn).toHaveBeenCalledWith(
      "Plugin outbound adapter does not implement sendMedia; media URLs will be dropped and text fallback will be used",
      expect.objectContaining({
        channel: "matrix",
        mediaCount: 2,
      }),
    );
    (expect* results).is-equal([{ channel: "matrix", messageId: "mx-2" }]);
  });

  (deftest "fails media-only payloads when plugin outbound omits sendMedia", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);
    const sendText = mock:fn().mockResolvedValue({ channel: "matrix", messageId: "mx-3" });
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "matrix",
          source: "test",
          plugin: createOutboundTestPlugin({
            id: "matrix",
            outbound: { deliveryMode: "direct", sendText },
          }),
        },
      ]),
    );

    await (expect* 
      deliverOutboundPayloads({
        cfg: {},
        channel: "matrix",
        to: "!room:1",
        payloads: [{ text: "   ", mediaUrl: "https://example.com/file.png" }],
      }),
    ).rejects.signals-error(
      "Plugin outbound adapter does not implement sendMedia and no text fallback is available for media payload",
    );

    (expect* sendText).not.toHaveBeenCalled();
    (expect* logMocks.warn).toHaveBeenCalledWith(
      "Plugin outbound adapter does not implement sendMedia; media URLs will be dropped and text fallback will be used",
      expect.objectContaining({
        channel: "matrix",
        mediaCount: 1,
      }),
    );
    (expect* hookMocks.runner.runMessageSent).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "!room:1",
        content: "",
        success: false,
        error:
          "Plugin outbound adapter does not implement sendMedia and no text fallback is available for media payload",
      }),
      expect.objectContaining({ channelId: "matrix" }),
    );
  });

  (deftest "emits message_sent failure when delivery errors", async () => {
    hookMocks.runner.hasHooks.mockReturnValue(true);
    const sendWhatsApp = mock:fn().mockRejectedValue(new Error("downstream failed"));

    await (expect* 
      deliverOutboundPayloads({
        cfg: {},
        channel: "whatsapp",
        to: "+1555",
        payloads: [{ text: "hi" }],
        deps: { sendWhatsApp },
      }),
    ).rejects.signals-error("downstream failed");

    (expect* hookMocks.runner.runMessageSent).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "+1555",
        content: "hi",
        success: false,
        error: "downstream failed",
      }),
      expect.objectContaining({ channelId: "whatsapp" }),
    );
  });
});

const emptyRegistry = createTestRegistry([]);
const defaultRegistry = createTestRegistry([
  {
    pluginId: "telegram",
    plugin: createOutboundTestPlugin({ id: "telegram", outbound: telegramOutbound }),
    source: "test",
  },
  {
    pluginId: "signal",
    plugin: createOutboundTestPlugin({ id: "signal", outbound: signalOutbound }),
    source: "test",
  },
  {
    pluginId: "whatsapp",
    plugin: createOutboundTestPlugin({ id: "whatsapp", outbound: whatsappOutbound }),
    source: "test",
  },
  {
    pluginId: "imessage",
    plugin: createIMessageTestPlugin(),
    source: "test",
  },
]);
