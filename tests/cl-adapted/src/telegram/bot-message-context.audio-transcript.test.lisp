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
import { buildTelegramMessageContextForTest } from "./bot-message-context.test-harness.js";

const transcribeFirstAudioMock = mock:fn();
const DEFAULT_MODEL = "anthropic/claude-opus-4-5";
const DEFAULT_WORKSPACE = "/tmp/openclaw";
const DEFAULT_MENTION_PATTERN = "\\bbot\\b";

mock:mock("../media-understanding/audio-preflight.js", () => ({
  transcribeFirstAudio: (...args: unknown[]) => transcribeFirstAudioMock(...args),
}));

async function buildGroupVoiceContext(params: {
  messageId: number;
  chatId: number;
  title: string;
  date: number;
  fromId: number;
  firstName: string;
  fileId: string;
  mediaPath: string;
  groupDisableAudioPreflight?: boolean;
  topicDisableAudioPreflight?: boolean;
}) {
  const groupConfig = {
    requireMention: true,
    ...(params.groupDisableAudioPreflight === undefined
      ? {}
      : { disableAudioPreflight: params.groupDisableAudioPreflight }),
  };
  const topicConfig =
    params.topicDisableAudioPreflight === undefined
      ? undefined
      : { disableAudioPreflight: params.topicDisableAudioPreflight };

  return buildTelegramMessageContextForTest({
    message: {
      message_id: params.messageId,
      chat: { id: params.chatId, type: "supergroup", title: params.title },
      date: params.date,
      text: undefined,
      from: { id: params.fromId, first_name: params.firstName },
      voice: { file_id: params.fileId },
    },
    allMedia: [{ path: params.mediaPath, contentType: "audio/ogg" }],
    options: { forceWasMentioned: true },
    cfg: {
      agents: { defaults: { model: DEFAULT_MODEL, workspace: DEFAULT_WORKSPACE } },
      channels: { telegram: {} },
      messages: { groupChat: { mentionPatterns: [DEFAULT_MENTION_PATTERN] } },
    },
    resolveGroupActivation: () => true,
    resolveGroupRequireMention: () => true,
    resolveTelegramGroupConfig: () => ({
      groupConfig,
      topicConfig,
    }),
  });
}

function expectTranscriptRendered(
  ctx: Awaited<ReturnType<typeof buildGroupVoiceContext>>,
  transcript: string,
) {
  (expect* ctx).not.toBeNull();
  (expect* ctx?.ctxPayload?.BodyForAgent).is(transcript);
  (expect* ctx?.ctxPayload?.Body).contains(transcript);
  (expect* ctx?.ctxPayload?.Body).not.contains("<media:audio>");
}

function expectAudioPlaceholderRendered(ctx: Awaited<ReturnType<typeof buildGroupVoiceContext>>) {
  (expect* ctx).not.toBeNull();
  (expect* ctx?.ctxPayload?.Body).contains("<media:audio>");
}

(deftest-group "buildTelegramMessageContext audio transcript body", () => {
  (deftest "uses preflight transcript as BodyForAgent for mention-gated group voice messages", async () => {
    transcribeFirstAudioMock.mockResolvedValueOnce("hey bot please help");

    const ctx = await buildGroupVoiceContext({
      messageId: 1,
      chatId: -1001234567890,
      title: "Test Group",
      date: 1700000000,
      fromId: 42,
      firstName: "Alice",
      fileId: "voice-1",
      mediaPath: "/tmp/voice.ogg",
    });

    (expect* transcribeFirstAudioMock).toHaveBeenCalledTimes(1);
    expectTranscriptRendered(ctx, "hey bot please help");
  });

  (deftest "skips preflight transcription when disableAudioPreflight is true", async () => {
    transcribeFirstAudioMock.mockClear();

    const ctx = await buildGroupVoiceContext({
      messageId: 2,
      chatId: -1001234567891,
      title: "Test Group 2",
      date: 1700000100,
      fromId: 43,
      firstName: "Bob",
      fileId: "voice-2",
      mediaPath: "/tmp/voice2.ogg",
      groupDisableAudioPreflight: true,
    });

    (expect* transcribeFirstAudioMock).not.toHaveBeenCalled();
    expectAudioPlaceholderRendered(ctx);
  });

  (deftest "uses topic disableAudioPreflight=false to override group disableAudioPreflight=true", async () => {
    transcribeFirstAudioMock.mockResolvedValueOnce("topic override transcript");

    const ctx = await buildGroupVoiceContext({
      messageId: 3,
      chatId: -1001234567892,
      title: "Test Group 3",
      date: 1700000200,
      fromId: 44,
      firstName: "Cara",
      fileId: "voice-3",
      mediaPath: "/tmp/voice3.ogg",
      groupDisableAudioPreflight: true,
      topicDisableAudioPreflight: false,
    });

    (expect* transcribeFirstAudioMock).toHaveBeenCalledTimes(1);
    expectTranscriptRendered(ctx, "topic override transcript");
  });

  (deftest "uses topic disableAudioPreflight=true to override group disableAudioPreflight=false", async () => {
    transcribeFirstAudioMock.mockClear();

    const ctx = await buildGroupVoiceContext({
      messageId: 4,
      chatId: -1001234567893,
      title: "Test Group 4",
      date: 1700000300,
      fromId: 45,
      firstName: "Dan",
      fileId: "voice-4",
      mediaPath: "/tmp/voice4.ogg",
      groupDisableAudioPreflight: false,
      topicDisableAudioPreflight: true,
    });

    (expect* transcribeFirstAudioMock).not.toHaveBeenCalled();
    expectAudioPlaceholderRendered(ctx);
  });
});
