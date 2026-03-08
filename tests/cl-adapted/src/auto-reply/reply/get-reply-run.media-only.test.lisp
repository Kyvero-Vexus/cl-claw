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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { runPreparedReply } from "./get-reply-run.js";

mock:mock("../../agents/auth-profiles/session-override.js", () => ({
  resolveSessionAuthProfileOverride: mock:fn().mockResolvedValue(undefined),
}));

mock:mock("../../agents/pi-embedded.js", () => ({
  abortEmbeddedPiRun: mock:fn().mockReturnValue(false),
  isEmbeddedPiRunActive: mock:fn().mockReturnValue(false),
  isEmbeddedPiRunStreaming: mock:fn().mockReturnValue(false),
  resolveEmbeddedSessionLane: mock:fn().mockReturnValue("session:session-key"),
}));

mock:mock("../../config/sessions.js", () => ({
  resolveGroupSessionKey: mock:fn().mockReturnValue(undefined),
  resolveSessionFilePath: mock:fn().mockReturnValue("/tmp/session.jsonl"),
  resolveSessionFilePathOptions: mock:fn().mockReturnValue({}),
  updateSessionStore: mock:fn(),
}));

mock:mock("../../globals.js", () => ({
  logVerbose: mock:fn(),
}));

mock:mock("../../process/command-queue.js", () => ({
  clearCommandLane: mock:fn().mockReturnValue(0),
  getQueueSize: mock:fn().mockReturnValue(0),
}));

mock:mock("../../routing/session-key.js", () => ({
  normalizeMainKey: mock:fn().mockReturnValue("main"),
}));

mock:mock("../../utils/provider-utils.js", () => ({
  isReasoningTagProvider: mock:fn().mockReturnValue(false),
}));

mock:mock("../command-detection.js", () => ({
  hasControlCommand: mock:fn().mockReturnValue(false),
}));

mock:mock("./agent-runner.js", () => ({
  runReplyAgent: mock:fn().mockResolvedValue({ text: "ok" }),
}));

mock:mock("./body.js", () => ({
  applySessionHints: mock:fn().mockImplementation(async ({ baseBody }) => baseBody),
}));

mock:mock("./groups.js", () => ({
  buildGroupIntro: mock:fn().mockReturnValue(""),
  buildGroupChatContext: mock:fn().mockReturnValue(""),
}));

mock:mock("./inbound-meta.js", () => ({
  buildInboundMetaSystemPrompt: mock:fn().mockReturnValue(""),
  buildInboundUserContextPrefix: mock:fn().mockReturnValue(""),
}));

mock:mock("./queue.js", () => ({
  resolveQueueSettings: mock:fn().mockReturnValue({ mode: "followup" }),
}));

mock:mock("./route-reply.js", () => ({
  routeReply: mock:fn(),
}));

mock:mock("./session-updates.js", () => ({
  ensureSkillSnapshot: mock:fn().mockImplementation(async ({ sessionEntry, systemSent }) => ({
    sessionEntry,
    systemSent,
    skillsSnapshot: undefined,
  })),
  drainFormattedSystemEvents: mock:fn().mockResolvedValue(undefined),
}));

mock:mock("./typing-mode.js", () => ({
  resolveTypingMode: mock:fn().mockReturnValue("off"),
}));

import { runReplyAgent } from "./agent-runner.js";
import { routeReply } from "./route-reply.js";
import { drainFormattedSystemEvents } from "./session-updates.js";
import { resolveTypingMode } from "./typing-mode.js";

function baseParams(
  overrides: Partial<Parameters<typeof runPreparedReply>[0]> = {},
): Parameters<typeof runPreparedReply>[0] {
  return {
    ctx: {
      Body: "",
      RawBody: "",
      CommandBody: "",
      ThreadHistoryBody: "Earlier message in this thread",
      OriginatingChannel: "slack",
      OriginatingTo: "C123",
      ChatType: "group",
    },
    sessionCtx: {
      Body: "",
      BodyStripped: "",
      ThreadHistoryBody: "Earlier message in this thread",
      MediaPath: "/tmp/input.png",
      Provider: "slack",
      ChatType: "group",
      OriginatingChannel: "slack",
      OriginatingTo: "C123",
    },
    cfg: { session: {}, channels: {}, agents: { defaults: {} } },
    agentId: "default",
    agentDir: "/tmp/agent",
    agentCfg: {},
    sessionCfg: {},
    commandAuthorized: true,
    command: {
      isAuthorizedSender: true,
      abortKey: "session-key",
      ownerList: [],
      senderIsOwner: false,
    } as never,
    commandSource: "",
    allowTextCommands: true,
    directives: {
      hasThinkDirective: false,
      thinkLevel: undefined,
    } as never,
    defaultActivation: "always",
    resolvedThinkLevel: "high",
    resolvedVerboseLevel: "off",
    resolvedReasoningLevel: "off",
    resolvedElevatedLevel: "off",
    elevatedEnabled: false,
    elevatedAllowed: false,
    blockStreamingEnabled: false,
    resolvedBlockStreamingBreak: "message_end",
    modelState: {
      resolveDefaultThinkingLevel: async () => "medium",
    } as never,
    provider: "anthropic",
    model: "claude-opus-4-1",
    typing: {
      onReplyStart: mock:fn().mockResolvedValue(undefined),
      cleanup: mock:fn(),
    } as never,
    defaultProvider: "anthropic",
    defaultModel: "claude-opus-4-1",
    timeoutMs: 30_000,
    isNewSession: true,
    resetTriggered: false,
    systemSent: true,
    sessionKey: "session-key",
    workspaceDir: "/tmp/workspace",
    abortedLastRun: false,
    ...overrides,
  };
}

(deftest-group "runPreparedReply media-only handling", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "allows media-only prompts and preserves thread context in queued followups", async () => {
    const result = await runPreparedReply(baseParams());
    (expect* result).is-equal({ text: "ok" });

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call).is-truthy();
    (expect* call?.followupRun.prompt).contains("[Thread history - for context]");
    (expect* call?.followupRun.prompt).contains("Earlier message in this thread");
    (expect* call?.followupRun.prompt).contains("[User sent media without caption]");
  });

  (deftest "keeps thread history context on follow-up turns", async () => {
    const result = await runPreparedReply(
      baseParams({
        isNewSession: false,
      }),
    );
    (expect* result).is-equal({ text: "ok" });

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call).is-truthy();
    (expect* call?.followupRun.prompt).contains("[Thread history - for context]");
    (expect* call?.followupRun.prompt).contains("Earlier message in this thread");
  });

  (deftest "returns the empty-body reply when there is no text and no media", async () => {
    const result = await runPreparedReply(
      baseParams({
        ctx: {
          Body: "",
          RawBody: "",
          CommandBody: "",
        },
        sessionCtx: {
          Body: "",
          BodyStripped: "",
          Provider: "slack",
        },
      }),
    );

    (expect* result).is-equal({
      text: "I didn't receive any text in your message. Please resend or add a caption.",
    });
    (expect* mock:mocked(runReplyAgent)).not.toHaveBeenCalled();
  });

  (deftest "omits auth key labels from /new and /reset confirmation messages", async () => {
    await runPreparedReply(
      baseParams({
        resetTriggered: true,
      }),
    );

    const resetNoticeCall = mock:mocked(routeReply).mock.calls[0]?.[0] as
      | { payload?: { text?: string } }
      | undefined;
    (expect* resetNoticeCall?.payload?.text).contains("✅ New session started · model:");
    (expect* resetNoticeCall?.payload?.text).not.contains("🔑");
    (expect* resetNoticeCall?.payload?.text).not.contains("api-key");
    (expect* resetNoticeCall?.payload?.text).not.contains("env:");
  });

  (deftest "skips reset notice when only webchat fallback routing is available", async () => {
    await runPreparedReply(
      baseParams({
        resetTriggered: true,
        ctx: {
          Body: "",
          RawBody: "",
          CommandBody: "",
          ThreadHistoryBody: "Earlier message in this thread",
          OriginatingChannel: undefined,
          OriginatingTo: undefined,
          ChatType: "group",
        },
        command: {
          isAuthorizedSender: true,
          abortKey: "session-key",
          ownerList: [],
          senderIsOwner: false,
          channel: "webchat",
          from: undefined,
          to: undefined,
        } as never,
      }),
    );

    (expect* mock:mocked(routeReply)).not.toHaveBeenCalled();
  });

  (deftest "uses inbound origin channel for run messageProvider", async () => {
    await runPreparedReply(
      baseParams({
        ctx: {
          Body: "",
          RawBody: "",
          CommandBody: "",
          ThreadHistoryBody: "Earlier message in this thread",
          OriginatingChannel: "webchat",
          OriginatingTo: "session:abc",
          ChatType: "group",
        },
        sessionCtx: {
          Body: "",
          BodyStripped: "",
          ThreadHistoryBody: "Earlier message in this thread",
          MediaPath: "/tmp/input.png",
          Provider: "telegram",
          ChatType: "group",
          OriginatingChannel: "telegram",
          OriginatingTo: "telegram:123",
        },
      }),
    );

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call?.followupRun.run.messageProvider).is("webchat");
  });

  (deftest "prefers Provider over Surface when origin channel is missing", async () => {
    await runPreparedReply(
      baseParams({
        ctx: {
          Body: "",
          RawBody: "",
          CommandBody: "",
          ThreadHistoryBody: "Earlier message in this thread",
          OriginatingChannel: undefined,
          OriginatingTo: undefined,
          Provider: "feishu",
          Surface: "webchat",
          ChatType: "group",
        },
        sessionCtx: {
          Body: "",
          BodyStripped: "",
          ThreadHistoryBody: "Earlier message in this thread",
          MediaPath: "/tmp/input.png",
          Provider: "webchat",
          ChatType: "group",
          OriginatingChannel: undefined,
          OriginatingTo: undefined,
        },
      }),
    );

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call?.followupRun.run.messageProvider).is("feishu");
  });

  (deftest "passes suppressTyping through typing mode resolution", async () => {
    await runPreparedReply(
      baseParams({
        opts: {
          suppressTyping: true,
        },
      }),
    );

    const call = mock:mocked(resolveTypingMode).mock.calls[0]?.[0] as
      | { suppressTyping?: boolean }
      | undefined;
    (expect* call?.suppressTyping).is(true);
  });

  (deftest "routes queued system events into user prompt text, not system prompt context", async () => {
    mock:mocked(drainFormattedSystemEvents).mockResolvedValueOnce("System: [t] Model switched.");

    await runPreparedReply(baseParams());

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call).is-truthy();
    (expect* call?.commandBody).contains("System: [t] Model switched.");
    (expect* call?.followupRun.run.extraSystemPrompt ?? "").not.contains("Runtime System Events");
  });

  (deftest "preserves first-token think hint when system events are prepended", async () => {
    // drainFormattedSystemEvents returns just the events block; the caller prepends it.
    // The hint must be extracted from the user body BEFORE prepending, so "System:"
    // does not shadow the low|medium|high shorthand.
    mock:mocked(drainFormattedSystemEvents).mockResolvedValueOnce("System: [t] Node connected.");

    await runPreparedReply(
      baseParams({
        ctx: { Body: "low tell me about cats", RawBody: "low tell me about cats" },
        sessionCtx: { Body: "low tell me about cats", BodyStripped: "low tell me about cats" },
        resolvedThinkLevel: undefined,
      }),
    );

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call).is-truthy();
    // Think hint extracted before events arrived — level must be "low", not the model default.
    (expect* call?.followupRun.run.thinkLevel).is("low");
    // The stripped user text (no "low" token) must still appear after the event block.
    (expect* call?.commandBody).contains("tell me about cats");
    (expect* call?.commandBody).not.toMatch(/^low\b/);
    // System events are still present in the body.
    (expect* call?.commandBody).contains("System: [t] Node connected.");
  });

  (deftest "carries system events into followupRun.prompt for deferred turns", async () => {
    // drainFormattedSystemEvents returns the events block; the caller prepends it to
    // effectiveBaseBody for the queue path so deferred turns see events.
    mock:mocked(drainFormattedSystemEvents).mockResolvedValueOnce("System: [t] Node connected.");

    await runPreparedReply(baseParams());

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call).is-truthy();
    (expect* call?.followupRun.prompt).contains("System: [t] Node connected.");
  });

  (deftest "does not strip think-hint token from deferred queue body", async () => {
    // In steer mode the inferred thinkLevel is never consumed, so the first token
    // must not be stripped from the queue/steer body (followupRun.prompt).
    mock:mocked(drainFormattedSystemEvents).mockResolvedValueOnce(undefined);

    await runPreparedReply(
      baseParams({
        ctx: { Body: "low steer this conversation", RawBody: "low steer this conversation" },
        sessionCtx: {
          Body: "low steer this conversation",
          BodyStripped: "low steer this conversation",
        },
        resolvedThinkLevel: undefined,
      }),
    );

    const call = mock:mocked(runReplyAgent).mock.calls[0]?.[0];
    (expect* call).is-truthy();
    // Queue body (used by steer mode) must keep the full original text.
    (expect* call?.followupRun.prompt).contains("low steer this conversation");
  });
});
