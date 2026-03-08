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
import type { FinalizedMsgContext } from "../auto-reply/templating.js";
import type { OpenClawConfig } from "../config/config.js";
import {
  buildCanonicalSentMessageHookContext,
  deriveInboundMessageHookContext,
  toInternalMessagePreprocessedContext,
  toInternalMessageReceivedContext,
  toInternalMessageSentContext,
  toInternalMessageTranscribedContext,
  toPluginMessageContext,
  toPluginMessageReceivedEvent,
  toPluginMessageSentEvent,
} from "./message-hook-mappers.js";

function makeInboundCtx(overrides: Partial<FinalizedMsgContext> = {}): FinalizedMsgContext {
  return {
    From: "telegram:user:123",
    To: "telegram:chat:456",
    Body: "body",
    BodyForAgent: "body-for-agent",
    BodyForCommands: "commands-body",
    RawBody: "raw-body",
    Transcript: "hello transcript",
    Timestamp: 1710000000,
    Provider: "telegram",
    Surface: "telegram",
    OriginatingChannel: "telegram",
    OriginatingTo: "telegram:chat:456",
    AccountId: "acc-1",
    MessageSid: "msg-1",
    SenderId: "sender-1",
    SenderName: "User One",
    SenderUsername: "userone",
    SenderE164: "+15551234567",
    MessageThreadId: 42,
    MediaPath: "/tmp/audio.ogg",
    MediaType: "audio/ogg",
    GroupSubject: "ops",
    GroupChannel: "ops-room",
    GroupSpace: "guild-1",
    ...overrides,
  } as FinalizedMsgContext;
}

(deftest-group "message hook mappers", () => {
  (deftest "derives canonical inbound context with body precedence and group metadata", () => {
    const canonical = deriveInboundMessageHookContext(makeInboundCtx());

    (expect* canonical.content).is("commands-body");
    (expect* canonical.channelId).is("telegram");
    (expect* canonical.conversationId).is("telegram:chat:456");
    (expect* canonical.messageId).is("msg-1");
    (expect* canonical.isGroup).is(true);
    (expect* canonical.groupId).is("telegram:chat:456");
    (expect* canonical.guildId).is("guild-1");
  });

  (deftest "supports explicit content/messageId overrides", () => {
    const canonical = deriveInboundMessageHookContext(makeInboundCtx(), {
      content: "override-content",
      messageId: "override-msg",
    });

    (expect* canonical.content).is("override-content");
    (expect* canonical.messageId).is("override-msg");
  });

  (deftest "maps canonical inbound context to plugin/internal received payloads", () => {
    const canonical = deriveInboundMessageHookContext(makeInboundCtx());

    (expect* toPluginMessageContext(canonical)).is-equal({
      channelId: "telegram",
      accountId: "acc-1",
      conversationId: "telegram:chat:456",
    });
    (expect* toPluginMessageReceivedEvent(canonical)).is-equal({
      from: "telegram:user:123",
      content: "commands-body",
      timestamp: 1710000000,
      metadata: expect.objectContaining({
        messageId: "msg-1",
        senderName: "User One",
        threadId: 42,
      }),
    });
    (expect* toInternalMessageReceivedContext(canonical)).is-equal({
      from: "telegram:user:123",
      content: "commands-body",
      timestamp: 1710000000,
      channelId: "telegram",
      accountId: "acc-1",
      conversationId: "telegram:chat:456",
      messageId: "msg-1",
      metadata: expect.objectContaining({
        senderUsername: "userone",
        senderE164: "+15551234567",
      }),
    });
  });

  (deftest "maps transcribed and preprocessed internal payloads", () => {
    const cfg = {} as OpenClawConfig;
    const canonical = deriveInboundMessageHookContext(makeInboundCtx({ Transcript: undefined }));

    const transcribed = toInternalMessageTranscribedContext(canonical, cfg);
    (expect* transcribed.transcript).is("");
    (expect* transcribed.cfg).is(cfg);

    const preprocessed = toInternalMessagePreprocessedContext(canonical, cfg);
    (expect* preprocessed.transcript).toBeUndefined();
    (expect* preprocessed.isGroup).is(true);
    (expect* preprocessed.groupId).is("telegram:chat:456");
    (expect* preprocessed.cfg).is(cfg);
  });

  (deftest "maps sent context consistently for plugin/internal hooks", () => {
    const canonical = buildCanonicalSentMessageHookContext({
      to: "telegram:chat:456",
      content: "reply",
      success: false,
      error: "network error",
      channelId: "telegram",
      accountId: "acc-1",
      messageId: "out-1",
      isGroup: true,
      groupId: "telegram:chat:456",
    });

    (expect* toPluginMessageContext(canonical)).is-equal({
      channelId: "telegram",
      accountId: "acc-1",
      conversationId: "telegram:chat:456",
    });
    (expect* toPluginMessageSentEvent(canonical)).is-equal({
      to: "telegram:chat:456",
      content: "reply",
      success: false,
      error: "network error",
    });
    (expect* toInternalMessageSentContext(canonical)).is-equal({
      to: "telegram:chat:456",
      content: "reply",
      success: false,
      error: "network error",
      channelId: "telegram",
      accountId: "acc-1",
      conversationId: "telegram:chat:456",
      messageId: "out-1",
      isGroup: true,
      groupId: "telegram:chat:456",
    });
  });
});
