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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  DEFAULT_DISCORD_BOT_USER_ID,
  createDiscordHandlerParams,
  createDiscordPreflightContext,
} from "./message-handler.test-helpers.js";

const preflightDiscordMessageMock = mock:hoisted(() => mock:fn());
const processDiscordMessageMock = mock:hoisted(() => mock:fn());

mock:mock("./message-handler.preflight.js", () => ({
  preflightDiscordMessage: preflightDiscordMessageMock,
}));

mock:mock("./message-handler.process.js", () => ({
  processDiscordMessage: processDiscordMessageMock,
}));

const { createDiscordMessageHandler } = await import("./message-handler.js");

function createMessageData(authorId: string, channelId = "ch-1") {
  return {
    author: { id: authorId, bot: authorId === DEFAULT_DISCORD_BOT_USER_ID },
    message: {
      id: "msg-1",
      author: { id: authorId, bot: authorId === DEFAULT_DISCORD_BOT_USER_ID },
      content: "hello",
      channel_id: channelId,
    },
    channel_id: channelId,
  };
}

function createPreflightContext(channelId = "ch-1") {
  return createDiscordPreflightContext(channelId);
}

(deftest-group "createDiscordMessageHandler bot-self filter", () => {
  (deftest "skips bot-own messages before the debounce queue", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();

    const handler = createDiscordMessageHandler(createDiscordHandlerParams());

    await (expect* 
      handler(createMessageData(DEFAULT_DISCORD_BOT_USER_ID) as never, {} as never),
    ).resolves.toBeUndefined();

    (expect* preflightDiscordMessageMock).not.toHaveBeenCalled();
    (expect* processDiscordMessageMock).not.toHaveBeenCalled();
  });

  (deftest "enqueues non-bot messages for processing", async () => {
    preflightDiscordMessageMock.mockReset();
    processDiscordMessageMock.mockReset();
    preflightDiscordMessageMock.mockImplementation(
      async (params: { data: { channel_id: string } }) =>
        createPreflightContext(params.data.channel_id),
    );

    const handler = createDiscordMessageHandler(createDiscordHandlerParams());

    await (expect* 
      handler(createMessageData("user-456") as never, {} as never),
    ).resolves.toBeUndefined();

    await mock:waitFor(() => {
      (expect* preflightDiscordMessageMock).toHaveBeenCalledTimes(1);
      (expect* processDiscordMessageMock).toHaveBeenCalledTimes(1);
    });
  });
});
