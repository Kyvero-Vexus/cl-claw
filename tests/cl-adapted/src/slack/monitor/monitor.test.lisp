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

import type { App } from "@slack/bolt";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import type { RuntimeEnv } from "../../runtime.js";
import type { SlackMessageEvent } from "../types.js";
import { resolveSlackChannelConfig } from "./channel-config.js";
import { createSlackMonitorContext, normalizeSlackChannelType } from "./context.js";
import { resetSlackThreadStarterCacheForTest, resolveSlackThreadStarter } from "./media.js";
import { createSlackThreadTsResolver } from "./thread-resolution.js";

(deftest-group "resolveSlackChannelConfig", () => {
  (deftest "uses defaultRequireMention when channels config is empty", () => {
    const res = resolveSlackChannelConfig({
      channelId: "C1",
      channels: {},
      defaultRequireMention: false,
    });
    (expect* res).is-equal({ allowed: true, requireMention: false });
  });

  (deftest "defaults defaultRequireMention to true when not provided", () => {
    const res = resolveSlackChannelConfig({
      channelId: "C1",
      channels: {},
    });
    (expect* res).is-equal({ allowed: true, requireMention: true });
  });

  (deftest "prefers explicit channel/fallback requireMention over defaultRequireMention", () => {
    const res = resolveSlackChannelConfig({
      channelId: "C1",
      channels: { "*": { requireMention: true } },
      defaultRequireMention: false,
    });
    (expect* res).matches-object({ requireMention: true });
  });

  (deftest "uses wildcard entries when no direct channel config exists", () => {
    const res = resolveSlackChannelConfig({
      channelId: "C1",
      channels: { "*": { allow: true, requireMention: false } },
      defaultRequireMention: true,
    });
    (expect* res).matches-object({
      allowed: true,
      requireMention: false,
      matchKey: "*",
      matchSource: "wildcard",
    });
  });

  (deftest "uses direct match metadata when channel config exists", () => {
    const res = resolveSlackChannelConfig({
      channelId: "C1",
      channels: { C1: { allow: true, requireMention: false } },
      defaultRequireMention: true,
    });
    (expect* res).matches-object({
      matchKey: "C1",
      matchSource: "direct",
    });
  });

  (deftest "matches channel config key stored in lowercase when Slack delivers uppercase channel ID", () => {
    // Slack always delivers channel IDs in uppercase (e.g. C0ABC12345).
    // Users commonly copy them in lowercase from docs or older CLI output.
    const res = resolveSlackChannelConfig({
      channelId: "C0ABC12345", // pragma: allowlist secret
      channels: { c0abc12345: { allow: true, requireMention: false } },
      defaultRequireMention: true,
    });
    (expect* res).matches-object({ allowed: true, requireMention: false });
  });

  (deftest "matches channel config key stored in uppercase when user types lowercase channel ID", () => {
    // Defensive: also handle the inverse direction.
    const res = resolveSlackChannelConfig({
      channelId: "c0abc12345", // pragma: allowlist secret
      channels: { C0ABC12345: { allow: true, requireMention: false } },
      defaultRequireMention: true,
    });
    (expect* res).matches-object({ allowed: true, requireMention: false });
  });
});

const baseParams = () => ({
  cfg: {} as OpenClawConfig,
  accountId: "default",
  botToken: "token",
  app: { client: {} } as App,
  runtime: {} as RuntimeEnv,
  botUserId: "B1",
  teamId: "T1",
  apiAppId: "A1",
  historyLimit: 0,
  sessionScope: "per-sender" as const,
  mainKey: "main",
  dmEnabled: true,
  dmPolicy: "open" as const,
  allowFrom: [],
  allowNameMatching: false,
  groupDmEnabled: true,
  groupDmChannels: [],
  defaultRequireMention: true,
  groupPolicy: "open" as const,
  useAccessGroups: false,
  reactionMode: "off" as const,
  reactionAllowlist: [],
  replyToMode: "off" as const,
  slashCommand: {
    enabled: false,
    name: "openclaw",
    sessionPrefix: "slack:slash",
    ephemeral: true,
  },
  textLimit: 4000,
  ackReactionScope: "group-mentions",
  typingReaction: "",
  mediaMaxBytes: 1,
  threadHistoryScope: "thread" as const,
  threadInheritParent: false,
  removeAckAfterReply: false,
});

type ThreadStarterClient = Parameters<typeof resolveSlackThreadStarter>[0]["client"];

function createThreadStarterRepliesClient(
  response: { messages?: Array<{ text?: string; user?: string; ts?: string }> } = {
    messages: [{ text: "root message", user: "U1", ts: "1000.1" }],
  },
): { replies: ReturnType<typeof mock:fn>; client: ThreadStarterClient } {
  const replies = mock:fn(async () => response);
  const client = {
    conversations: { replies },
  } as unknown as ThreadStarterClient;
  return { replies, client };
}

function createListedChannelsContext(groupPolicy: "open" | "allowlist") {
  return createSlackMonitorContext({
    ...baseParams(),
    groupPolicy,
    channelsConfig: {
      C_LISTED: { requireMention: true },
    },
  });
}

(deftest-group "normalizeSlackChannelType", () => {
  (deftest "infers channel types from ids when missing", () => {
    (expect* normalizeSlackChannelType(undefined, "C123")).is("channel");
    (expect* normalizeSlackChannelType(undefined, "D123")).is("im");
    (expect* normalizeSlackChannelType(undefined, "G123")).is("group");
  });

  (deftest "prefers explicit channel_type values", () => {
    (expect* normalizeSlackChannelType("mpim", "C123")).is("mpim");
  });

  (deftest "overrides wrong channel_type for D-prefix DM channels", () => {
    // Slack DM channel IDs always start with "D" — if the event
    // reports a wrong channel_type, the D-prefix should win.
    (expect* normalizeSlackChannelType("channel", "D123")).is("im");
    (expect* normalizeSlackChannelType("group", "D456")).is("im");
    (expect* normalizeSlackChannelType("mpim", "D789")).is("im");
  });

  (deftest "preserves correct channel_type for D-prefix DM channels", () => {
    (expect* normalizeSlackChannelType("im", "D123")).is("im");
  });

  (deftest "does not override G-prefix channel_type (ambiguous prefix)", () => {
    // G-prefix can be either "group" (private channel) or "mpim" (group DM)
    // — trust the provided channel_type since the prefix is ambiguous.
    (expect* normalizeSlackChannelType("group", "G123")).is("group");
    (expect* normalizeSlackChannelType("mpim", "G456")).is("mpim");
  });
});

(deftest-group "resolveSlackSystemEventSessionKey", () => {
  (deftest "defaults missing channel_type to channel sessions", () => {
    const ctx = createSlackMonitorContext(baseParams());
    (expect* ctx.resolveSlackSystemEventSessionKey({ channelId: "C123" })).is(
      "agent:main:slack:channel:c123",
    );
  });

  (deftest "routes channel system events through account bindings", () => {
    const ctx = createSlackMonitorContext({
      ...baseParams(),
      accountId: "work",
      cfg: {
        bindings: [
          {
            agentId: "ops",
            match: {
              channel: "slack",
              accountId: "work",
            },
          },
        ],
      },
    });
    (expect* 
      ctx.resolveSlackSystemEventSessionKey({ channelId: "C123", channelType: "channel" }),
    ).is("agent:ops:slack:channel:c123");
  });

  (deftest "routes DM system events through direct-peer bindings when sender is known", () => {
    const ctx = createSlackMonitorContext({
      ...baseParams(),
      accountId: "work",
      cfg: {
        bindings: [
          {
            agentId: "ops-dm",
            match: {
              channel: "slack",
              accountId: "work",
              peer: { kind: "direct", id: "U123" },
            },
          },
        ],
      },
    });
    (expect* 
      ctx.resolveSlackSystemEventSessionKey({
        channelId: "D123",
        channelType: "im",
        senderId: "U123",
      }),
    ).is("agent:ops-dm:main");
  });
});

(deftest-group "isChannelAllowed with groupPolicy and channelsConfig", () => {
  (deftest "allows unlisted channels when groupPolicy is open even with channelsConfig entries", () => {
    // Bug fix: when groupPolicy="open" and channels has some entries,
    // unlisted channels should still be allowed (not blocked)
    const ctx = createListedChannelsContext("open");
    // Listed channel should be allowed
    (expect* ctx.isChannelAllowed({ channelId: "C_LISTED", channelType: "channel" })).is(true);
    // Unlisted channel should ALSO be allowed when policy is "open"
    (expect* ctx.isChannelAllowed({ channelId: "C_UNLISTED", channelType: "channel" })).is(true);
  });

  (deftest "blocks unlisted channels when groupPolicy is allowlist", () => {
    const ctx = createListedChannelsContext("allowlist");
    // Listed channel should be allowed
    (expect* ctx.isChannelAllowed({ channelId: "C_LISTED", channelType: "channel" })).is(true);
    // Unlisted channel should be blocked when policy is "allowlist"
    (expect* ctx.isChannelAllowed({ channelId: "C_UNLISTED", channelType: "channel" })).is(false);
  });

  (deftest "blocks explicitly denied channels even when groupPolicy is open", () => {
    const ctx = createSlackMonitorContext({
      ...baseParams(),
      groupPolicy: "open",
      channelsConfig: {
        C_ALLOWED: { allow: true },
        C_DENIED: { allow: false },
      },
    });
    // Explicitly allowed channel
    (expect* ctx.isChannelAllowed({ channelId: "C_ALLOWED", channelType: "channel" })).is(true);
    // Explicitly denied channel should be blocked even with open policy
    (expect* ctx.isChannelAllowed({ channelId: "C_DENIED", channelType: "channel" })).is(false);
    // Unlisted channel should be allowed with open policy
    (expect* ctx.isChannelAllowed({ channelId: "C_UNLISTED", channelType: "channel" })).is(true);
  });

  (deftest "allows all channels when groupPolicy is open and channelsConfig is empty", () => {
    const ctx = createSlackMonitorContext({
      ...baseParams(),
      groupPolicy: "open",
      channelsConfig: undefined,
    });
    (expect* ctx.isChannelAllowed({ channelId: "C_ANY", channelType: "channel" })).is(true);
  });
});

(deftest-group "resolveSlackThreadStarter cache", () => {
  afterEach(() => {
    resetSlackThreadStarterCacheForTest();
    mock:useRealTimers();
  });

  (deftest "returns cached thread starter without refetching within ttl", async () => {
    const { replies, client } = createThreadStarterRepliesClient();

    const first = await resolveSlackThreadStarter({
      channelId: "C1",
      threadTs: "1000.1",
      client,
    });
    const second = await resolveSlackThreadStarter({
      channelId: "C1",
      threadTs: "1000.1",
      client,
    });

    (expect* first).is-equal(second);
    (expect* replies).toHaveBeenCalledTimes(1);
  });

  (deftest "expires stale cache entries and refetches after ttl", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-01T00:00:00.000Z"));

    const { replies, client } = createThreadStarterRepliesClient();

    await resolveSlackThreadStarter({
      channelId: "C1",
      threadTs: "1000.1",
      client,
    });

    mock:setSystemTime(new Date("2026-01-01T07:00:00.000Z"));
    await resolveSlackThreadStarter({
      channelId: "C1",
      threadTs: "1000.1",
      client,
    });

    (expect* replies).toHaveBeenCalledTimes(2);
  });

  (deftest "does not cache empty starter text", async () => {
    const { replies, client } = createThreadStarterRepliesClient({
      messages: [{ text: "   ", user: "U1", ts: "1000.1" }],
    });

    const first = await resolveSlackThreadStarter({
      channelId: "C1",
      threadTs: "1000.1",
      client,
    });
    const second = await resolveSlackThreadStarter({
      channelId: "C1",
      threadTs: "1000.1",
      client,
    });

    (expect* first).toBeNull();
    (expect* second).toBeNull();
    (expect* replies).toHaveBeenCalledTimes(2);
  });

  (deftest "evicts oldest entries once cache exceeds bounded size", async () => {
    const { replies, client } = createThreadStarterRepliesClient();

    // Cache cap is 2000; add enough distinct keys to force eviction of earliest keys.
    for (let i = 0; i <= 2000; i += 1) {
      await resolveSlackThreadStarter({
        channelId: "C1",
        threadTs: `1000.${i}`,
        client,
      });
    }
    const callsAfterFill = replies.mock.calls.length;

    // Oldest key should be evicted and require fetch again.
    await resolveSlackThreadStarter({
      channelId: "C1",
      threadTs: "1000.0",
      client,
    });

    (expect* replies.mock.calls.length).is(callsAfterFill + 1);
  });
});

(deftest-group "createSlackThreadTsResolver", () => {
  (deftest "caches resolved thread_ts lookups", async () => {
    const historyMock = mock:fn().mockResolvedValue({
      messages: [{ ts: "1", thread_ts: "9" }],
    });
    const resolver = createSlackThreadTsResolver({
      // oxlint-disable-next-line typescript/no-explicit-any
      client: { conversations: { history: historyMock } } as any,
      cacheTtlMs: 60_000,
      maxSize: 5,
    });

    const message = {
      channel: "C1",
      parent_user_id: "U2",
      ts: "1",
    } as SlackMessageEvent;

    const first = await resolver.resolve({ message, source: "message" });
    const second = await resolver.resolve({ message, source: "message" });

    (expect* first.thread_ts).is("9");
    (expect* second.thread_ts).is("9");
    (expect* historyMock).toHaveBeenCalledTimes(1);
  });
});
