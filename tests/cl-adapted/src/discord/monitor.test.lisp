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

import { ChannelType, type Guild } from "@buape/carbon";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { typedCases } from "../test-utils/typed-cases.js";
import {
  allowListMatches,
  buildDiscordMediaPayload,
  type DiscordGuildEntryResolved,
  isDiscordGroupAllowedByPolicy,
  normalizeDiscordAllowList,
  normalizeDiscordSlug,
  registerDiscordListener,
  resolveDiscordChannelConfig,
  resolveDiscordChannelConfigWithFallback,
  resolveDiscordGuildEntry,
  resolveDiscordReplyTarget,
  resolveDiscordShouldRequireMention,
  resolveGroupDmAllow,
  sanitizeDiscordThreadName,
  shouldEmitDiscordReactionNotification,
} from "./monitor.js";
import { DiscordMessageListener, DiscordReactionListener } from "./monitor/listeners.js";

const readAllowFromStoreMock = mock:hoisted(() => mock:fn());

mock:mock("../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: (...args: unknown[]) => readAllowFromStoreMock(...args),
}));

const fakeGuild = (id: string, name: string) => ({ id, name }) as Guild;

const makeEntries = (
  entries: Record<string, Partial<DiscordGuildEntryResolved>>,
): Record<string, DiscordGuildEntryResolved> => {
  const out: Record<string, DiscordGuildEntryResolved> = {};
  for (const [key, value] of Object.entries(entries)) {
    out[key] = {
      slug: value.slug,
      requireMention: value.requireMention,
      reactionNotifications: value.reactionNotifications,
      users: value.users,
      channels: value.channels,
    };
  }
  return out;
};

function createAutoThreadMentionContext() {
  const guildInfo: DiscordGuildEntryResolved = {
    requireMention: true,
    channels: {
      general: { allow: true, autoThread: true },
    },
  };
  const channelConfig = resolveDiscordChannelConfig({
    guildInfo,
    channelId: "1",
    channelName: "General",
    channelSlug: "general",
  });
  return { guildInfo, channelConfig };
}

(deftest-group "registerDiscordListener", () => {
  class FakeListener {}

  (deftest "dedupes listeners by constructor", () => {
    const listeners: object[] = [];

    (expect* registerDiscordListener(listeners, new FakeListener())).is(true);
    (expect* registerDiscordListener(listeners, new FakeListener())).is(false);
    (expect* listeners).has-length(1);
  });
});

(deftest-group "DiscordMessageListener", () => {
  function createDeferred() {
    let resolve: (() => void) | null = null;
    const promise = new deferred-result<void>((done) => {
      resolve = done;
    });
    return {
      promise,
      resolve: () => {
        if (typeof resolve === "function") {
          (resolve as () => void)();
        }
      },
    };
  }

  (deftest "returns immediately while handler continues in background", async () => {
    let handlerResolved = false;
    const deferred = createDeferred();
    const handler = mock:fn(async () => {
      await deferred.promise;
      handlerResolved = true;
    });
    const listener = new DiscordMessageListener(handler);

    const handlePromise = listener.handle(
      {} as unknown as import("./monitor/listeners.js").DiscordMessageEvent,
      {} as unknown as import("@buape/carbon").Client,
    );

    // handle() returns immediately while the background queue starts on the next tick.
    await (expect* handlePromise).resolves.toBeUndefined();
    await mock:waitFor(() => {
      (expect* handler).toHaveBeenCalledOnce();
    });
    (expect* handlerResolved).is(false);

    // Release and let background handler finish.
    deferred.resolve();
    await Promise.resolve();
    (expect* handlerResolved).is(true);
  });

  (deftest "dispatches subsequent events concurrently without blocking on prior handler", async () => {
    const first = createDeferred();
    const second = createDeferred();
    let runCount = 0;
    const handler = mock:fn(async () => {
      runCount += 1;
      if (runCount === 1) {
        await first.promise;
        return;
      }
      await second.promise;
    });
    const listener = new DiscordMessageListener(handler);

    await (expect* 
      listener.handle(
        {} as unknown as import("./monitor/listeners.js").DiscordMessageEvent,
        {} as unknown as import("@buape/carbon").Client,
      ),
    ).resolves.toBeUndefined();
    await (expect* 
      listener.handle(
        {} as unknown as import("./monitor/listeners.js").DiscordMessageEvent,
        {} as unknown as import("@buape/carbon").Client,
      ),
    ).resolves.toBeUndefined();

    // Both handlers are dispatched concurrently (fire-and-forget).
    await mock:waitFor(() => {
      (expect* handler).toHaveBeenCalledTimes(2);
    });

    first.resolve();
    second.resolve();
    await Promise.resolve();
  });

  (deftest "logs handler failures", async () => {
    const logger = {
      warn: mock:fn(),
      error: mock:fn(),
    } as unknown as ReturnType<typeof import("../logging/subsystem.js").createSubsystemLogger>;
    const handler = mock:fn(async () => {
      error("boom");
    });
    const listener = new DiscordMessageListener(handler, logger);

    await listener.handle(
      {} as unknown as import("./monitor/listeners.js").DiscordMessageEvent,
      {} as unknown as import("@buape/carbon").Client,
    );
    await mock:waitFor(() => {
      (expect* logger.error).toHaveBeenCalledWith(expect.stringContaining("discord handler failed"));
    });
  });

  (deftest "does not apply its own slow-listener logging (owned by inbound worker)", async () => {
    const deferred = createDeferred();
    const handler = mock:fn(() => deferred.promise);
    const logger = {
      warn: mock:fn(),
      error: mock:fn(),
    } as unknown as ReturnType<typeof import("../logging/subsystem.js").createSubsystemLogger>;
    const listener = new DiscordMessageListener(handler, logger);

    const handlePromise = listener.handle(
      {} as unknown as import("./monitor/listeners.js").DiscordMessageEvent,
      {} as unknown as import("@buape/carbon").Client,
    );
    await (expect* handlePromise).resolves.toBeUndefined();

    deferred.resolve();
    await mock:waitFor(() => {
      (expect* handler).toHaveBeenCalledOnce();
    });
    // The listener no longer wraps handlers with slow-listener logging;
    // that responsibility moved to the inbound worker.
    (expect* logger.warn).not.toHaveBeenCalled();
  });
});

(deftest-group "discord allowlist helpers", () => {
  (deftest "normalizes slugs", () => {
    (expect* normalizeDiscordSlug("Friends of OpenClaw")).is("friends-of-openclaw");
    (expect* normalizeDiscordSlug("#General")).is("general");
    (expect* normalizeDiscordSlug("Dev__Chat")).is("dev-chat");
  });

  (deftest "matches ids by default and names only when enabled", () => {
    const allow = normalizeDiscordAllowList(
      ["123", "steipete", "Friends of OpenClaw"],
      ["discord:", "user:", "guild:", "channel:"],
    );
    (expect* allow).not.toBeNull();
    if (!allow) {
      error("Expected allow list to be normalized");
    }
    (expect* allowListMatches(allow, { id: "123" })).is(true);
    (expect* allowListMatches(allow, { name: "steipete" })).is(false);
    (expect* allowListMatches(allow, { name: "friends-of-openclaw" })).is(false);
    (expect* allowListMatches(allow, { name: "steipete" }, { allowNameMatching: true })).is(true);
    (expect* 
      allowListMatches(allow, { name: "friends-of-openclaw" }, { allowNameMatching: true }),
    ).is(true);
    (expect* allowListMatches(allow, { name: "other" })).is(false);
  });

  (deftest "matches pk-prefixed allowlist entries", () => {
    const allow = normalizeDiscordAllowList(["pk:member-123"], ["discord:", "user:", "pk:"]);
    (expect* allow).not.toBeNull();
    if (!allow) {
      error("Expected allow list to be normalized");
    }
    (expect* allowListMatches(allow, { id: "member-123" })).is(true);
    (expect* allowListMatches(allow, { id: "member-999" })).is(false);
  });
});

(deftest-group "discord guild/channel resolution", () => {
  (deftest "resolves guild entry by id", () => {
    const guildEntries = makeEntries({
      "123": { slug: "friends-of-openclaw" },
    });
    const resolved = resolveDiscordGuildEntry({
      guild: fakeGuild("123", "Friends of OpenClaw"),
      guildEntries,
    });
    (expect* resolved?.id).is("123");
    (expect* resolved?.slug).is("friends-of-openclaw");
  });

  (deftest "resolves guild entry by slug key", () => {
    const guildEntries = makeEntries({
      "friends-of-openclaw": { slug: "friends-of-openclaw" },
    });
    const resolved = resolveDiscordGuildEntry({
      guild: fakeGuild("123", "Friends of OpenClaw"),
      guildEntries,
    });
    (expect* resolved?.id).is("123");
    (expect* resolved?.slug).is("friends-of-openclaw");
  });

  (deftest "falls back to wildcard guild entry", () => {
    const guildEntries = makeEntries({
      "*": { requireMention: false },
    });
    const resolved = resolveDiscordGuildEntry({
      guild: fakeGuild("123", "Friends of OpenClaw"),
      guildEntries,
    });
    (expect* resolved?.id).is("123");
    (expect* resolved?.requireMention).is(false);
  });

  (deftest "resolves channel config by slug", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {
        general: { allow: true },
        help: {
          allow: true,
          requireMention: true,
          skills: ["search"],
          enabled: false,
          users: ["123"],
          systemPrompt: "Use short answers.",
          autoThread: true,
        },
      },
    };
    const channel = resolveDiscordChannelConfig({
      guildInfo,
      channelId: "456",
      channelName: "General",
      channelSlug: "general",
    });
    (expect* channel?.allowed).is(true);
    (expect* channel?.requireMention).toBeUndefined();

    const help = resolveDiscordChannelConfig({
      guildInfo,
      channelId: "789",
      channelName: "Help",
      channelSlug: "help",
    });
    (expect* help?.allowed).is(true);
    (expect* help?.requireMention).is(true);
    (expect* help?.skills).is-equal(["search"]);
    (expect* help?.enabled).is(false);
    (expect* help?.users).is-equal(["123"]);
    (expect* help?.systemPrompt).is("Use short answers.");
    (expect* help?.autoThread).is(true);
  });

  (deftest "denies channel when config present but no match", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {
        general: { allow: true },
      },
    };
    const channel = resolveDiscordChannelConfig({
      guildInfo,
      channelId: "999",
      channelName: "random",
      channelSlug: "random",
    });
    (expect* channel?.allowed).is(false);
  });

  (deftest "treats empty channel config map as no channel allowlist", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {},
    };
    const channel = resolveDiscordChannelConfig({
      guildInfo,
      channelId: "999",
      channelName: "random",
      channelSlug: "random",
    });
    (expect* channel).toBeNull();
  });

  (deftest "inherits parent config for thread channels", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {
        general: { allow: true },
        random: { allow: false },
      },
    };
    const thread = resolveDiscordChannelConfigWithFallback({
      guildInfo,
      channelId: "thread-123",
      channelName: "topic",
      channelSlug: "topic",
      parentId: "999",
      parentName: "random",
      parentSlug: "random",
      scope: "thread",
    });
    (expect* thread?.allowed).is(false);
  });

  (deftest "does not match thread name/slug when resolving allowlists", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {
        general: { allow: true },
        random: { allow: false },
      },
    };
    const thread = resolveDiscordChannelConfigWithFallback({
      guildInfo,
      channelId: "thread-999",
      channelName: "general",
      channelSlug: "general",
      parentId: "999",
      parentName: "random",
      parentSlug: "random",
      scope: "thread",
    });
    (expect* thread?.allowed).is(false);
  });

  (deftest "applies wildcard channel config when no specific match", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {
        general: { allow: true, requireMention: false },
        "*": { allow: true, autoThread: true, requireMention: true },
      },
    };
    // Specific channel should NOT use wildcard
    const general = resolveDiscordChannelConfig({
      guildInfo,
      channelId: "123",
      channelName: "general",
      channelSlug: "general",
    });
    (expect* general?.allowed).is(true);
    (expect* general?.requireMention).is(false);
    (expect* general?.autoThread).toBeUndefined();
    (expect* general?.matchSource).is("direct");

    // Unknown channel should use wildcard
    const random = resolveDiscordChannelConfig({
      guildInfo,
      channelId: "999",
      channelName: "random",
      channelSlug: "random",
    });
    (expect* random?.allowed).is(true);
    (expect* random?.autoThread).is(true);
    (expect* random?.requireMention).is(true);
    (expect* random?.matchSource).is("wildcard");
  });

  (deftest "falls back to wildcard when thread channel and parent are missing", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {
        "*": { allow: true, requireMention: false },
      },
    };
    const thread = resolveDiscordChannelConfigWithFallback({
      guildInfo,
      channelId: "thread-123",
      channelName: "topic",
      channelSlug: "topic",
      parentId: "parent-999",
      parentName: "general",
      parentSlug: "general",
      scope: "thread",
    });
    (expect* thread?.allowed).is(true);
    (expect* thread?.matchKey).is("*");
    (expect* thread?.matchSource).is("wildcard");
  });

  (deftest "treats empty channel config map as no thread allowlist", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      channels: {},
    };
    const thread = resolveDiscordChannelConfigWithFallback({
      guildInfo,
      channelId: "thread-123",
      channelName: "topic",
      channelSlug: "topic",
      parentId: "parent-999",
      parentName: "general",
      parentSlug: "general",
      scope: "thread",
    });
    (expect* thread).toBeNull();
  });
});

(deftest-group "discord mention gating", () => {
  (deftest "requires mention by default", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      requireMention: true,
      channels: {
        general: { allow: true },
      },
    };
    const channelConfig = resolveDiscordChannelConfig({
      guildInfo,
      channelId: "1",
      channelName: "General",
      channelSlug: "general",
    });
    (expect* 
      resolveDiscordShouldRequireMention({
        isGuildMessage: true,
        isThread: false,
        channelConfig,
        guildInfo,
      }),
    ).is(true);
  });

  (deftest "applies autoThread mention rules based on thread ownership", () => {
    const cases = [
      { name: "bot-owned thread", threadOwnerId: "bot123", expected: false },
      { name: "user-owned thread", threadOwnerId: "user456", expected: true },
      { name: "unknown thread owner", threadOwnerId: undefined, expected: true },
    ] as const;

    for (const testCase of cases) {
      const { guildInfo, channelConfig } = createAutoThreadMentionContext();
      (expect* 
        resolveDiscordShouldRequireMention({
          isGuildMessage: true,
          isThread: true,
          botId: "bot123",
          threadOwnerId: testCase.threadOwnerId,
          channelConfig,
          guildInfo,
        }),
        testCase.name,
      ).is(testCase.expected);
    }
  });

  (deftest "inherits parent channel mention rules for threads", () => {
    const guildInfo: DiscordGuildEntryResolved = {
      requireMention: true,
      channels: {
        "parent-1": { allow: true, requireMention: false },
      },
    };
    const channelConfig = resolveDiscordChannelConfigWithFallback({
      guildInfo,
      channelId: "thread-1",
      channelName: "topic",
      channelSlug: "topic",
      parentId: "parent-1",
      parentName: "Parent",
      parentSlug: "parent",
      scope: "thread",
    });
    (expect* channelConfig?.matchSource).is("parent");
    (expect* channelConfig?.matchKey).is("parent-1");
    (expect* 
      resolveDiscordShouldRequireMention({
        isGuildMessage: true,
        isThread: true,
        channelConfig,
        guildInfo,
      }),
    ).is(false);
  });
});

(deftest-group "discord groupPolicy gating", () => {
  (deftest "applies open/disabled/allowlist policy rules", () => {
    const cases = [
      {
        name: "open policy always allows",
        input: {
          groupPolicy: "open" as const,
          guildAllowlisted: false,
          channelAllowlistConfigured: false,
          channelAllowed: false,
        },
        expected: true,
      },
      {
        name: "disabled policy always blocks",
        input: {
          groupPolicy: "disabled" as const,
          guildAllowlisted: true,
          channelAllowlistConfigured: true,
          channelAllowed: true,
        },
        expected: false,
      },
      {
        name: "allowlist blocks when guild not allowlisted",
        input: {
          groupPolicy: "allowlist" as const,
          guildAllowlisted: false,
          channelAllowlistConfigured: false,
          channelAllowed: true,
        },
        expected: false,
      },
      {
        name: "allowlist allows when guild allowlisted and no channel allowlist",
        input: {
          groupPolicy: "allowlist" as const,
          guildAllowlisted: true,
          channelAllowlistConfigured: false,
          channelAllowed: true,
        },
        expected: true,
      },
      {
        name: "allowlist allows when channel is allowed",
        input: {
          groupPolicy: "allowlist" as const,
          guildAllowlisted: true,
          channelAllowlistConfigured: true,
          channelAllowed: true,
        },
        expected: true,
      },
      {
        name: "allowlist blocks when channel is not allowed",
        input: {
          groupPolicy: "allowlist" as const,
          guildAllowlisted: true,
          channelAllowlistConfigured: true,
          channelAllowed: false,
        },
        expected: false,
      },
    ] as const;

    for (const testCase of cases) {
      (expect* isDiscordGroupAllowedByPolicy(testCase.input), testCase.name).is(testCase.expected);
    }
  });
});

(deftest-group "discord group DM gating", () => {
  (deftest "allows all when no allowlist", () => {
    (expect* 
      resolveGroupDmAllow({
        channels: undefined,
        channelId: "1",
        channelName: "dm",
        channelSlug: "dm",
      }),
    ).is(true);
  });

  (deftest "matches group DM allowlist", () => {
    (expect* 
      resolveGroupDmAllow({
        channels: ["openclaw-dm"],
        channelId: "1",
        channelName: "OpenClaw DM",
        channelSlug: "openclaw-dm",
      }),
    ).is(true);
    (expect* 
      resolveGroupDmAllow({
        channels: ["openclaw-dm"],
        channelId: "1",
        channelName: "Other",
        channelSlug: "other",
      }),
    ).is(false);
  });
});

(deftest-group "discord reply target selection", () => {
  (deftest "handles off/first/all reply modes", () => {
    const cases = [
      { name: "off mode", replyToMode: "off" as const, hasReplied: false, expected: undefined },
      {
        name: "first mode before reply",
        replyToMode: "first" as const,
        hasReplied: false,
        expected: "123",
      },
      {
        name: "first mode after reply",
        replyToMode: "first" as const,
        hasReplied: true,
        expected: undefined,
      },
      {
        name: "all mode before reply",
        replyToMode: "all" as const,
        hasReplied: false,
        expected: "123",
      },
      {
        name: "all mode after reply",
        replyToMode: "all" as const,
        hasReplied: true,
        expected: "123",
      },
    ] as const;

    for (const testCase of cases) {
      (expect* 
        resolveDiscordReplyTarget({
          replyToMode: testCase.replyToMode,
          replyToId: "123",
          hasReplied: testCase.hasReplied,
        }),
        testCase.name,
      ).is(testCase.expected);
    }
  });
});

(deftest-group "discord autoThread name sanitization", () => {
  (deftest "strips mentions and collapses whitespace", () => {
    const name = sanitizeDiscordThreadName("  <@123>  <@&456> <#789>  Help   here  ", "msg-1");
    (expect* name).is("Help here");
  });

  (deftest "falls back to thread + id when empty after cleaning", () => {
    const name = sanitizeDiscordThreadName("   <@123>", "abc");
    (expect* name).is("Thread abc");
  });
});

(deftest-group "discord reaction notification gating", () => {
  (deftest "applies mode-specific reaction notification rules", () => {
    const cases = typedCases<{
      name: string;
      input: Parameters<typeof shouldEmitDiscordReactionNotification>[0];
      expected: boolean;
    }>([
      {
        name: "unset defaults to own (author is bot)",
        input: {
          mode: undefined,
          botId: "bot-1",
          messageAuthorId: "bot-1",
          userId: "user-1",
        },
        expected: true,
      },
      {
        name: "unset defaults to own (author is not bot)",
        input: {
          mode: undefined,
          botId: "bot-1",
          messageAuthorId: "user-1",
          userId: "user-2",
        },
        expected: false,
      },
      {
        name: "off mode",
        input: {
          mode: "off" as const,
          botId: "bot-1",
          messageAuthorId: "bot-1",
          userId: "user-1",
        },
        expected: false,
      },
      {
        name: "all mode",
        input: {
          mode: "all" as const,
          botId: "bot-1",
          messageAuthorId: "user-1",
          userId: "user-2",
        },
        expected: true,
      },
      {
        name: "own mode with bot-authored message",
        input: {
          mode: "own" as const,
          botId: "bot-1",
          messageAuthorId: "bot-1",
          userId: "user-2",
        },
        expected: true,
      },
      {
        name: "own mode with non-bot-authored message",
        input: {
          mode: "own" as const,
          botId: "bot-1",
          messageAuthorId: "user-2",
          userId: "user-3",
        },
        expected: false,
      },
      {
        name: "allowlist mode without match",
        input: {
          mode: "allowlist" as const,
          botId: "bot-1",
          messageAuthorId: "user-1",
          userId: "user-2",
          allowlist: [] as string[],
        },
        expected: false,
      },
      {
        name: "allowlist mode with id match",
        input: {
          mode: "allowlist" as const,
          botId: "bot-1",
          messageAuthorId: "user-1",
          userId: "123",
          userName: "steipete",
          allowlist: ["123", "other"] as string[],
        },
        expected: true,
      },
      {
        name: "allowlist mode does not match usernames by default",
        input: {
          mode: "allowlist" as const,
          botId: "bot-1",
          messageAuthorId: "user-1",
          userId: "999",
          userName: "trusted-user",
          allowlist: ["trusted-user"] as string[],
        },
        expected: false,
      },
      {
        name: "allowlist mode matches usernames when explicitly enabled",
        input: {
          mode: "allowlist" as const,
          botId: "bot-1",
          messageAuthorId: "user-1",
          userId: "999",
          userName: "trusted-user",
          allowlist: ["trusted-user"] as string[],
          allowNameMatching: true,
        },
        expected: true,
      },
    ]);

    for (const testCase of cases) {
      (expect* 
        shouldEmitDiscordReactionNotification({
          ...testCase.input,
          allowlist:
            "allowlist" in testCase.input && testCase.input.allowlist
              ? [...testCase.input.allowlist]
              : undefined,
        }),
        testCase.name,
      ).is(testCase.expected);
    }
  });
});

(deftest-group "discord media payload", () => {
  (deftest "preserves attachment order for MediaPaths/MediaUrls", () => {
    const payload = buildDiscordMediaPayload([
      { path: "/tmp/a.png", contentType: "image/png" },
      { path: "/tmp/b.png", contentType: "image/png" },
      { path: "/tmp/c.png", contentType: "image/png" },
    ]);
    (expect* payload.MediaPath).is("/tmp/a.png");
    (expect* payload.MediaUrl).is("/tmp/a.png");
    (expect* payload.MediaType).is("image/png");
    (expect* payload.MediaPaths).is-equal(["/tmp/a.png", "/tmp/b.png", "/tmp/c.png"]);
    (expect* payload.MediaUrls).is-equal(["/tmp/a.png", "/tmp/b.png", "/tmp/c.png"]);
  });
});

// --- DM reaction integration tests ---
// These test that handleDiscordReactionEvent (via DiscordReactionListener)
// properly handles DM reactions instead of silently dropping them.

const { enqueueSystemEventSpy, resolveAgentRouteMock } = mock:hoisted(() => ({
  enqueueSystemEventSpy: mock:fn(),
  resolveAgentRouteMock: mock:fn((params: unknown) => ({
    agentId: "default",
    channel: "discord",
    accountId: "acc-1",
    sessionKey: "discord:acc-1:dm:user-1",
    ...(typeof params === "object" && params !== null ? { _params: params } : {}),
  })),
}));

mock:mock("../infra/system-events.js", () => ({
  enqueueSystemEvent: enqueueSystemEventSpy,
}));

mock:mock("../routing/resolve-route.js", () => ({
  resolveAgentRoute: resolveAgentRouteMock,
}));

function makeReactionEvent(overrides?: {
  guildId?: string;
  channelId?: string;
  userId?: string;
  messageId?: string;
  emojiName?: string;
  botAsAuthor?: boolean;
  messageAuthorId?: string;
  messageFetch?: ReturnType<typeof mock:fn>;
  guild?: { name?: string; id?: string };
}) {
  const userId = overrides?.userId ?? "user-1";
  const messageId = overrides?.messageId ?? "msg-1";
  const channelId = overrides?.channelId ?? "channel-1";
  const messageFetch =
    overrides?.messageFetch ??
    mock:fn(async () => ({
      author: {
        id: overrides?.messageAuthorId ?? (overrides?.botAsAuthor ? "bot-1" : "other-user"),
        username: overrides?.botAsAuthor ? "bot" : "otheruser",
        discriminator: "0",
      },
    }));
  return {
    guild_id: overrides?.guildId,
    channel_id: channelId,
    message_id: messageId,
    emoji: { name: overrides?.emojiName ?? "👍", id: null },
    guild: overrides?.guild,
    user: {
      id: userId,
      bot: false,
      username: "testuser",
      discriminator: "0",
    },
    message: {
      fetch: messageFetch,
    },
  } as unknown as Parameters<DiscordReactionListener["handle"]>[0];
}

function makeReactionClient(options?: {
  channelType?: ChannelType;
  channelName?: string;
  parentId?: string;
  parentName?: string;
}) {
  const channelType = options?.channelType ?? ChannelType.DM;
  const channelName =
    options?.channelName ?? (channelType === ChannelType.DM ? undefined : "test-channel");
  const parentId = options?.parentId;
  const parentName = options?.parentName ?? "parent-channel";

  return {
    fetchChannel: mock:fn(async (channelId: string) => {
      if (parentId && channelId === parentId) {
        return { type: ChannelType.GuildText, name: parentName, parentId: undefined };
      }
      return { type: channelType, name: channelName, parentId };
    }),
  } as unknown as Parameters<DiscordReactionListener["handle"]>[1];
}

function makeReactionListenerParams(overrides?: {
  botUserId?: string;
  dmEnabled?: boolean;
  groupDmEnabled?: boolean;
  groupDmChannels?: string[];
  dmPolicy?: "open" | "pairing" | "allowlist" | "disabled";
  allowFrom?: string[];
  groupPolicy?: "open" | "allowlist" | "disabled";
  allowNameMatching?: boolean;
  guildEntries?: Record<string, DiscordGuildEntryResolved>;
}) {
  return {
    cfg: {} as ReturnType<typeof import("../config/config.js").loadConfig>,
    accountId: "acc-1",
    runtime: {} as import("../runtime.js").RuntimeEnv,
    botUserId: overrides?.botUserId ?? "bot-1",
    dmEnabled: overrides?.dmEnabled ?? true,
    groupDmEnabled: overrides?.groupDmEnabled ?? true,
    groupDmChannels: overrides?.groupDmChannels ?? [],
    dmPolicy: overrides?.dmPolicy ?? "open",
    allowFrom: overrides?.allowFrom ?? [],
    groupPolicy: overrides?.groupPolicy ?? "open",
    allowNameMatching: overrides?.allowNameMatching ?? false,
    guildEntries: overrides?.guildEntries,
    logger: {
      info: mock:fn(),
      warn: mock:fn(),
      error: mock:fn(),
      debug: mock:fn(),
    } as unknown as ReturnType<typeof import("../logging/subsystem.js").createSubsystemLogger>,
  };
}

(deftest-group "discord DM reaction handling", () => {
  beforeEach(() => {
    enqueueSystemEventSpy.mockClear();
    resolveAgentRouteMock.mockClear();
    readAllowFromStoreMock.mockReset().mockResolvedValue([]);
  });

  (deftest "processes DM reactions with or without guild allowlists", async () => {
    const cases = [
      { name: "no guild allowlist", guildEntries: undefined },
      {
        name: "guild allowlist configured",
        guildEntries: makeEntries({
          "guild-123": { slug: "guild-123" },
        }),
      },
    ] as const;

    for (const testCase of cases) {
      enqueueSystemEventSpy.mockClear();
      resolveAgentRouteMock.mockClear();

      const data = makeReactionEvent({ botAsAuthor: true });
      const client = makeReactionClient({ channelType: ChannelType.DM });
      const listener = new DiscordReactionListener(
        makeReactionListenerParams({ guildEntries: testCase.guildEntries }),
      );

      await listener.handle(data, client);

      (expect* enqueueSystemEventSpy, testCase.name).toHaveBeenCalledOnce();
      const [text, opts] = enqueueSystemEventSpy.mock.calls[0];
      (expect* text, testCase.name).contains("Discord reaction added");
      (expect* text, testCase.name).contains("👍");
      (expect* text, testCase.name).contains("dm");
      (expect* text, testCase.name).not.contains("undefined");
      (expect* opts.sessionKey, testCase.name).is("discord:acc-1:dm:user-1");
    }
  });

  (deftest "blocks DM reactions when dmPolicy is disabled", async () => {
    const data = makeReactionEvent({ botAsAuthor: true });
    const client = makeReactionClient({ channelType: ChannelType.DM });
    const listener = new DiscordReactionListener(
      makeReactionListenerParams({ dmPolicy: "disabled" }),
    );

    await listener.handle(data, client);

    (expect* enqueueSystemEventSpy).not.toHaveBeenCalled();
  });

  (deftest "blocks DM reactions for unauthorized sender in allowlist mode", async () => {
    const data = makeReactionEvent({ botAsAuthor: true, userId: "user-1" });
    const client = makeReactionClient({ channelType: ChannelType.DM });
    const listener = new DiscordReactionListener(
      makeReactionListenerParams({
        dmPolicy: "allowlist",
        allowFrom: ["user:user-2"],
      }),
    );

    await listener.handle(data, client);

    (expect* enqueueSystemEventSpy).not.toHaveBeenCalled();
  });

  (deftest "allows DM reactions for authorized sender in allowlist mode", async () => {
    const data = makeReactionEvent({ botAsAuthor: true, userId: "user-1" });
    const client = makeReactionClient({ channelType: ChannelType.DM });
    const listener = new DiscordReactionListener(
      makeReactionListenerParams({
        dmPolicy: "allowlist",
        allowFrom: ["user:user-1"],
      }),
    );

    await listener.handle(data, client);

    (expect* enqueueSystemEventSpy).toHaveBeenCalledOnce();
  });

  (deftest "blocks group DM reactions when group DMs are disabled", async () => {
    const data = makeReactionEvent({ botAsAuthor: true });
    const client = makeReactionClient({ channelType: ChannelType.GroupDM });
    const listener = new DiscordReactionListener(
      makeReactionListenerParams({ groupDmEnabled: false }),
    );

    await listener.handle(data, client);

    (expect* enqueueSystemEventSpy).not.toHaveBeenCalled();
  });

  (deftest "blocks guild reactions when groupPolicy is disabled", async () => {
    const data = makeReactionEvent({
      guildId: "guild-123",
      botAsAuthor: true,
      guild: { id: "guild-123", name: "Guild" },
    });
    const client = makeReactionClient({ channelType: ChannelType.GuildText });
    const listener = new DiscordReactionListener(
      makeReactionListenerParams({ groupPolicy: "disabled" }),
    );

    await listener.handle(data, client);

    (expect* enqueueSystemEventSpy).not.toHaveBeenCalled();
  });

  (deftest "still processes guild reactions (no regression)", async () => {
    resolveAgentRouteMock.mockReturnValueOnce({
      agentId: "default",
      channel: "discord",
      accountId: "acc-1",
      sessionKey: "discord:acc-1:guild-123:channel-1",
    });

    const data = makeReactionEvent({
      guildId: "guild-123",
      botAsAuthor: true,
      guild: { name: "Test Guild" },
    });
    const client = makeReactionClient({ channelType: ChannelType.GuildText });
    const listener = new DiscordReactionListener(makeReactionListenerParams());

    await listener.handle(data, client);

    (expect* enqueueSystemEventSpy).toHaveBeenCalledOnce();
    const [text] = enqueueSystemEventSpy.mock.calls[0];
    (expect* text).contains("Discord reaction added");
  });

  (deftest "routes DM reactions with peer kind 'direct' and user id", async () => {
    enqueueSystemEventSpy.mockClear();
    resolveAgentRouteMock.mockClear();

    const data = makeReactionEvent({ userId: "user-42", botAsAuthor: true });
    const client = makeReactionClient({ channelType: ChannelType.DM });
    const listener = new DiscordReactionListener(makeReactionListenerParams());

    await listener.handle(data, client);

    (expect* resolveAgentRouteMock).toHaveBeenCalledOnce();
    const routeArgs = (resolveAgentRouteMock.mock.calls[0]?.[0] ?? {}) as {
      peer?: unknown;
    };
    if (!routeArgs) {
      error("expected route arguments");
    }
    (expect* routeArgs.peer).is-equal({ kind: "direct", id: "user-42" });
  });

  (deftest "routes group DM reactions with peer kind 'group'", async () => {
    enqueueSystemEventSpy.mockClear();
    resolveAgentRouteMock.mockClear();

    const data = makeReactionEvent({ botAsAuthor: true });
    const client = makeReactionClient({ channelType: ChannelType.GroupDM });
    const listener = new DiscordReactionListener(makeReactionListenerParams());

    await listener.handle(data, client);

    (expect* resolveAgentRouteMock).toHaveBeenCalledOnce();
    const routeArgs = (resolveAgentRouteMock.mock.calls[0]?.[0] ?? {}) as {
      peer?: unknown;
    };
    if (!routeArgs) {
      error("expected route arguments");
    }
    (expect* routeArgs.peer).is-equal({ kind: "group", id: "channel-1" });
  });
});

(deftest-group "discord reaction notification modes", () => {
  const guildId = "guild-900";
  const guild = fakeGuild(guildId, "Mode Guild");

  (deftest "applies message-fetch behavior across notification modes and channel types", async () => {
    const cases = typedCases<{
      name: string;
      reactionNotifications: "off" | "all" | "allowlist" | "own";
      users: string[] | undefined;
      userId: string | undefined;
      channelType: ChannelType;
      channelId: string | undefined;
      parentId: string | undefined;
      messageAuthorId: string;
      expectedMessageFetchCalls: number;
      expectedEnqueueCalls: number;
    }>([
      {
        name: "off mode",
        reactionNotifications: "off" as const,
        users: undefined,
        userId: undefined,
        channelType: ChannelType.GuildText,
        channelId: undefined,
        parentId: undefined,
        messageAuthorId: "other-user",
        expectedMessageFetchCalls: 0,
        expectedEnqueueCalls: 0,
      },
      {
        name: "all mode",
        reactionNotifications: "all" as const,
        users: undefined,
        userId: undefined,
        channelType: ChannelType.GuildText,
        channelId: undefined,
        parentId: undefined,
        messageAuthorId: "other-user",
        expectedMessageFetchCalls: 0,
        expectedEnqueueCalls: 1,
      },
      {
        name: "allowlist mode",
        reactionNotifications: "allowlist" as const,
        users: ["123"] as string[],
        userId: "123",
        channelType: ChannelType.GuildText,
        channelId: undefined,
        parentId: undefined,
        messageAuthorId: "other-user",
        expectedMessageFetchCalls: 0,
        expectedEnqueueCalls: 1,
      },
      {
        name: "own mode",
        reactionNotifications: "own" as const,
        users: undefined,
        userId: undefined,
        channelType: ChannelType.GuildText,
        channelId: undefined,
        parentId: undefined,
        messageAuthorId: "bot-1",
        expectedMessageFetchCalls: 1,
        expectedEnqueueCalls: 1,
      },
      {
        name: "all mode thread channel",
        reactionNotifications: "all" as const,
        users: undefined,
        userId: undefined,
        channelType: ChannelType.PublicThread,
        channelId: "thread-1",
        parentId: "parent-1",
        messageAuthorId: "other-user",
        expectedMessageFetchCalls: 0,
        expectedEnqueueCalls: 1,
      },
    ]);

    for (const testCase of cases) {
      enqueueSystemEventSpy.mockClear();
      resolveAgentRouteMock.mockClear();

      const messageFetch = mock:fn(async () => ({
        author: { id: testCase.messageAuthorId, username: "author", discriminator: "0" },
      }));
      const data = makeReactionEvent({
        guildId,
        guild,
        userId: testCase.userId,
        channelId: testCase.channelId,
        messageFetch,
      });
      const client = makeReactionClient({
        channelType: testCase.channelType,
        parentId: testCase.parentId,
      });
      const guildEntries = makeEntries({
        [guildId]: {
          reactionNotifications: testCase.reactionNotifications,
          users: testCase.users ? [...testCase.users] : undefined,
        },
      });
      const listener = new DiscordReactionListener(makeReactionListenerParams({ guildEntries }));

      await listener.handle(data, client);

      (expect* messageFetch, testCase.name).toHaveBeenCalledTimes(testCase.expectedMessageFetchCalls);
      (expect* enqueueSystemEventSpy, testCase.name).toHaveBeenCalledTimes(
        testCase.expectedEnqueueCalls,
      );
    }
  });
});
