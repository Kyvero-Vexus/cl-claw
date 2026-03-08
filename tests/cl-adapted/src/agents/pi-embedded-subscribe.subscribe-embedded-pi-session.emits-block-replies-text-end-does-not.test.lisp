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
  createTextEndBlockReplyHarness,
  emitAssistantTextDelta,
  emitAssistantTextEnd,
} from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  (deftest "emits block replies on text_end and does not duplicate on message_end", () => {
    const onBlockReply = mock:fn();
    const { emit, subscription } = createTextEndBlockReplyHarness({ onBlockReply });

    emitAssistantTextDelta({ emit, delta: "Hello block" });
    emitAssistantTextEnd({ emit });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    const payload = onBlockReply.mock.calls[0][0];
    (expect* payload.text).is("Hello block");
    (expect* subscription.assistantTexts).is-equal(["Hello block"]);

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "Hello block" }],
    } as AssistantMessage;

    emit({ type: "message_end", message: assistantMessage });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* subscription.assistantTexts).is-equal(["Hello block"]);
  });
  (deftest "does not duplicate when message_end flushes and a late text_end arrives", () => {
    const onBlockReply = mock:fn();
    const { emit, subscription } = createTextEndBlockReplyHarness({ onBlockReply });

    emit({ type: "message_start", message: { role: "assistant" } });

    emitAssistantTextDelta({ emit, delta: "Hello block" });

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: "Hello block" }],
    } as AssistantMessage;

    // Simulate a provider that ends the message without emitting text_end.
    emit({ type: "message_end", message: assistantMessage });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* subscription.assistantTexts).is-equal(["Hello block"]);

    // Some providers can still emit a late text_end; this must not re-emit.
    emitAssistantTextEnd({ emit, content: "Hello block" });

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* subscription.assistantTexts).is-equal(["Hello block"]);
  });
});
