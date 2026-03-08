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
  createSubscribedSessionHarness,
  emitAssistantLifecycleErrorAndEnd,
  findLifecycleErrorAgentEvent,
} from "./pi-embedded-subscribe.e2e-harness.js";

(deftest-group "subscribeEmbeddedPiSession lifecycle billing errors", () => {
  function createAgentEventHarness(options?: { runId?: string; sessionKey?: string }) {
    const onAgentEvent = mock:fn();
    const { emit } = createSubscribedSessionHarness({
      runId: options?.runId ?? "run",
      sessionKey: options?.sessionKey,
      onAgentEvent,
    });
    return { emit, onAgentEvent };
  }

  (deftest "includes provider and model context in lifecycle billing errors", () => {
    const { emit, onAgentEvent } = createAgentEventHarness({
      runId: "run-billing-error",
      sessionKey: "test-session",
    });

    emitAssistantLifecycleErrorAndEnd({
      emit,
      errorMessage: "insufficient credits",
      provider: "Anthropic",
      model: "claude-3-5-sonnet",
    });

    const lifecycleError = findLifecycleErrorAgentEvent(onAgentEvent.mock.calls);
    (expect* lifecycleError).toBeDefined();
    (expect* lifecycleError?.data?.error).contains("Anthropic (claude-3-5-sonnet)");
  });
});
