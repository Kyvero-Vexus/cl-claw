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
  createTextEndBlockReplyHarness,
  emitAssistantTextDelta,
  emitAssistantTextEnd,
} from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession", () => {
  function setupTextEndSubscription() {
    const onBlockReply = mock:fn();
    const { emit, subscription } = createTextEndBlockReplyHarness({ onBlockReply });

    const emitDelta = (delta: string) => {
      emitAssistantTextDelta({ emit, delta });
    };

    const emitTextEnd = (content: string) => {
      emitAssistantTextEnd({ emit, content });
    };

    return { onBlockReply, subscription, emitDelta, emitTextEnd };
  }

  it.each([
    {
      name: "does not append when text_end content is a prefix of deltas",
      delta: "Hello world",
      content: "Hello",
      expected: "Hello world",
    },
    {
      name: "does not append when text_end content is already contained",
      delta: "Hello world",
      content: "world",
      expected: "Hello world",
    },
    {
      name: "appends suffix when text_end content extends deltas",
      delta: "Hello",
      content: "Hello world",
      expected: "Hello world",
    },
  ])("$name", ({ delta, content, expected }) => {
    const { onBlockReply, subscription, emitDelta, emitTextEnd } = setupTextEndSubscription();

    emitDelta(delta);
    emitTextEnd(content);

    (expect* onBlockReply).toHaveBeenCalledTimes(1);
    (expect* subscription.assistantTexts).is-equal([expected]);
  });
});
