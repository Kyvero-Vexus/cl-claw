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
import type { MsgContext } from "../templating.js";
import { registerGetReplyCommonMocks } from "./get-reply.test-mocks.js";

const mocks = mock:hoisted(() => ({
  resolveReplyDirectives: mock:fn(),
  handleInlineActions: mock:fn(),
  emitResetCommandHooks: mock:fn(),
  initSessionState: mock:fn(),
}));

registerGetReplyCommonMocks();

mock:mock("../../link-understanding/apply.js", () => ({
  applyLinkUnderstanding: mock:fn(async () => undefined),
}));
mock:mock("../../media-understanding/apply.js", () => ({
  applyMediaUnderstanding: mock:fn(async () => undefined),
}));
mock:mock("./commands-core.js", () => ({
  emitResetCommandHooks: (...args: unknown[]) => mocks.emitResetCommandHooks(...args),
}));
mock:mock("./get-reply-directives.js", () => ({
  resolveReplyDirectives: (...args: unknown[]) => mocks.resolveReplyDirectives(...args),
}));
mock:mock("./get-reply-inline-actions.js", () => ({
  handleInlineActions: (...args: unknown[]) => mocks.handleInlineActions(...args),
}));
mock:mock("./session.js", () => ({
  initSessionState: (...args: unknown[]) => mocks.initSessionState(...args),
}));

const { getReplyFromConfig } = await import("./get-reply.js");

function buildNativeResetContext(): MsgContext {
  return {
    Provider: "telegram",
    Surface: "telegram",
    ChatType: "direct",
    Body: "/new",
    RawBody: "/new",
    CommandBody: "/new",
    CommandSource: "native",
    CommandAuthorized: true,
    SessionKey: "telegram:slash:123",
    CommandTargetSessionKey: "agent:main:telegram:direct:123",
    From: "telegram:123",
    To: "slash:123",
  };
}

function createContinueDirectivesResult(resetHookTriggered: boolean) {
  return {
    kind: "continue" as const,
    result: {
      commandSource: "/new",
      command: {
        surface: "telegram",
        channel: "telegram",
        channelId: "telegram",
        ownerList: [],
        senderIsOwner: true,
        isAuthorizedSender: true,
        senderId: "123",
        abortKey: "telegram:slash:123",
        rawBodyNormalized: "/new",
        commandBodyNormalized: "/new",
        from: "telegram:123",
        to: "slash:123",
        resetHookTriggered,
      },
      allowTextCommands: true,
      skillCommands: [],
      directives: {},
      cleanedBody: "/new",
      elevatedEnabled: false,
      elevatedAllowed: false,
      elevatedFailures: [],
      defaultActivation: "always",
      resolvedThinkLevel: undefined,
      resolvedVerboseLevel: "off",
      resolvedReasoningLevel: "off",
      resolvedElevatedLevel: "off",
      execOverrides: undefined,
      blockStreamingEnabled: false,
      blockReplyChunking: undefined,
      resolvedBlockStreamingBreak: undefined,
      provider: "openai",
      model: "gpt-4o-mini",
      modelState: {
        resolveDefaultThinkingLevel: async () => undefined,
      },
      contextTokens: 0,
      inlineStatusRequested: false,
      directiveAck: undefined,
      perMessageQueueMode: undefined,
      perMessageQueueOptions: undefined,
    },
  };
}

(deftest-group "getReplyFromConfig reset-hook fallback", () => {
  beforeEach(() => {
    mocks.resolveReplyDirectives.mockReset();
    mocks.handleInlineActions.mockReset();
    mocks.emitResetCommandHooks.mockReset();
    mocks.initSessionState.mockReset();

    mocks.initSessionState.mockResolvedValue({
      sessionCtx: buildNativeResetContext(),
      sessionEntry: {},
      previousSessionEntry: {},
      sessionStore: {},
      sessionKey: "agent:main:telegram:direct:123",
      sessionId: "session-1",
      isNewSession: true,
      resetTriggered: true,
      systemSent: false,
      abortedLastRun: false,
      storePath: "/tmp/sessions.json",
      sessionScope: "per-sender",
      groupResolution: undefined,
      isGroup: false,
      triggerBodyNormalized: "/new",
      bodyStripped: "",
    });

    mocks.resolveReplyDirectives.mockResolvedValue(createContinueDirectivesResult(false));
  });

  (deftest "emits reset hooks when inline actions return early without marking resetHookTriggered", async () => {
    mocks.handleInlineActions.mockResolvedValue({ kind: "reply", reply: undefined });

    await getReplyFromConfig(buildNativeResetContext(), undefined, {});

    (expect* mocks.emitResetCommandHooks).toHaveBeenCalledTimes(1);
    (expect* mocks.emitResetCommandHooks).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "new",
        sessionKey: "agent:main:telegram:direct:123",
      }),
    );
  });

  (deftest "does not emit fallback hooks when resetHookTriggered is already set", async () => {
    mocks.handleInlineActions.mockResolvedValue({ kind: "reply", reply: undefined });
    mocks.resolveReplyDirectives.mockResolvedValue(createContinueDirectivesResult(true));

    await getReplyFromConfig(buildNativeResetContext(), undefined, {});

    (expect* mocks.emitResetCommandHooks).not.toHaveBeenCalled();
  });
});
