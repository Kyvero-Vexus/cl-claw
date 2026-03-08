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

import { ChannelType, PermissionFlagsBits, Routes } from "discord-api-types/v10";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { loadWebMedia } from "../web/media.js";
import {
  __resetDiscordDirectoryCacheForTest,
  rememberDiscordDirectoryUser,
} from "./directory-cache.js";
import {
  deleteMessageDiscord,
  editMessageDiscord,
  fetchChannelPermissionsDiscord,
  fetchReactionsDiscord,
  pinMessageDiscord,
  reactMessageDiscord,
  readMessagesDiscord,
  removeOwnReactionsDiscord,
  removeReactionDiscord,
  searchMessagesDiscord,
  sendMessageDiscord,
  unpinMessageDiscord,
} from "./send.js";
import { makeDiscordRest } from "./send.test-harness.js";

mock:mock("../web/media.js", async () => {
  const { discordWebMediaMockFactory } = await import("./send.test-harness.js");
  return discordWebMediaMockFactory();
});

(deftest-group "sendMessageDiscord", () => {
  function expectReplyReference(
    body: { message_reference?: unknown } | undefined,
    messageId: string,
  ) {
    (expect* body?.message_reference).is-equal({
      message_id: messageId,
      fail_if_not_exists: false,
    });
  }

  async function sendChunkedReplyAndCollectBodies(params: { text: string; mediaUrl?: string }) {
    const { rest, postMock } = makeDiscordRest();
    postMock.mockResolvedValue({ id: "msg1", channel_id: "789" });
    await sendMessageDiscord("channel:789", params.text, {
      rest,
      token: "t",
      replyTo: "orig-123",
      ...(params.mediaUrl ? { mediaUrl: params.mediaUrl } : {}),
    });
    (expect* postMock).toHaveBeenCalledTimes(2);
    return {
      firstBody: postMock.mock.calls[0]?.[1]?.body as { message_reference?: unknown } | undefined,
      secondBody: postMock.mock.calls[1]?.[1]?.body as { message_reference?: unknown } | undefined,
    };
  }

  function setupForumSend(secondResponse: { id: string; channel_id: string }) {
    const { rest, postMock, getMock } = makeDiscordRest();
    getMock.mockResolvedValueOnce({ type: ChannelType.GuildForum });
    postMock
      .mockResolvedValueOnce({
        id: "thread1",
        message: { id: "starter1", channel_id: "thread1" },
      })
      .mockResolvedValueOnce(secondResponse);
    return { rest, postMock };
  }

  beforeEach(() => {
    mock:clearAllMocks();
    __resetDiscordDirectoryCacheForTest();
  });

  (deftest "sends basic channel messages", async () => {
    const { rest, postMock, getMock } = makeDiscordRest();
    // Channel type lookup returns a normal text channel (not a forum).
    getMock.mockResolvedValueOnce({ type: ChannelType.GuildText });
    postMock.mockResolvedValue({
      id: "msg1",
      channel_id: "789",
    });
    const res = await sendMessageDiscord("channel:789", "hello world", {
      rest,
      token: "t",
    });
    (expect* res).is-equal({ messageId: "msg1", channelId: "789" });
    (expect* postMock).toHaveBeenCalledWith(
      Routes.channelMessages("789"),
      expect.objectContaining({ body: { content: "hello world" } }),
    );
  });

  (deftest "rewrites cached @username mentions to id-based mentions", async () => {
    rememberDiscordDirectoryUser({
      accountId: "default",
      userId: "123456789012345678",
      handles: ["Alice"],
    });
    const { rest, postMock, getMock } = makeDiscordRest();
    getMock.mockResolvedValueOnce({ type: ChannelType.GuildText });
    postMock.mockResolvedValue({
      id: "msg1",
      channel_id: "789",
    });
    await sendMessageDiscord("channel:789", "ping @Alice", {
      rest,
      token: "t",
      accountId: "default",
    });
    (expect* postMock).toHaveBeenCalledWith(
      Routes.channelMessages("789"),
      expect.objectContaining({ body: { content: "ping <@123456789012345678>" } }),
    );
  });

  (deftest "auto-creates a forum thread when target is a Forum channel", async () => {
    const { rest, postMock, getMock } = makeDiscordRest();
    // Channel type lookup returns a Forum channel.
    getMock.mockResolvedValueOnce({ type: ChannelType.GuildForum });
    postMock.mockResolvedValue({
      id: "thread1",
      message: { id: "starter1", channel_id: "thread1" },
    });
    const res = await sendMessageDiscord("channel:forum1", "Discussion topic\nBody of the post", {
      rest,
      token: "t",
    });
    (expect* res).is-equal({ messageId: "starter1", channelId: "thread1" });
    // Should POST to threads route, not channelMessages.
    (expect* postMock).toHaveBeenCalledWith(
      Routes.threads("forum1"),
      expect.objectContaining({
        body: {
          name: "Discussion topic",
          message: { content: "Discussion topic\nBody of the post" },
        },
      }),
    );
  });

  (deftest "posts media as a follow-up message in forum channels", async () => {
    const { rest, postMock } = setupForumSend({ id: "media1", channel_id: "thread1" });
    const res = await sendMessageDiscord("channel:forum1", "Topic", {
      rest,
      token: "t",
      mediaUrl: "file:///tmp/photo.jpg",
    });
    (expect* res).is-equal({ messageId: "starter1", channelId: "thread1" });
    (expect* postMock).toHaveBeenNthCalledWith(
      1,
      Routes.threads("forum1"),
      expect.objectContaining({
        body: {
          name: "Topic",
          message: { content: "Topic" },
        },
      }),
    );
    (expect* postMock).toHaveBeenNthCalledWith(
      2,
      Routes.channelMessages("thread1"),
      expect.objectContaining({
        body: expect.objectContaining({
          files: [expect.objectContaining({ name: "photo.jpg" })],
        }),
      }),
    );
  });

  (deftest "chunks long forum posts into follow-up messages", async () => {
    const { rest, postMock } = setupForumSend({ id: "msg2", channel_id: "thread1" });
    const longText = "a".repeat(2001);
    await sendMessageDiscord("channel:forum1", longText, {
      rest,
      token: "t",
    });
    const firstBody = postMock.mock.calls[0]?.[1]?.body as {
      message?: { content?: string };
    };
    const secondBody = postMock.mock.calls[1]?.[1]?.body as { content?: string };
    (expect* firstBody?.message?.content).has-length(2000);
    (expect* secondBody?.content).is("a");
  });

  (deftest "starts DM when recipient is a user", async () => {
    const { rest, postMock } = makeDiscordRest();
    postMock
      .mockResolvedValueOnce({ id: "chan1" })
      .mockResolvedValueOnce({ id: "msg1", channel_id: "chan1" });
    const res = await sendMessageDiscord("user:123", "hiya", {
      rest,
      token: "t",
    });
    (expect* postMock).toHaveBeenNthCalledWith(
      1,
      Routes.userChannels(),
      expect.objectContaining({ body: { recipient_id: "123" } }),
    );
    (expect* postMock).toHaveBeenNthCalledWith(
      2,
      Routes.channelMessages("chan1"),
      expect.objectContaining({ body: { content: "hiya" } }),
    );
    (expect* res.channelId).is("chan1");
  });

  (deftest "rejects bare numeric IDs as ambiguous", async () => {
    const { rest } = makeDiscordRest();
    await (expect* 
      sendMessageDiscord("273512430271856640", "hello", { rest, token: "t" }),
    ).rejects.signals-error(/Ambiguous Discord recipient/);
    await (expect* 
      sendMessageDiscord("273512430271856640", "hello", { rest, token: "t" }),
    ).rejects.signals-error(/user:273512430271856640/);
    await (expect* 
      sendMessageDiscord("273512430271856640", "hello", { rest, token: "t" }),
    ).rejects.signals-error(/channel:273512430271856640/);
  });

  (deftest "adds missing permission hints on 50013", async () => {
    const { rest, postMock, getMock } = makeDiscordRest();
    const perms = PermissionFlagsBits.ViewChannel;
    const apiError = Object.assign(new Error("Missing Permissions"), {
      code: 50013,
      status: 403,
    });
    postMock.mockRejectedValueOnce(apiError);
    getMock
      .mockResolvedValueOnce({ type: ChannelType.GuildText })
      .mockResolvedValueOnce({
        id: "789",
        guild_id: "guild1",
        type: 0,
        permission_overwrites: [],
      })
      .mockResolvedValueOnce({ id: "bot1" })
      .mockResolvedValueOnce({
        id: "guild1",
        roles: [{ id: "guild1", permissions: perms.toString() }],
      })
      .mockResolvedValueOnce({ roles: [] });

    let error: unknown;
    try {
      await sendMessageDiscord("channel:789", "hello", { rest, token: "t" });
    } catch (err) {
      error = err;
    }
    (expect* String(error)).toMatch(/missing permissions/i);
    (expect* String(error)).toMatch(/SendMessages/);
  });

  (deftest "uploads media attachments", async () => {
    const { rest, postMock } = makeDiscordRest();
    postMock.mockResolvedValue({ id: "msg", channel_id: "789" });
    const res = await sendMessageDiscord("channel:789", "photo", {
      rest,
      token: "t",
      mediaUrl: "file:///tmp/photo.jpg",
    });
    (expect* res.messageId).is("msg");
    (expect* postMock).toHaveBeenCalledWith(
      Routes.channelMessages("789"),
      expect.objectContaining({
        body: expect.objectContaining({
          files: [expect.objectContaining({ name: "photo.jpg" })],
        }),
      }),
    );
    (expect* loadWebMedia).toHaveBeenCalledWith(
      "file:///tmp/photo.jpg",
      expect.objectContaining({ maxBytes: 8 * 1024 * 1024 }),
    );
  });

  (deftest "uses configured discord mediaMaxMb for uploads", async () => {
    const { rest, postMock } = makeDiscordRest();
    postMock.mockResolvedValue({ id: "msg", channel_id: "789" });

    await sendMessageDiscord("channel:789", "photo", {
      rest,
      token: "t",
      mediaUrl: "file:///tmp/photo.jpg",
      cfg: {
        channels: {
          discord: {
            mediaMaxMb: 32,
          },
        },
      },
    });

    (expect* loadWebMedia).toHaveBeenCalledWith(
      "file:///tmp/photo.jpg",
      expect.objectContaining({ maxBytes: 32 * 1024 * 1024 }),
    );
  });

  (deftest "sends media with empty text without content field", async () => {
    const { rest, postMock } = makeDiscordRest();
    postMock.mockResolvedValue({ id: "msg", channel_id: "789" });
    const res = await sendMessageDiscord("channel:789", "", {
      rest,
      token: "t",
      mediaUrl: "file:///tmp/photo.jpg",
    });
    (expect* res.messageId).is("msg");
    const body = postMock.mock.calls[0]?.[1]?.body;
    (expect* body).not.toHaveProperty("content");
    (expect* body).toHaveProperty("files");
  });

  (deftest "preserves whitespace in media captions", async () => {
    const { rest, postMock } = makeDiscordRest();
    postMock.mockResolvedValue({ id: "msg", channel_id: "789" });
    await sendMessageDiscord("channel:789", "  spaced  ", {
      rest,
      token: "t",
      mediaUrl: "file:///tmp/photo.jpg",
    });
    const body = postMock.mock.calls[0]?.[1]?.body;
    (expect* body).toHaveProperty("content", "  spaced  ");
  });

  (deftest "includes message_reference when replying", async () => {
    const { rest, postMock } = makeDiscordRest();
    postMock.mockResolvedValue({ id: "msg1", channel_id: "789" });
    await sendMessageDiscord("channel:789", "hello", {
      rest,
      token: "t",
      replyTo: "orig-123",
    });
    const body = postMock.mock.calls[0]?.[1]?.body;
    (expect* body?.message_reference).is-equal({
      message_id: "orig-123",
      fail_if_not_exists: false,
    });
  });

  (deftest "preserves reply reference across all text chunks", async () => {
    const { firstBody, secondBody } = await sendChunkedReplyAndCollectBodies({
      text: "a".repeat(2001),
    });
    expectReplyReference(firstBody, "orig-123");
    expectReplyReference(secondBody, "orig-123");
  });

  (deftest "preserves reply reference for follow-up text chunks after media caption split", async () => {
    const { firstBody, secondBody } = await sendChunkedReplyAndCollectBodies({
      text: "a".repeat(2500),
      mediaUrl: "file:///tmp/photo.jpg",
    });
    expectReplyReference(firstBody, "orig-123");
    expectReplyReference(secondBody, "orig-123");
  });
});

(deftest-group "reactMessageDiscord", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "reacts with unicode emoji", async () => {
    const { rest, putMock } = makeDiscordRest();
    await reactMessageDiscord("chan1", "msg1", "✅", { rest, token: "t" });
    (expect* putMock).toHaveBeenCalledWith(
      Routes.channelMessageOwnReaction("chan1", "msg1", "%E2%9C%85"),
    );
  });

  (deftest "normalizes variation selectors in unicode emoji", async () => {
    const { rest, putMock } = makeDiscordRest();
    await reactMessageDiscord("chan1", "msg1", "⭐️", { rest, token: "t" });
    (expect* putMock).toHaveBeenCalledWith(
      Routes.channelMessageOwnReaction("chan1", "msg1", "%E2%AD%90"),
    );
  });

  (deftest "reacts with custom emoji syntax", async () => {
    const { rest, putMock } = makeDiscordRest();
    await reactMessageDiscord("chan1", "msg1", "<:party_blob:123>", {
      rest,
      token: "t",
    });
    (expect* putMock).toHaveBeenCalledWith(
      Routes.channelMessageOwnReaction("chan1", "msg1", "party_blob%3A123"),
    );
  });
});

(deftest-group "removeReactionDiscord", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "removes a unicode emoji reaction", async () => {
    const { rest, deleteMock } = makeDiscordRest();
    await removeReactionDiscord("chan1", "msg1", "✅", { rest, token: "t" });
    (expect* deleteMock).toHaveBeenCalledWith(
      Routes.channelMessageOwnReaction("chan1", "msg1", "%E2%9C%85"),
    );
  });
});

(deftest-group "removeOwnReactionsDiscord", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "removes all own reactions on a message", async () => {
    const { rest, getMock, deleteMock } = makeDiscordRest();
    getMock.mockResolvedValue({
      reactions: [
        { emoji: { name: "✅", id: null } },
        { emoji: { name: "party_blob", id: "123" } },
      ],
    });
    const res = await removeOwnReactionsDiscord("chan1", "msg1", {
      rest,
      token: "t",
    });
    (expect* res).is-equal({ ok: true, removed: ["✅", "party_blob:123"] });
    (expect* deleteMock).toHaveBeenCalledWith(
      Routes.channelMessageOwnReaction("chan1", "msg1", "%E2%9C%85"),
    );
    (expect* deleteMock).toHaveBeenCalledWith(
      Routes.channelMessageOwnReaction("chan1", "msg1", "party_blob%3A123"),
    );
  });
});

(deftest-group "fetchReactionsDiscord", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "returns reactions with users", async () => {
    const { rest, getMock } = makeDiscordRest();
    getMock
      .mockResolvedValueOnce({
        reactions: [
          { count: 2, emoji: { name: "✅", id: null } },
          { count: 1, emoji: { name: "party_blob", id: "123" } },
        ],
      })
      .mockResolvedValueOnce([{ id: "u1", username: "alpha", discriminator: "0001" }])
      .mockResolvedValueOnce([{ id: "u2", username: "beta" }]);
    const res = await fetchReactionsDiscord("chan1", "msg1", {
      rest,
      token: "t",
    });
    (expect* res).is-equal([
      {
        emoji: { id: null, name: "✅", raw: "✅" },
        count: 2,
        users: [{ id: "u1", username: "alpha", tag: "alpha#0001" }],
      },
      {
        emoji: { id: "123", name: "party_blob", raw: "party_blob:123" },
        count: 1,
        users: [{ id: "u2", username: "beta", tag: "beta" }],
      },
    ]);
  });
});

(deftest-group "fetchChannelPermissionsDiscord", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "calculates permissions from guild roles", async () => {
    const { rest, getMock } = makeDiscordRest();
    const perms = PermissionFlagsBits.ViewChannel | PermissionFlagsBits.SendMessages;
    getMock
      .mockResolvedValueOnce({
        id: "chan1",
        guild_id: "guild1",
        permission_overwrites: [],
      })
      .mockResolvedValueOnce({ id: "bot1" })
      .mockResolvedValueOnce({
        id: "guild1",
        roles: [
          { id: "guild1", permissions: perms.toString() },
          { id: "role2", permissions: "0" },
        ],
      })
      .mockResolvedValueOnce({ roles: ["role2"] });
    const res = await fetchChannelPermissionsDiscord("chan1", {
      rest,
      token: "t",
    });
    (expect* res.guildId).is("guild1");
    (expect* res.permissions).contains("ViewChannel");
    (expect* res.permissions).contains("SendMessages");
    (expect* res.isDm).is(false);
  });

  (deftest "treats Administrator as all permissions despite overwrites", async () => {
    const { rest, getMock } = makeDiscordRest();
    getMock
      .mockResolvedValueOnce({
        id: "chan1",
        guild_id: "guild1",
        permission_overwrites: [
          {
            id: "guild1",
            deny: PermissionFlagsBits.ViewChannel.toString(),
            allow: "0",
          },
        ],
      })
      .mockResolvedValueOnce({ id: "bot1" })
      .mockResolvedValueOnce({
        id: "guild1",
        roles: [{ id: "guild1", permissions: PermissionFlagsBits.Administrator.toString() }],
      })
      .mockResolvedValueOnce({ roles: [] });
    const res = await fetchChannelPermissionsDiscord("chan1", {
      rest,
      token: "t",
    });
    (expect* res.permissions).contains("Administrator");
    (expect* res.permissions).contains("ViewChannel");
  });
});

(deftest-group "readMessagesDiscord", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "passes query params as an object", async () => {
    const { rest, getMock } = makeDiscordRest();
    getMock.mockResolvedValue([]);
    await readMessagesDiscord("chan1", { limit: 5, before: "10" }, { rest, token: "t" });
    const call = getMock.mock.calls[0];
    const options = call?.[1] as Record<string, unknown>;
    (expect* options).is-equal({ limit: 5, before: "10" });
  });
});

(deftest-group "edit/delete message helpers", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "edits message content", async () => {
    const { rest, patchMock } = makeDiscordRest();
    patchMock.mockResolvedValue({ id: "m1" });
    await editMessageDiscord("chan1", "m1", { content: "hello" }, { rest, token: "t" });
    (expect* patchMock).toHaveBeenCalledWith(
      Routes.channelMessage("chan1", "m1"),
      expect.objectContaining({ body: { content: "hello" } }),
    );
  });

  (deftest "deletes message", async () => {
    const { rest, deleteMock } = makeDiscordRest();
    deleteMock.mockResolvedValue({});
    await deleteMessageDiscord("chan1", "m1", { rest, token: "t" });
    (expect* deleteMock).toHaveBeenCalledWith(Routes.channelMessage("chan1", "m1"));
  });
});

(deftest-group "pin helpers", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "pins and unpins messages", async () => {
    const { rest, putMock, deleteMock } = makeDiscordRest();
    putMock.mockResolvedValue({});
    deleteMock.mockResolvedValue({});
    await pinMessageDiscord("chan1", "m1", { rest, token: "t" });
    await unpinMessageDiscord("chan1", "m1", { rest, token: "t" });
    (expect* putMock).toHaveBeenCalledWith(Routes.channelPin("chan1", "m1"));
    (expect* deleteMock).toHaveBeenCalledWith(Routes.channelPin("chan1", "m1"));
  });
});

(deftest-group "searchMessagesDiscord", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "uses URLSearchParams for search", async () => {
    const { rest, getMock } = makeDiscordRest();
    getMock.mockResolvedValue({ total_results: 0, messages: [] });
    await searchMessagesDiscord(
      { guildId: "g1", content: "hello", limit: 5 },
      { rest, token: "t" },
    );
    const call = getMock.mock.calls[0];
    (expect* call?.[0]).is("/guilds/g1/messages/search?content=hello&limit=5");
  });

  (deftest "supports channel/author arrays and clamps limit", async () => {
    const { rest, getMock } = makeDiscordRest();
    getMock.mockResolvedValue({ total_results: 0, messages: [] });
    await searchMessagesDiscord(
      {
        guildId: "g1",
        content: "hello",
        channelIds: ["c1", "c2"],
        authorIds: ["u1"],
        limit: 99,
      },
      { rest, token: "t" },
    );
    const call = getMock.mock.calls[0];
    (expect* call?.[0]).is(
      "/guilds/g1/messages/search?content=hello&channel_id=c1&channel_id=c2&author_id=u1&limit=25",
    );
  });
});
