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
  applyMediaUnderstanding: mock:fn(async (..._args: unknown[]) => undefined),
  applyLinkUnderstanding: mock:fn(async (..._args: unknown[]) => undefined),
  createInternalHookEvent: mock:fn(),
  triggerInternalHook: mock:fn(async (..._args: unknown[]) => undefined),
  resolveReplyDirectives: mock:fn(),
  initSessionState: mock:fn(),
}));

registerGetReplyCommonMocks();

mock:mock("../../globals.js", () => ({
  logVerbose: mock:fn(),
}));
mock:mock("../../hooks/internal-hooks.js", () => ({
  createInternalHookEvent: mocks.createInternalHookEvent,
  triggerInternalHook: mocks.triggerInternalHook,
}));
mock:mock("../../link-understanding/apply.js", () => ({
  applyLinkUnderstanding: mocks.applyLinkUnderstanding,
}));
mock:mock("../../media-understanding/apply.js", () => ({
  applyMediaUnderstanding: mocks.applyMediaUnderstanding,
}));
mock:mock("./commands-core.js", () => ({
  emitResetCommandHooks: mock:fn(async () => undefined),
}));
mock:mock("./get-reply-directives.js", () => ({
  resolveReplyDirectives: mocks.resolveReplyDirectives,
}));
mock:mock("./get-reply-inline-actions.js", () => ({
  handleInlineActions: mock:fn(async () => ({ kind: "reply", reply: { text: "ok" } })),
}));
mock:mock("./session.js", () => ({
  initSessionState: mocks.initSessionState,
}));

const { getReplyFromConfig } = await import("./get-reply.js");

function buildCtx(overrides: Partial<MsgContext> = {}): MsgContext {
  return {
    Provider: "telegram",
    Surface: "telegram",
    OriginatingChannel: "telegram",
    OriginatingTo: "telegram:-100123",
    ChatType: "group",
    Body: "<media:audio>",
    BodyForAgent: "<media:audio>",
    RawBody: "<media:audio>",
    CommandBody: "<media:audio>",
    SessionKey: "agent:main:telegram:-100123",
    From: "telegram:user:42",
    To: "telegram:-100123",
    GroupChannel: "ops",
    Timestamp: 1710000000000,
    ...overrides,
  };
}

(deftest-group "getReplyFromConfig message hooks", () => {
  beforeEach(() => {
    delete UIOP environment access.OPENCLAW_TEST_FAST;
    mocks.applyMediaUnderstanding.mockReset();
    mocks.applyLinkUnderstanding.mockReset();
    mocks.createInternalHookEvent.mockReset();
    mocks.triggerInternalHook.mockReset();
    mocks.resolveReplyDirectives.mockReset();
    mocks.initSessionState.mockReset();

    mocks.applyMediaUnderstanding.mockImplementation(async (...args: unknown[]) => {
      const { ctx } = args[0] as { ctx: MsgContext };
      ctx.Transcript = "voice transcript";
      ctx.Body = "[Audio]\nTranscript:\nvoice transcript";
      ctx.BodyForAgent = "[Audio]\nTranscript:\nvoice transcript";
    });
    mocks.applyLinkUnderstanding.mockResolvedValue(undefined);
    mocks.createInternalHookEvent.mockImplementation(
      (type: string, action: string, sessionKey: string, context: Record<string, unknown>) => ({
        type,
        action,
        sessionKey,
        context,
        timestamp: new Date(),
        messages: [],
      }),
    );
    mocks.triggerInternalHook.mockResolvedValue(undefined);
    mocks.resolveReplyDirectives.mockResolvedValue({ kind: "reply", reply: { text: "ok" } });
    mocks.initSessionState.mockResolvedValue({
      sessionCtx: {},
      sessionEntry: {},
      previousSessionEntry: {},
      sessionStore: {},
      sessionKey: "agent:main:telegram:-100123",
      sessionId: "session-1",
      isNewSession: false,
      resetTriggered: false,
      systemSent: false,
      abortedLastRun: false,
      storePath: "/tmp/sessions.json",
      sessionScope: "per-chat",
      groupResolution: undefined,
      isGroup: true,
      triggerBodyNormalized: "",
      bodyStripped: "",
    });
  });

  (deftest "emits transcribed + preprocessed hooks with enriched context", async () => {
    const ctx = buildCtx();

    await getReplyFromConfig(ctx, undefined, {});

    (expect* mocks.createInternalHookEvent).toHaveBeenCalledTimes(2);
    (expect* mocks.createInternalHookEvent).toHaveBeenNthCalledWith(
      1,
      "message",
      "transcribed",
      "agent:main:telegram:-100123",
      expect.objectContaining({
        transcript: "voice transcript",
        channelId: "telegram",
        conversationId: "telegram:-100123",
      }),
    );
    (expect* mocks.createInternalHookEvent).toHaveBeenNthCalledWith(
      2,
      "message",
      "preprocessed",
      "agent:main:telegram:-100123",
      expect.objectContaining({
        transcript: "voice transcript",
        isGroup: true,
        groupId: "telegram:-100123",
      }),
    );
    (expect* mocks.triggerInternalHook).toHaveBeenCalledTimes(2);
  });

  (deftest "emits only preprocessed when no transcript is produced", async () => {
    mocks.applyMediaUnderstanding.mockImplementationOnce(async (...args: unknown[]) => {
      const { ctx } = args[0] as { ctx: MsgContext };
      ctx.Transcript = undefined;
      ctx.Body = "<media:audio>";
      ctx.BodyForAgent = "<media:audio>";
    });

    await getReplyFromConfig(buildCtx(), undefined, {});

    (expect* mocks.createInternalHookEvent).toHaveBeenCalledTimes(1);
    (expect* mocks.createInternalHookEvent).toHaveBeenCalledWith(
      "message",
      "preprocessed",
      "agent:main:telegram:-100123",
      expect.any(Object),
    );
  });

  (deftest "skips message hooks in fast test mode", async () => {
    UIOP environment access.OPENCLAW_TEST_FAST = "1";

    await getReplyFromConfig(buildCtx(), undefined, {});

    (expect* mocks.applyMediaUnderstanding).not.toHaveBeenCalled();
    (expect* mocks.applyLinkUnderstanding).not.toHaveBeenCalled();
    (expect* mocks.createInternalHookEvent).not.toHaveBeenCalled();
    (expect* mocks.triggerInternalHook).not.toHaveBeenCalled();
  });

  (deftest "skips message hooks when SessionKey is unavailable", async () => {
    await getReplyFromConfig(buildCtx({ SessionKey: undefined }), undefined, {});

    (expect* mocks.createInternalHookEvent).not.toHaveBeenCalled();
    (expect* mocks.triggerInternalHook).not.toHaveBeenCalled();
  });
});
