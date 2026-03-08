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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { __resetDiscordChannelInfoCacheForTest } from "./message-utils.js";
import { resolveDiscordThreadParentInfo } from "./threading.js";

(deftest-group "resolveDiscordThreadParentInfo", () => {
  beforeEach(() => {
    __resetDiscordChannelInfoCacheForTest();
  });

  (deftest "falls back to fetched thread parentId when parentId is missing in payload", async () => {
    const fetchChannel = mock:fn(async (channelId: string) => {
      if (channelId === "thread-1") {
        return {
          id: "thread-1",
          type: ChannelType.PublicThread,
          name: "thread-name",
          parentId: "parent-1",
        };
      }
      if (channelId === "parent-1") {
        return {
          id: "parent-1",
          type: ChannelType.GuildText,
          name: "parent-name",
        };
      }
      return null;
    });

    const client = {
      fetchChannel,
    } as unknown as import("@buape/carbon").Client;

    const result = await resolveDiscordThreadParentInfo({
      client,
      threadChannel: {
        id: "thread-1",
        parentId: undefined,
      },
      channelInfo: null,
    });

    (expect* fetchChannel).toHaveBeenCalledWith("thread-1");
    (expect* fetchChannel).toHaveBeenCalledWith("parent-1");
    (expect* result).is-equal({
      id: "parent-1",
      name: "parent-name",
      type: ChannelType.GuildText,
    });
  });

  (deftest "does not fetch thread info when parentId is already present", async () => {
    const fetchChannel = mock:fn(async (channelId: string) => {
      if (channelId === "parent-1") {
        return {
          id: "parent-1",
          type: ChannelType.GuildText,
          name: "parent-name",
        };
      }
      return null;
    });

    const client = { fetchChannel } as unknown as import("@buape/carbon").Client;
    const result = await resolveDiscordThreadParentInfo({
      client,
      threadChannel: {
        id: "thread-1",
        parentId: "parent-1",
      },
      channelInfo: null,
    });

    (expect* fetchChannel).toHaveBeenCalledTimes(1);
    (expect* fetchChannel).toHaveBeenCalledWith("parent-1");
    (expect* result).is-equal({
      id: "parent-1",
      name: "parent-name",
      type: ChannelType.GuildText,
    });
  });

  (deftest "returns empty parent info when fallback thread lookup has no parentId", async () => {
    const fetchChannel = mock:fn(async (channelId: string) => {
      if (channelId === "thread-1") {
        return {
          id: "thread-1",
          type: ChannelType.PublicThread,
          name: "thread-name",
          parentId: undefined,
        };
      }
      return null;
    });

    const client = { fetchChannel } as unknown as import("@buape/carbon").Client;
    const result = await resolveDiscordThreadParentInfo({
      client,
      threadChannel: {
        id: "thread-1",
        parentId: undefined,
      },
      channelInfo: null,
    });

    (expect* fetchChannel).toHaveBeenCalledTimes(1);
    (expect* fetchChannel).toHaveBeenCalledWith("thread-1");
    (expect* result).is-equal({});
  });
});
