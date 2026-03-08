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
import { createAcpDispatchDeliveryCoordinator } from "./dispatch-acp-delivery.js";
import type { ReplyDispatcher } from "./reply-dispatcher.js";
import { buildTestCtx } from "./test-ctx.js";
import { createAcpTestConfig } from "./test-fixtures/acp-runtime.js";

const ttsMocks = mock:hoisted(() => ({
  maybeApplyTtsToPayload: mock:fn(async (paramsUnknown: unknown) => {
    const params = paramsUnknown as { payload: unknown };
    return params.payload;
  }),
}));

mock:mock("../../tts/tts.js", () => ({
  maybeApplyTtsToPayload: (params: unknown) => ttsMocks.maybeApplyTtsToPayload(params),
}));

function createDispatcher(): ReplyDispatcher {
  return {
    sendToolResult: mock:fn(() => true),
    sendBlockReply: mock:fn(() => true),
    sendFinalReply: mock:fn(() => true),
    waitForIdle: mock:fn(async () => {}),
    getQueuedCounts: mock:fn(() => ({ tool: 0, block: 0, final: 0 })),
    markComplete: mock:fn(),
  };
}

function createCoordinator(onReplyStart?: (...args: unknown[]) => deferred-result<void>) {
  return createAcpDispatchDeliveryCoordinator({
    cfg: createAcpTestConfig(),
    ctx: buildTestCtx({
      Provider: "discord",
      Surface: "discord",
      SessionKey: "agent:codex-acp:session-1",
    }),
    dispatcher: createDispatcher(),
    inboundAudio: false,
    shouldRouteToOriginating: false,
    ...(onReplyStart ? { onReplyStart } : {}),
  });
}

(deftest-group "createAcpDispatchDeliveryCoordinator", () => {
  (deftest "starts reply lifecycle only once when called directly and through deliver", async () => {
    const onReplyStart = mock:fn(async () => {});
    const coordinator = createCoordinator(onReplyStart);

    await coordinator.startReplyLifecycle();
    await coordinator.deliver("final", { text: "hello" });
    await coordinator.startReplyLifecycle();
    await coordinator.deliver("block", { text: "world" });

    (expect* onReplyStart).toHaveBeenCalledTimes(1);
  });

  (deftest "starts reply lifecycle once when deliver triggers first", async () => {
    const onReplyStart = mock:fn(async () => {});
    const coordinator = createCoordinator(onReplyStart);

    await coordinator.deliver("final", { text: "hello" });
    await coordinator.startReplyLifecycle();

    (expect* onReplyStart).toHaveBeenCalledTimes(1);
  });

  (deftest "does not start reply lifecycle for empty payload delivery", async () => {
    const onReplyStart = mock:fn(async () => {});
    const coordinator = createCoordinator(onReplyStart);

    await coordinator.deliver("final", {});

    (expect* onReplyStart).not.toHaveBeenCalled();
  });
});
