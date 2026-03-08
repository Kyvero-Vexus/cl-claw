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

import type { Client } from "@buape/carbon";
import { ChannelType, MessageType } from "@buape/carbon";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  dispatchMock,
  readAllowFromStoreMock,
  sendMock,
  updateLastRouteMock,
  upsertPairingRequestMock,
} from "./monitor.tool-result.test-harness.js";
import { createDiscordMessageHandler } from "./monitor/message-handler.js";
import { __resetDiscordChannelInfoCacheForTest } from "./monitor/message-utils.js";
import { createNoopThreadBindingManager } from "./monitor/thread-bindings.js";

type Config = ReturnType<typeof import("../config/config.js").loadConfig>;

beforeEach(() => {
  __resetDiscordChannelInfoCacheForTest();
  sendMock.mockClear().mockResolvedValue(undefined);
  updateLastRouteMock.mockClear();
  dispatchMock.mockClear().mockImplementation(async ({ dispatcher }) => {
    dispatcher.sendFinalReply({ text: "hi" });
    return { queuedFinal: true, counts: { tool: 0, block: 0, final: 1 } };
  });
  readAllowFromStoreMock.mockClear().mockResolvedValue([]);
  upsertPairingRequestMock.mockClear().mockResolvedValue({ code: "PAIRCODE", created: true });
});

const BASE_CFG: Config = {
  agents: {
    defaults: {
      model: { primary: "anthropic/claude-opus-4-5" },
      workspace: "/tmp/openclaw",
    },
  },
  session: { store: "/tmp/openclaw-sessions.json" },
};

const CATEGORY_GUILD_CFG = {
  ...BASE_CFG,
  channels: {
    discord: {
      dm: { enabled: true, policy: "open" },
      guilds: {
        "*": {
          requireMention: false,
          channels: { c1: { allow: true } },
        },
      },
    },
  },
} satisfies Config;

function createHandlerBaseConfig(
  cfg: Config,
  runtimeError?: (err: unknown) => void,
): Parameters<typeof createDiscordMessageHandler>[0] {
  return {
    cfg,
    discordConfig: cfg.channels?.discord,
    accountId: "default",
    token: "token",
    runtime: {
      log: mock:fn(),
      error: runtimeError ?? mock:fn(),
      exit: (code: number): never => {
        error(`exit ${code}`);
      },
    },
    botUserId: "bot-id",
    guildHistories: new Map(),
    historyLimit: 0,
    mediaMaxBytes: 10_000,
    textLimit: 2000,
    replyToMode: "off",
    dmEnabled: true,
    groupDmEnabled: false,
    threadBindings: createNoopThreadBindingManager("default"),
  };
}

async function createDmHandler(opts: { cfg: Config; runtimeError?: (err: unknown) => void }) {
  return createDiscordMessageHandler(createHandlerBaseConfig(opts.cfg, opts.runtimeError));
}

function createDmClient() {
  return {
    fetchChannel: mock:fn().mockResolvedValue({
      type: ChannelType.DM,
      name: "dm",
    }),
  } as unknown as Client;
}

async function createCategoryGuildHandler() {
  return createDiscordMessageHandler({
    ...createHandlerBaseConfig(CATEGORY_GUILD_CFG),
    guildEntries: {
      "*": { requireMention: false, channels: { c1: { allow: true } } },
    },
  });
}

function createCategoryGuildClient() {
  return {
    fetchChannel: mock:fn().mockResolvedValue({
      type: ChannelType.GuildText,
      name: "general",
      parentId: "category-1",
    }),
    rest: { get: mock:fn() },
  } as unknown as Client;
}

function createCategoryGuildEvent(params: {
  messageId: string;
  timestamp?: string;
  author: Record<string, unknown>;
}) {
  return {
    message: {
      id: params.messageId,
      content: "hello",
      channelId: "c1",
      timestamp: params.timestamp ?? new Date().toISOString(),
      type: MessageType.Default,
      attachments: [],
      embeds: [],
      mentionedEveryone: false,
      mentionedUsers: [],
      mentionedRoles: [],
      author: params.author,
    },
    author: params.author,
    member: { displayName: "Ada" },
    guild: { id: "g1", name: "Guild" },
    guild_id: "g1",
  };
}

(deftest-group "discord tool result dispatch", () => {
  (deftest "uses channel id allowlists for non-thread channels with categories", async () => {
    let capturedCtx: { SessionKey?: string } | undefined;
    dispatchMock.mockImplementationOnce(async ({ ctx, dispatcher }) => {
      capturedCtx = ctx;
      dispatcher.sendFinalReply({ text: "hi" });
      return { queuedFinal: true, counts: { final: 1 } };
    });

    const handler = await createCategoryGuildHandler();
    const client = createCategoryGuildClient();

    await handler(
      createCategoryGuildEvent({
        messageId: "m-category",
        author: { id: "u1", bot: false, username: "Ada", tag: "Ada#1" },
      }),
      client,
    );

    await mock:waitFor(() => (expect* dispatchMock).toHaveBeenCalledTimes(1));
    (expect* capturedCtx?.SessionKey).is("agent:main:discord:channel:c1");
  });

  (deftest "prefixes group bodies with sender label", async () => {
    let capturedBody = "";
    dispatchMock.mockImplementationOnce(async ({ ctx, dispatcher }) => {
      capturedBody = ctx.Body ?? "";
      dispatcher.sendFinalReply({ text: "ok" });
      return { queuedFinal: true, counts: { final: 1 } };
    });

    const handler = await createCategoryGuildHandler();
    const client = createCategoryGuildClient();

    await handler(
      createCategoryGuildEvent({
        messageId: "m-prefix",
        timestamp: new Date("2026-01-17T00:00:00Z").toISOString(),
        author: { id: "u1", bot: false, username: "Ada", discriminator: "1234" },
      }),
      client,
    );

    await mock:waitFor(() => (expect* dispatchMock).toHaveBeenCalledTimes(1));
    (expect* capturedBody).contains("Ada (Ada#1234): hello");
  });

  (deftest "replies with pairing code and sender id when dmPolicy is pairing", async () => {
    const cfg = {
      ...BASE_CFG,
      channels: {
        discord: { dm: { enabled: true, policy: "pairing", allowFrom: [] } },
      },
    } as Config;

    const handler = await createDmHandler({ cfg });
    const client = createDmClient();

    await handler(
      {
        message: {
          id: "m1",
          content: "hello",
          channelId: "c1",
          timestamp: new Date().toISOString(),
          type: MessageType.Default,
          attachments: [],
          embeds: [],
          mentionedEveryone: false,
          mentionedUsers: [],
          mentionedRoles: [],
          author: { id: "u2", bot: false, username: "Ada" },
        },
        author: { id: "u2", bot: false, username: "Ada" },
        guild_id: null,
      },
      client,
    );

    (expect* dispatchMock).not.toHaveBeenCalled();
    (expect* upsertPairingRequestMock).toHaveBeenCalled();
    (expect* sendMock).toHaveBeenCalledTimes(1);
    (expect* String(sendMock.mock.calls[0]?.[1] ?? "")).contains("Your Discord user id: u2");
    (expect* String(sendMock.mock.calls[0]?.[1] ?? "")).contains("Pairing code: PAIRCODE");
  }, 10000);
});
