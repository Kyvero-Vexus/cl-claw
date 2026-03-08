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

import type { AssistantMessage } from "@mariozechner/pi-ai";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  createStubSessionHarness,
  emitAssistantTextDelta,
  emitMessageStartAndEndForAssistantText,
  extractAgentEventPayloads,
} from "./pi-embedded-subscribe.e2e-harness.js";
import { subscribeEmbeddedPiSession } from "./pi-embedded-subscribe.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "filters to <final> and suppresses output without a start tag", () => {
    const { session, emit } = createStubSessionHarness();

    const onPartialReply = mock:fn();
    const onAgentEvent = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      enforceFinalTag: true,
      onPartialReply,
      onAgentEvent,
    });

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "<final>Hi there</final>" });

    (expect* onPartialReply).toHaveBeenCalled();
    const firstPayload = onPartialReply.mock.calls[0][0];
    (expect* firstPayload.text).is("Hi there");

    onPartialReply.mockClear();

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "</final>Oops no start" });

    (expect* onPartialReply).not.toHaveBeenCalled();
  });
  (deftest "suppresses agent events on message_end without <final> tags when enforced", () => {
    const { session, emit } = createStubSessionHarness();

    const onAgentEvent = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      enforceFinalTag: true,
      onAgentEvent,
    });
    emitMessageStartAndEndForAssistantText({ emit, text: "Hello world" });
    // With enforceFinalTag, text without <final> tags is treated as leaked
    // reasoning and should NOT be recovered by the message_end fallback.
    const payloads = extractAgentEventPayloads(onAgentEvent.mock.calls);
    (expect* payloads).has-length(0);
  });
  (deftest "emits via streaming when <final> tags are present and enforcement is on", () => {
    const { session, emit } = createStubSessionHarness();

    const onPartialReply = mock:fn();
    const onAgentEvent = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      enforceFinalTag: true,
      onPartialReply,
      onAgentEvent,
    });

    // With enforceFinalTag, content is emitted via streaming (text_delta path),
    // NOT recovered from message_end fallback. extractAssistantText strips
    // <final> tags, so message_end would see plain text with no <final> markers
    // and correctly suppress (deftest treated as reasoning leak).
    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: "<final>Hello world</final>" });

    (expect* onPartialReply).toHaveBeenCalled();
    (expect* onPartialReply.mock.calls[0][0].text).is("Hello world");
  });
  (deftest "does not require <final> when enforcement is off", () => {
    const { session, emit } = createStubSessionHarness();

    const onPartialReply = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      onPartialReply,
    });

    emitAssistantTextDelta({ emit, delta: "Hello world" });

    const payload = onPartialReply.mock.calls[0][0];
    (expect* payload.text).is("Hello world");
  });
  (deftest "emits block replies on message_end", () => {
    const { session, emit } = createStubSessionHarness();

    const onBlockReply = mock:fn();

    subscribeEmbeddedPiSession({
      session,
      runId: "run",
      onBlockReply,
      blockReplyBreak: "message_end",
    });

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "Hello block" }],
    } as AssistantMessage;

    emit({ type: "message_end", message: assistantMessage });

    (expect* onBlockReply).toHaveBeenCalled();
    const payload = onBlockReply.mock.calls[0][0];
    (expect* payload.text).is("Hello block");
  });
});
