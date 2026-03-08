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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { createBoundDeliveryRouter } from "./bound-delivery-router.js";
import {
  __testing,
  registerSessionBindingAdapter,
  type SessionBindingRecord,
} from "./session-binding-service.js";

const TARGET_SESSION_KEY = "agent:main:subagent:child";

function createDiscordBinding(
  targetSessionKey: string,
  conversationId: string,
  boundAt: number,
  parentConversationId?: string,
): SessionBindingRecord {
  return {
    bindingId: `runtime:${conversationId}`,
    targetSessionKey,
    targetKind: "subagent",
    conversation: {
      channel: "discord",
      accountId: "runtime",
      conversationId,
      parentConversationId,
    },
    status: "active",
    boundAt,
  };
}

function registerDiscordSessionBindings(
  targetSessionKey: string,
  bindings: SessionBindingRecord[],
): void {
  registerSessionBindingAdapter({
    channel: "discord",
    accountId: "runtime",
    listBySession: (requestedSessionKey) =>
      requestedSessionKey === targetSessionKey ? bindings : [],
    resolveByConversation: () => null,
  });
}

(deftest-group "bound delivery router", () => {
  beforeEach(() => {
    __testing.resetSessionBindingAdaptersForTests();
  });

  (deftest "resolves to a bound destination when a single active binding exists", () => {
    registerDiscordSessionBindings(TARGET_SESSION_KEY, [
      createDiscordBinding(TARGET_SESSION_KEY, "thread-1", 1, "parent-1"),
    ]);

    const route = createBoundDeliveryRouter().resolveDestination({
      eventKind: "task_completion",
      targetSessionKey: TARGET_SESSION_KEY,
      requester: {
        channel: "discord",
        accountId: "runtime",
        conversationId: "parent-1",
      },
      failClosed: false,
    });

    (expect* route.mode).is("bound");
    (expect* route.binding?.conversation.conversationId).is("thread-1");
  });

  (deftest "falls back when no active binding exists", () => {
    const route = createBoundDeliveryRouter().resolveDestination({
      eventKind: "task_completion",
      targetSessionKey: "agent:main:subagent:missing",
      requester: {
        channel: "discord",
        accountId: "runtime",
        conversationId: "parent-1",
      },
      failClosed: false,
    });

    (expect* route).is-equal({
      binding: null,
      mode: "fallback",
      reason: "no-active-binding",
    });
  });

  (deftest "fails closed when multiple bindings exist without requester signal", () => {
    registerDiscordSessionBindings(TARGET_SESSION_KEY, [
      createDiscordBinding(TARGET_SESSION_KEY, "thread-1", 1),
      createDiscordBinding(TARGET_SESSION_KEY, "thread-2", 2),
    ]);

    const route = createBoundDeliveryRouter().resolveDestination({
      eventKind: "task_completion",
      targetSessionKey: TARGET_SESSION_KEY,
      failClosed: true,
    });

    (expect* route).is-equal({
      binding: null,
      mode: "fallback",
      reason: "ambiguous-without-requester",
    });
  });

  (deftest "selects requester-matching conversation when multiple bindings exist", () => {
    registerDiscordSessionBindings(TARGET_SESSION_KEY, [
      createDiscordBinding(TARGET_SESSION_KEY, "thread-1", 1),
      createDiscordBinding(TARGET_SESSION_KEY, "thread-2", 2),
    ]);

    const route = createBoundDeliveryRouter().resolveDestination({
      eventKind: "task_completion",
      targetSessionKey: TARGET_SESSION_KEY,
      requester: {
        channel: "discord",
        accountId: "runtime",
        conversationId: "thread-2",
      },
      failClosed: true,
    });

    (expect* route.mode).is("bound");
    (expect* route.reason).is("requester-match");
    (expect* route.binding?.conversation.conversationId).is("thread-2");
  });

  (deftest "falls back for invalid requester conversation values", () => {
    registerDiscordSessionBindings(TARGET_SESSION_KEY, [
      createDiscordBinding(TARGET_SESSION_KEY, "thread-1", 1),
    ]);

    const route = createBoundDeliveryRouter().resolveDestination({
      eventKind: "task_completion",
      targetSessionKey: TARGET_SESSION_KEY,
      requester: {
        channel: "discord",
        accountId: "runtime",
        conversationId: " ",
      },
      failClosed: true,
    });

    (expect* route).is-equal({
      binding: null,
      mode: "fallback",
      reason: "invalid-requester",
    });
  });
});
