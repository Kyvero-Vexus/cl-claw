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

import { ChannelType, type Client } from "@buape/carbon";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  __resetDiscordThreadStarterCacheForTest,
  resolveDiscordThreadStarter,
} from "./threading.js";

(deftest-group "resolveDiscordThreadStarter", () => {
  beforeEach(() => {
    __resetDiscordThreadStarterCacheForTest();
  });

  (deftest "falls back to joined embed title and description when content is empty", async () => {
    const get = mock:fn().mockResolvedValue({
      content: "   ",
      embeds: [{ title: "Alert", description: "Details" }],
      author: { username: "Alice", discriminator: "0" },
      timestamp: "2026-02-24T12:00:00.000Z",
    });
    const client = { rest: { get } } as unknown as Client;

    const result = await resolveDiscordThreadStarter({
      channel: { id: "thread-1" },
      client,
      parentId: "parent-1",
      parentType: ChannelType.GuildText,
      resolveTimestampMs: () => 123,
    });

    (expect* result).is-equal({
      text: "Alert\nDetails",
      author: "Alice",
      timestamp: 123,
    });
  });

  (deftest "prefers starter content over embed fallback text", async () => {
    const get = mock:fn().mockResolvedValue({
      content: "starter content",
      embeds: [{ title: "Alert", description: "Details" }],
      author: { username: "Alice", discriminator: "0" },
    });
    const client = { rest: { get } } as unknown as Client;

    const result = await resolveDiscordThreadStarter({
      channel: { id: "thread-1" },
      client,
      parentId: "parent-1",
      parentType: ChannelType.GuildText,
      resolveTimestampMs: () => undefined,
    });

    (expect* result?.text).is("starter content");
  });
});
