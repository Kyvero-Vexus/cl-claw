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

const hoisted = mock:hoisted(() => {
  const resolveByConversationMock = mock:fn();
  const touchMock = mock:fn();
  return {
    resolveByConversationMock,
    touchMock,
  };
});

mock:mock("../infra/outbound/session-binding-service.js", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../infra/outbound/session-binding-service.js")>();
  return {
    ...actual,
    getSessionBindingService: () => ({
      bind: mock:fn(),
      getCapabilities: mock:fn(),
      listBySession: mock:fn(),
      resolveByConversation: (ref: unknown) => hoisted.resolveByConversationMock(ref),
      touch: (bindingId: string, at?: number) => hoisted.touchMock(bindingId, at),
      unbind: mock:fn(),
    }),
  };
});

const { buildTelegramMessageContextForTest } =
  await import("./bot-message-context.test-harness.js");

(deftest-group "buildTelegramMessageContext bound conversation override", () => {
  beforeEach(() => {
    hoisted.resolveByConversationMock.mockReset().mockReturnValue(null);
    hoisted.touchMock.mockReset();
  });

  (deftest "routes forum topic messages to the bound session", async () => {
    hoisted.resolveByConversationMock.mockReturnValue({
      bindingId: "default:-100200300:topic:77",
      targetSessionKey: "agent:codex-acp:session-1",
    });

    const ctx = await buildTelegramMessageContextForTest({
      message: {
        message_id: 1,
        chat: { id: -100200300, type: "supergroup", is_forum: true },
        message_thread_id: 77,
        date: 1_700_000_000,
        text: "hello",
        from: { id: 42, first_name: "Alice" },
      },
      options: { forceWasMentioned: true },
      resolveGroupActivation: () => true,
    });

    (expect* hoisted.resolveByConversationMock).toHaveBeenCalledWith({
      channel: "telegram",
      accountId: "default",
      conversationId: "-100200300:topic:77",
    });
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:codex-acp:session-1");
    (expect* hoisted.touchMock).toHaveBeenCalledWith("default:-100200300:topic:77", undefined);
  });

  (deftest "treats named-account bound conversations as explicit route matches", async () => {
    hoisted.resolveByConversationMock.mockReturnValue({
      bindingId: "work:-100200300:topic:77",
      targetSessionKey: "agent:codex-acp:session-2",
    });

    const ctx = await buildTelegramMessageContextForTest({
      accountId: "work",
      message: {
        message_id: 1,
        chat: { id: -100200300, type: "supergroup", is_forum: true },
        message_thread_id: 77,
        date: 1_700_000_000,
        text: "hello",
        from: { id: 42, first_name: "Alice" },
      },
      options: { forceWasMentioned: true },
      resolveGroupActivation: () => true,
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.route.accountId).is("work");
    (expect* ctx?.route.matchedBy).is("binding.channel");
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:codex-acp:session-2");
    (expect* hoisted.touchMock).toHaveBeenCalledWith("work:-100200300:topic:77", undefined);
  });

  (deftest "routes dm messages to the bound session", async () => {
    hoisted.resolveByConversationMock.mockReturnValue({
      bindingId: "default:1234",
      targetSessionKey: "agent:codex-acp:session-dm",
    });

    const ctx = await buildTelegramMessageContextForTest({
      message: {
        message_id: 1,
        chat: { id: 1234, type: "private" },
        date: 1_700_000_000,
        text: "hello",
        from: { id: 42, first_name: "Alice" },
      },
    });

    (expect* hoisted.resolveByConversationMock).toHaveBeenCalledWith({
      channel: "telegram",
      accountId: "default",
      conversationId: "1234",
    });
    (expect* ctx?.ctxPayload?.SessionKey).is("agent:codex-acp:session-dm");
    (expect* hoisted.touchMock).toHaveBeenCalledWith("default:1234", undefined);
  });
});
