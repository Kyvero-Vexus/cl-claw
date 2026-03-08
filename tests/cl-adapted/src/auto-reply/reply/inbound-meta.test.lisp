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
import type { TemplateContext } from "../templating.js";
import { buildInboundMetaSystemPrompt, buildInboundUserContextPrefix } from "./inbound-meta.js";

function parseInboundMetaPayload(text: string): Record<string, unknown> {
  const match = text.match(/```json\n([\s\S]*?)\n```/);
  if (!match?.[1]) {
    error("missing inbound meta json block");
  }
  return JSON.parse(match[1]) as Record<string, unknown>;
}

function parseConversationInfoPayload(text: string): Record<string, unknown> {
  const match = text.match(/Conversation info \(untrusted metadata\):\n```json\n([\s\S]*?)\n```/);
  if (!match?.[1]) {
    error("missing conversation info json block");
  }
  return JSON.parse(match[1]) as Record<string, unknown>;
}

function parseSenderInfoPayload(text: string): Record<string, unknown> {
  const match = text.match(/Sender \(untrusted metadata\):\n```json\n([\s\S]*?)\n```/);
  if (!match?.[1]) {
    error("missing sender info json block");
  }
  return JSON.parse(match[1]) as Record<string, unknown>;
}

(deftest-group "buildInboundMetaSystemPrompt", () => {
  (deftest "includes session-stable routing fields", () => {
    const prompt = buildInboundMetaSystemPrompt({
      MessageSid: "123",
      MessageSidFull: "123",
      ReplyToId: "99",
      OriginatingTo: "telegram:5494292670",
      AccountId: " work ",
      OriginatingChannel: "telegram",
      Provider: "telegram",
      Surface: "telegram",
      ChatType: "direct",
    } as TemplateContext);

    const payload = parseInboundMetaPayload(prompt);
    (expect* payload["schema"]).is("openclaw.inbound_meta.v1");
    (expect* payload["chat_id"]).is("telegram:5494292670");
    (expect* payload["account_id"]).is("work");
    (expect* payload["channel"]).is("telegram");
  });

  (deftest "does not include per-turn message identifiers (cache stability)", () => {
    const prompt = buildInboundMetaSystemPrompt({
      MessageSid: "123",
      MessageSidFull: "123",
      ReplyToId: "99",
      SenderId: "289522496",
      OriginatingTo: "telegram:5494292670",
      OriginatingChannel: "telegram",
      Provider: "telegram",
      Surface: "telegram",
      ChatType: "direct",
    } as TemplateContext);

    const payload = parseInboundMetaPayload(prompt);
    (expect* payload["message_id"]).toBeUndefined();
    (expect* payload["message_id_full"]).toBeUndefined();
    (expect* payload["reply_to_id"]).toBeUndefined();
    (expect* payload["sender_id"]).toBeUndefined();
  });

  (deftest "does not include per-turn flags in system metadata", () => {
    const prompt = buildInboundMetaSystemPrompt({
      ReplyToBody: "quoted",
      ForwardedFrom: "sender",
      ThreadStarterBody: "starter",
      InboundHistory: [{ sender: "a", body: "b", timestamp: 1 }],
      WasMentioned: true,
      OriginatingTo: "telegram:-1001249586642",
      OriginatingChannel: "telegram",
      Provider: "telegram",
      Surface: "telegram",
      ChatType: "group",
    } as TemplateContext);

    const payload = parseInboundMetaPayload(prompt);
    (expect* payload["flags"]).toBeUndefined();
  });

  (deftest "omits sender_id when blank", () => {
    const prompt = buildInboundMetaSystemPrompt({
      MessageSid: "458",
      SenderId: "   ",
      OriginatingTo: "telegram:-1001249586642",
      OriginatingChannel: "telegram",
      Provider: "telegram",
      Surface: "telegram",
      ChatType: "group",
    } as TemplateContext);

    const payload = parseInboundMetaPayload(prompt);
    (expect* payload["sender_id"]).toBeUndefined();
  });
});

(deftest-group "buildInboundUserContextPrefix", () => {
  (deftest "omits conversation label block for direct chats", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "direct",
      ConversationLabel: "openclaw-tui",
    } as TemplateContext);

    (expect* text).is("");
  });

  (deftest "hides message identifiers for direct webchat chats", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "direct",
      OriginatingChannel: "webchat",
      MessageSid: "short-id",
      MessageSidFull: "provider-full-id",
    } as TemplateContext);

    (expect* text).is("");
  });

  (deftest "includes message identifiers for direct external-channel chats", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "direct",
      OriginatingChannel: "whatsapp",
      MessageSid: "short-id",
      MessageSidFull: "provider-full-id",
      SenderE164: " +15551234567 ",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["message_id"]).is("short-id");
    (expect* conversationInfo["message_id_full"]).toBeUndefined();
    (expect* conversationInfo["sender"]).is("+15551234567");
    (expect* conversationInfo["conversation_label"]).toBeUndefined();
  });

  (deftest "includes message identifiers for direct chats when channel is inferred from Provider", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "direct",
      Provider: "whatsapp",
      MessageSid: "provider-only-id",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["message_id"]).is("provider-only-id");
  });

  (deftest "does not treat group chats as direct based on sender id", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      SenderId: "openclaw-control-ui",
      MessageSid: "123",
      ConversationLabel: "some-label",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["message_id"]).is("123");
    (expect* conversationInfo["sender_id"]).is("openclaw-control-ui");
    (expect* conversationInfo["conversation_label"]).is("some-label");
  });

  (deftest "keeps conversation label for group chats", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      ConversationLabel: "ops-room",
    } as TemplateContext);

    (expect* text).contains("Conversation info (untrusted metadata):");
    (expect* text).contains('"conversation_label": "ops-room"');
  });

  (deftest "includes sender identifier in conversation info", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      SenderE164: " +15551234567 ",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["sender"]).is("+15551234567");
  });

  (deftest "prefers SenderName in conversation info sender identity", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      SenderName: " Tyler ",
      SenderId: " +15551234567 ",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["sender"]).is("Tyler");
  });

  (deftest "includes sender metadata block for direct chats", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "direct",
      SenderName: "Tyler",
      SenderId: "+15551234567",
    } as TemplateContext);

    const senderInfo = parseSenderInfoPayload(text);
    (expect* senderInfo["label"]).is("Tyler (+15551234567)");
    (expect* senderInfo["id"]).is("+15551234567");
  });

  (deftest "includes formatted timestamp in conversation info when provided", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "msg-with-ts",
      Timestamp: Date.UTC(2026, 1, 15, 13, 35),
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["timestamp"]).is-equal(expect.any(String));
  });

  (deftest "omits invalid timestamps instead of throwing", () => {
    (expect* () =>
      buildInboundUserContextPrefix({
        ChatType: "group",
        MessageSid: "msg-with-bad-ts",
        Timestamp: 1e20,
      } as TemplateContext),
    ).not.signals-error();

    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "msg-with-bad-ts",
      Timestamp: 1e20,
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["timestamp"]).toBeUndefined();
  });

  (deftest "includes message_id in conversation info", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "  msg-123  ",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["message_id"]).is("msg-123");
  });

  (deftest "prefers MessageSid when both MessageSid and MessageSidFull are present", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "short-id",
      MessageSidFull: "full-provider-message-id",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["message_id"]).is("short-id");
    (expect* conversationInfo["message_id_full"]).toBeUndefined();
  });

  (deftest "falls back to MessageSidFull when MessageSid is missing", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "   ",
      MessageSidFull: "full-provider-message-id",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["message_id"]).is("full-provider-message-id");
    (expect* conversationInfo["message_id_full"]).toBeUndefined();
  });

  (deftest "includes reply_to_id in conversation info", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "msg-200",
      ReplyToId: "msg-199",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["reply_to_id"]).is("msg-199");
  });

  (deftest "includes sender_id in conversation info", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "msg-456",
      SenderId: "289522496",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["sender_id"]).is("289522496");
  });

  (deftest "includes dynamic per-turn flags in conversation info", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      WasMentioned: true,
      ReplyToBody: "quoted",
      ForwardedFrom: "sender",
      ThreadStarterBody: "starter",
      InboundHistory: [{ sender: "a", body: "b", timestamp: 1 }],
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["is_group_chat"]).is(true);
    (expect* conversationInfo["was_mentioned"]).is(true);
    (expect* conversationInfo["has_reply_context"]).is(true);
    (expect* conversationInfo["has_forwarded_context"]).is(true);
    (expect* conversationInfo["has_thread_starter"]).is(true);
    (expect* conversationInfo["history_count"]).is(1);
  });

  (deftest "trims sender_id in conversation info", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      MessageSid: "msg-457",
      SenderId: "  289522496  ",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["sender_id"]).is("289522496");
  });

  (deftest "falls back to SenderId when sender phone is missing", () => {
    const text = buildInboundUserContextPrefix({
      ChatType: "group",
      SenderId: " user@example.com ",
    } as TemplateContext);

    const conversationInfo = parseConversationInfoPayload(text);
    (expect* conversationInfo["sender"]).is("user@example.com");
  });
});
