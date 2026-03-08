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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  createSubscribedSessionHarness,
  emitAssistantTextDelta,
  emitAssistantTextEnd,
  emitMessageStartAndEndForAssistantText,
} from "./pi-embedded-subscribe.e2e-harness.js";

const waitForAsyncCallbacks = async () => {
  await Promise.resolve();
  await new Promise((resolve) => setTimeout(resolve, 0));
};

(deftest-group "subscribeEmbeddedPiSession block reply rejections", () => {
  const unhandledRejections: unknown[] = [];
  const onUnhandledRejection = (reason: unknown) => {
    unhandledRejections.push(reason);
  };

  afterEach(() => {
    process.off("unhandledRejection", onUnhandledRejection);
    unhandledRejections.length = 0;
  });

  (deftest "contains rejected async text_end block replies", async () => {
    process.on("unhandledRejection", onUnhandledRejection);
    const onBlockReply = mock:fn().mockRejectedValue(new Error("boom"));
    const { emit } = createSubscribedSessionHarness({
      runId: "run",
      onBlockReply,
      blockReplyBreak: "text_end",
    });

    emitAssistantTextDelta({ emit, delta: "Hello block" });
    emitAssistantTextEnd({ emit });
    await waitForAsyncCallbacks();

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* unhandledRejections).has-length(0);
  });

  (deftest "contains rejected async message_end block replies", async () => {
    process.on("unhandledRejection", onUnhandledRejection);
    const onBlockReply = mock:fn().mockRejectedValue(new Error("boom"));
    const { emit } = createSubscribedSessionHarness({
      runId: "run",
      onBlockReply,
      blockReplyBreak: "message_end",
    });

    emitMessageStartAndEndForAssistantText({ emit, text: "Hello block" });
    await waitForAsyncCallbacks();

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* unhandledRejections).has-length(0);
  });
});
