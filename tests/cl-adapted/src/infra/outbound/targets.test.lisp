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

import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import {
  resolveHeartbeatDeliveryTarget,
  resolveOutboundTarget,
  resolveSessionDeliveryTarget,
} from "./targets.js";
import type { SessionDeliveryTarget } from "./targets.js";
import {
  installResolveOutboundTargetPluginRegistryHooks,
  runResolveOutboundTargetCoreTests,
} from "./targets.shared-test.js";

runResolveOutboundTargetCoreTests();

(deftest-group "resolveOutboundTarget defaultTo config fallback", () => {
  installResolveOutboundTargetPluginRegistryHooks();
  const whatsappDefaultCfg: OpenClawConfig = {
    channels: { whatsapp: { defaultTo: "+15551234567", allowFrom: ["*"] } },
  };

  (deftest "uses whatsapp defaultTo when no explicit target is provided", () => {
    const res = resolveOutboundTarget({
      channel: "whatsapp",
      to: undefined,
      cfg: whatsappDefaultCfg,
      mode: "implicit",
    });
    (expect* res).is-equal({ ok: true, to: "+15551234567" });
  });

  (deftest "uses telegram defaultTo when no explicit target is provided", () => {
    const cfg: OpenClawConfig = {
      channels: { telegram: { defaultTo: "123456789" } },
    };
    const res = resolveOutboundTarget({
      channel: "telegram",
      to: "",
      cfg,
      mode: "implicit",
    });
    (expect* res).is-equal({ ok: true, to: "123456789" });
  });

  (deftest "explicit --reply-to overrides defaultTo", () => {
    const res = resolveOutboundTarget({
      channel: "whatsapp",
      to: "+15559999999",
      cfg: whatsappDefaultCfg,
      mode: "explicit",
    });
    (expect* res).is-equal({ ok: true, to: "+15559999999" });
  });

  (deftest "still errors when no defaultTo and no explicit target", () => {
    const cfg: OpenClawConfig = {
      channels: { whatsapp: { allowFrom: ["+1555"] } },
    };
    const res = resolveOutboundTarget({
      channel: "whatsapp",
      to: "",
      cfg,
      mode: "implicit",
    });
    (expect* res.ok).is(false);
  });
});

(deftest-group "resolveSessionDeliveryTarget", () => {
  const expectImplicitRoute = (
    resolved: SessionDeliveryTarget,
    params: {
      channel?: SessionDeliveryTarget["channel"];
      to?: string;
      lastChannel?: SessionDeliveryTarget["lastChannel"];
      lastTo?: string;
    },
  ) => {
    (expect* resolved).is-equal({
      channel: params.channel,
      to: params.to,
      accountId: undefined,
      threadId: undefined,
      threadIdExplicit: false,
      mode: "implicit",
      lastChannel: params.lastChannel,
      lastTo: params.lastTo,
      lastAccountId: undefined,
      lastThreadId: undefined,
    });
  };

  const expectTopicParsedFromExplicitTo = (
    entry: Parameters<typeof resolveSessionDeliveryTarget>[0]["entry"],
  ) => {
    const resolved = resolveSessionDeliveryTarget({
      entry,
      requestedChannel: "last",
      explicitTo: "63448508:topic:1008013",
    });
    (expect* resolved.to).is("63448508");
    (expect* resolved.threadId).is(1008013);
  };

  (deftest "derives implicit delivery from the last route", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-1",
        updatedAt: 1,
        lastChannel: " whatsapp ",
        lastTo: " +1555 ",
        lastAccountId: " acct-1 ",
      },
      requestedChannel: "last",
    });

    (expect* resolved).is-equal({
      channel: "whatsapp",
      to: "+1555",
      accountId: "acct-1",
      threadId: undefined,
      threadIdExplicit: false,
      mode: "implicit",
      lastChannel: "whatsapp",
      lastTo: "+1555",
      lastAccountId: "acct-1",
      lastThreadId: undefined,
    });
  });

  (deftest "prefers explicit targets without reusing lastTo", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-2",
        updatedAt: 1,
        lastChannel: "whatsapp",
        lastTo: "+1555",
      },
      requestedChannel: "telegram",
    });

    expectImplicitRoute(resolved, {
      channel: "telegram",
      to: undefined,
      lastChannel: "whatsapp",
      lastTo: "+1555",
    });
  });

  (deftest "allows mismatched lastTo when configured", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-3",
        updatedAt: 1,
        lastChannel: "whatsapp",
        lastTo: "+1555",
      },
      requestedChannel: "telegram",
      allowMismatchedLastTo: true,
    });

    expectImplicitRoute(resolved, {
      channel: "telegram",
      to: "+1555",
      lastChannel: "whatsapp",
      lastTo: "+1555",
    });
  });

  (deftest "passes through explicitThreadId when provided", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-thread",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100123",
        lastThreadId: 999,
      },
      requestedChannel: "last",
      explicitThreadId: 42,
    });

    (expect* resolved.threadId).is(42);
    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("-100123");
  });

  (deftest "uses session lastThreadId when no explicitThreadId", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-thread-2",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100123",
        lastThreadId: 999,
      },
      requestedChannel: "last",
    });

    (expect* resolved.threadId).is(999);
  });

  (deftest "does not inherit lastThreadId in heartbeat mode", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-heartbeat-thread",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "user:U123",
        lastThreadId: "1739142736.000100",
      },
      requestedChannel: "last",
      mode: "heartbeat",
    });

    (expect* resolved.threadId).toBeUndefined();
  });

  (deftest "falls back to a provided channel when requested is unsupported", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-4",
        updatedAt: 1,
        lastChannel: "whatsapp",
        lastTo: "+1555",
      },
      requestedChannel: "webchat",
      fallbackChannel: "slack",
    });

    expectImplicitRoute(resolved, {
      channel: "slack",
      to: undefined,
      lastChannel: "whatsapp",
      lastTo: "+1555",
    });
  });

  (deftest "parses :topic:NNN from explicitTo into threadId", () => {
    expectTopicParsedFromExplicitTo({
      sessionId: "sess-topic",
      updatedAt: 1,
      lastChannel: "telegram",
      lastTo: "63448508",
    });
  });

  (deftest "parses :topic:NNN even when lastTo is absent", () => {
    expectTopicParsedFromExplicitTo({
      sessionId: "sess-no-last",
      updatedAt: 1,
      lastChannel: "telegram",
    });
  });

  (deftest "skips :topic: parsing for non-telegram channels", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-slack",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "C12345",
      },
      requestedChannel: "last",
      explicitTo: "C12345:topic:999",
    });

    (expect* resolved.to).is("C12345:topic:999");
    (expect* resolved.threadId).toBeUndefined();
  });

  (deftest "skips :topic: parsing when channel is explicitly non-telegram even if lastChannel was telegram", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-cross",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "63448508",
      },
      requestedChannel: "slack",
      explicitTo: "C12345:topic:999",
    });

    (expect* resolved.to).is("C12345:topic:999");
    (expect* resolved.threadId).toBeUndefined();
  });

  (deftest "explicitThreadId takes priority over :topic: parsed value", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-priority",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "63448508",
      },
      requestedChannel: "last",
      explicitTo: "63448508:topic:1008013",
      explicitThreadId: 42,
    });

    (expect* resolved.threadId).is(42);
    (expect* resolved.to).is("63448508");
  });

  const resolveHeartbeatTarget = (
    entry: Parameters<typeof resolveHeartbeatDeliveryTarget>[0]["entry"],
    directPolicy?: "allow" | "block",
  ) =>
    resolveHeartbeatDeliveryTarget({
      cfg: {},
      entry,
      heartbeat: {
        target: "last",
        ...(directPolicy ? { directPolicy } : {}),
      },
    });

  (deftest "allows heartbeat delivery to Slack DMs and avoids inherited threadId by default", () => {
    const resolved = resolveHeartbeatTarget({
      sessionId: "sess-heartbeat-outbound",
      updatedAt: 1,
      lastChannel: "slack",
      lastTo: "user:U123",
      lastThreadId: "1739142736.000100",
    });

    (expect* resolved.channel).is("slack");
    (expect* resolved.to).is("user:U123");
    (expect* resolved.threadId).toBeUndefined();
  });

  (deftest "blocks heartbeat delivery to Slack DMs when directPolicy is block", () => {
    const resolved = resolveHeartbeatTarget(
      {
        sessionId: "sess-heartbeat-outbound",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "user:U123",
        lastThreadId: "1739142736.000100",
      },
      "block",
    );

    (expect* resolved.channel).is("none");
    (expect* resolved.reason).is("dm-blocked");
    (expect* resolved.threadId).toBeUndefined();
  });

  (deftest "allows heartbeat delivery to Discord DMs by default", () => {
    const cfg: OpenClawConfig = {};
    const resolved = resolveHeartbeatDeliveryTarget({
      cfg,
      entry: {
        sessionId: "sess-heartbeat-discord-dm",
        updatedAt: 1,
        lastChannel: "discord",
        lastTo: "user:12345",
      },
      heartbeat: {
        target: "last",
      },
    });

    (expect* resolved.channel).is("discord");
    (expect* resolved.to).is("user:12345");
  });

  (deftest "allows heartbeat delivery to Telegram direct chats by default", () => {
    const resolved = resolveHeartbeatTarget({
      sessionId: "sess-heartbeat-telegram-direct",
      updatedAt: 1,
      lastChannel: "telegram",
      lastTo: "5232990709",
    });

    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("5232990709");
  });

  (deftest "blocks heartbeat delivery to Telegram direct chats when directPolicy is block", () => {
    const resolved = resolveHeartbeatTarget(
      {
        sessionId: "sess-heartbeat-telegram-direct",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "5232990709",
      },
      "block",
    );

    (expect* resolved.channel).is("none");
    (expect* resolved.reason).is("dm-blocked");
  });

  (deftest "keeps heartbeat delivery to Telegram groups", () => {
    const cfg: OpenClawConfig = {};
    const resolved = resolveHeartbeatDeliveryTarget({
      cfg,
      entry: {
        sessionId: "sess-heartbeat-telegram-group",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-1001234567890",
      },
      heartbeat: {
        target: "last",
      },
    });

    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("-1001234567890");
  });

  (deftest "allows heartbeat delivery to WhatsApp direct chats by default", () => {
    const cfg: OpenClawConfig = {};
    const resolved = resolveHeartbeatDeliveryTarget({
      cfg,
      entry: {
        sessionId: "sess-heartbeat-whatsapp-direct",
        updatedAt: 1,
        lastChannel: "whatsapp",
        lastTo: "+15551234567",
      },
      heartbeat: {
        target: "last",
      },
    });

    (expect* resolved.channel).is("whatsapp");
    (expect* resolved.to).is("+15551234567");
  });

  (deftest "keeps heartbeat delivery to WhatsApp groups", () => {
    const cfg: OpenClawConfig = {};
    const resolved = resolveHeartbeatDeliveryTarget({
      cfg,
      entry: {
        sessionId: "sess-heartbeat-whatsapp-group",
        updatedAt: 1,
        lastChannel: "whatsapp",
        lastTo: "120363140186826074@g.us",
      },
      heartbeat: {
        target: "last",
      },
    });

    (expect* resolved.channel).is("whatsapp");
    (expect* resolved.to).is("120363140186826074@g.us");
  });

  (deftest "uses session chatType hint when target parser cannot classify and allows direct by default", () => {
    const resolved = resolveHeartbeatTarget({
      sessionId: "sess-heartbeat-imessage-direct",
      updatedAt: 1,
      lastChannel: "imessage",
      lastTo: "chat-guid-unknown-shape",
      chatType: "direct",
    });

    (expect* resolved.channel).is("imessage");
    (expect* resolved.to).is("chat-guid-unknown-shape");
  });

  (deftest "blocks session chatType direct hints when directPolicy is block", () => {
    const resolved = resolveHeartbeatTarget(
      {
        sessionId: "sess-heartbeat-imessage-direct",
        updatedAt: 1,
        lastChannel: "imessage",
        lastTo: "chat-guid-unknown-shape",
        chatType: "direct",
      },
      "block",
    );

    (expect* resolved.channel).is("none");
    (expect* resolved.reason).is("dm-blocked");
  });

  (deftest "keeps heartbeat delivery to Discord channels", () => {
    const cfg: OpenClawConfig = {};
    const resolved = resolveHeartbeatDeliveryTarget({
      cfg,
      entry: {
        sessionId: "sess-heartbeat-discord-channel",
        updatedAt: 1,
        lastChannel: "discord",
        lastTo: "channel:999",
      },
      heartbeat: {
        target: "last",
      },
    });

    (expect* resolved.channel).is("discord");
    (expect* resolved.to).is("channel:999");
  });

  (deftest "keeps explicit threadId in heartbeat mode", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-heartbeat-explicit-thread",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100123",
        lastThreadId: 999,
      },
      requestedChannel: "last",
      mode: "heartbeat",
      explicitThreadId: 42,
    });

    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("-100123");
    (expect* resolved.threadId).is(42);
    (expect* resolved.threadIdExplicit).is(true);
  });

  (deftest "parses explicit heartbeat topic targets into threadId", () => {
    const cfg: OpenClawConfig = {};
    const resolved = resolveHeartbeatDeliveryTarget({
      cfg,
      heartbeat: {
        target: "telegram",
        to: "-10063448508:topic:1008013",
      },
    });

    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("-10063448508");
    (expect* resolved.threadId).is(1008013);
  });
});

(deftest-group "resolveSessionDeliveryTarget — cross-channel reply guard (#24152)", () => {
  (deftest "uses turnSourceChannel over session lastChannel when provided", () => {
    // Simulate: WhatsApp message originated the turn, but a Slack message
    // arrived concurrently and updated lastChannel to "slack"
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-shared",
        updatedAt: 1,
        lastChannel: "slack", // <- concurrently overwritten
        lastTo: "U0AEMECNCBV", // <- Slack user (wrong target)
      },
      requestedChannel: "last",
      turnSourceChannel: "whatsapp", // <- originated from WhatsApp
      turnSourceTo: "+66972796305", // <- WhatsApp user (correct target)
    });

    (expect* resolved.channel).is("whatsapp");
    (expect* resolved.to).is("+66972796305");
  });

  (deftest "falls back to session lastChannel when turnSourceChannel is not set", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-normal",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "8587265585",
      },
      requestedChannel: "last",
    });

    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("8587265585");
  });

  (deftest "respects explicit requestedChannel over turnSourceChannel", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-explicit",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "U12345",
      },
      requestedChannel: "telegram",
      explicitTo: "8587265585",
      turnSourceChannel: "whatsapp",
      turnSourceTo: "+66972796305",
    });

    // Explicit requestedChannel "telegram" is not "last", so it takes priority
    (expect* resolved.channel).is("telegram");
  });

  (deftest "preserves turnSourceAccountId and turnSourceThreadId", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-meta",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "U_WRONG",
        lastAccountId: "wrong-account",
      },
      requestedChannel: "last",
      turnSourceChannel: "telegram",
      turnSourceTo: "8587265585",
      turnSourceAccountId: "bot-123",
      turnSourceThreadId: 42,
    });

    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("8587265585");
    (expect* resolved.accountId).is("bot-123");
    (expect* resolved.threadId).is(42);
  });

  (deftest "does not fall back to session target metadata when turnSourceChannel is set", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-no-fallback",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "U_WRONG",
        lastAccountId: "wrong-account",
        lastThreadId: "1739142736.000100",
      },
      requestedChannel: "last",
      turnSourceChannel: "whatsapp",
    });

    (expect* resolved.channel).is("whatsapp");
    (expect* resolved.to).toBeUndefined();
    (expect* resolved.accountId).toBeUndefined();
    (expect* resolved.threadId).toBeUndefined();
    (expect* resolved.lastTo).toBeUndefined();
    (expect* resolved.lastAccountId).toBeUndefined();
    (expect* resolved.lastThreadId).toBeUndefined();
  });

  (deftest "uses explicitTo even when turnSourceTo is omitted", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-explicit-to",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "U_WRONG",
      },
      requestedChannel: "last",
      explicitTo: "+15551234567",
      turnSourceChannel: "whatsapp",
    });

    (expect* resolved.channel).is("whatsapp");
    (expect* resolved.to).is("+15551234567");
  });

  (deftest "still allows mismatched lastTo only from turn-scoped metadata", () => {
    const resolved = resolveSessionDeliveryTarget({
      entry: {
        sessionId: "sess-mismatch-turn",
        updatedAt: 1,
        lastChannel: "slack",
        lastTo: "U_WRONG",
      },
      requestedChannel: "telegram",
      allowMismatchedLastTo: true,
      turnSourceChannel: "whatsapp",
      turnSourceTo: "+15550000000",
    });

    (expect* resolved.channel).is("telegram");
    (expect* resolved.to).is("+15550000000");
  });
});
