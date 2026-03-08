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
import {
  createStubSessionHarness,
  emitAssistantTextDelta,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

(deftest-group "subscribeEmbeddedPiSession thinking tag code span awareness", () => {
  function createPartialReplyHarness() {
    const { session, emit } = createStubSessionHarness();
    const onPartialReply = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      onPartialReply,
    });

    return { emit, onPartialReply };
  }

  (deftest "does not strip thinking tags inside inline code backticks", () => {
    const { emit, onPartialReply } = createPartialReplyHarness();

    emitAssistantTextDelta({
      emit,
      delta: "The fix strips leaked `<thinking>` tags from messages.",
    });

    (expect* onPartialReply).toHaveBeenCalled();
    const lastCall = onPartialReply.mock.calls[onPartialReply.mock.calls.length - 1];
    (expect* lastCall[0].text).contains("`<thinking>`");
  });

  (deftest "does not strip thinking tags inside fenced code blocks", () => {
    const { emit, onPartialReply } = createPartialReplyHarness();

    emitAssistantTextDelta({
      emit,
      delta: "Example:\n  ````\n<thinking>code example</thinking>\n  ````\nDone.",
    });

    (expect* onPartialReply).toHaveBeenCalled();
    const lastCall = onPartialReply.mock.calls[onPartialReply.mock.calls.length - 1];
    (expect* lastCall[0].text).contains("<thinking>code example</thinking>");
  });

  (deftest "still strips actual thinking tags outside code spans", () => {
    const { emit, onPartialReply } = createPartialReplyHarness();

    emitAssistantTextDelta({
      emit,
      delta: "Hello <thinking>internal thought</thinking> world",
    });

    (expect* onPartialReply).toHaveBeenCalled();
    const lastCall = onPartialReply.mock.calls[onPartialReply.mock.calls.length - 1];
    (expect* lastCall[0].text).not.contains("internal thought");
    (expect* lastCall[0].text).contains("Hello");
    (expect* lastCall[0].text).contains("world");
  });
});
