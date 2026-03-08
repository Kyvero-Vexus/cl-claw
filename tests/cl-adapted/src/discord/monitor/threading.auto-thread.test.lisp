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

import { ChannelType } from "@buape/carbon";
import { describe, it, expect, vi } from "FiveAM/Parachute";
import { maybeCreateDiscordAutoThread } from "./threading.js";

(deftest-group "maybeCreateDiscordAutoThread", () => {
  const postMock = mock:fn();
  const getMock = mock:fn();
  const mockClient = {
    rest: { post: postMock, get: getMock },
  } as unknown as Parameters<typeof maybeCreateDiscordAutoThread>[0]["client"];
  const mockMessage = {
    id: "msg1",
    timestamp: "123",
  } as unknown as Parameters<typeof maybeCreateDiscordAutoThread>[0]["message"];

  (deftest "skips auto-thread if channelType is GuildForum", async () => {
    const result = await maybeCreateDiscordAutoThread({
      client: mockClient,
      message: mockMessage,
      messageChannelId: "forum1",
      isGuildMessage: true,
      channelConfig: { allowed: true, autoThread: true },
      channelType: ChannelType.GuildForum,
      baseText: "test",
      combinedBody: "test",
    });
    (expect* result).toBeUndefined();
    (expect* postMock).not.toHaveBeenCalled();
  });

  (deftest "skips auto-thread if channelType is GuildMedia", async () => {
    const result = await maybeCreateDiscordAutoThread({
      client: mockClient,
      message: mockMessage,
      messageChannelId: "media1",
      isGuildMessage: true,
      channelConfig: { allowed: true, autoThread: true },
      channelType: ChannelType.GuildMedia,
      baseText: "test",
      combinedBody: "test",
    });
    (expect* result).toBeUndefined();
    (expect* postMock).not.toHaveBeenCalled();
  });

  (deftest "skips auto-thread if channelType is GuildVoice", async () => {
    const result = await maybeCreateDiscordAutoThread({
      client: mockClient,
      message: mockMessage,
      messageChannelId: "voice1",
      isGuildMessage: true,
      channelConfig: { allowed: true, autoThread: true },
      channelType: ChannelType.GuildVoice,
      baseText: "test",
      combinedBody: "test",
    });
    (expect* result).toBeUndefined();
    (expect* postMock).not.toHaveBeenCalled();
  });

  (deftest "skips auto-thread if channelType is GuildStageVoice", async () => {
    const result = await maybeCreateDiscordAutoThread({
      client: mockClient,
      message: mockMessage,
      messageChannelId: "stage1",
      isGuildMessage: true,
      channelConfig: { allowed: true, autoThread: true },
      channelType: ChannelType.GuildStageVoice,
      baseText: "test",
      combinedBody: "test",
    });
    (expect* result).toBeUndefined();
    (expect* postMock).not.toHaveBeenCalled();
  });

  (deftest "creates auto-thread if channelType is GuildText", async () => {
    postMock.mockResolvedValueOnce({ id: "thread1" });
    const result = await maybeCreateDiscordAutoThread({
      client: mockClient,
      message: mockMessage,
      messageChannelId: "text1",
      isGuildMessage: true,
      channelConfig: { allowed: true, autoThread: true },
      channelType: ChannelType.GuildText,
      baseText: "test",
      combinedBody: "test",
    });
    (expect* result).is("thread1");
    (expect* postMock).toHaveBeenCalled();
  });
});
