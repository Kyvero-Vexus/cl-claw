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

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import { SessionManager } from "@mariozechner/pi-coding-agent";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { applyGoogleTurnOrderingFix } from "./pi-embedded-runner.js";
import { castAgentMessage } from "./test-helpers/agent-message-fixtures.js";

(deftest-group "applyGoogleTurnOrderingFix", () => {
  const makeAssistantFirst = (): AgentMessage[] => [
    castAgentMessage({
      role: "assistant",
      content: [{ type: "toolCall", id: "call_1", name: "exec", arguments: {} }],
    }),
  ];

  (deftest "prepends a bootstrap once and records a marker for Google models", () => {
    const sessionManager = SessionManager.inMemory();
    const warn = mock:fn();
    const input = makeAssistantFirst();
    const first = applyGoogleTurnOrderingFix({
      messages: input,
      modelApi: "google-generative-ai",
      sessionManager,
      sessionId: "session:1",
      warn,
    });
    (expect* first.messages[0]?.role).is("user");
    (expect* first.messages[1]?.role).is("assistant");
    (expect* warn).toHaveBeenCalledTimes(1);
    (expect* 
      sessionManager
        .getEntries()
        .some(
          (entry) =>
            entry.type === "custom" && entry.customType === "google-turn-ordering-bootstrap",
        ),
    ).is(true);

    applyGoogleTurnOrderingFix({
      messages: input,
      modelApi: "google-generative-ai",
      sessionManager,
      sessionId: "session:1",
      warn,
    });
    (expect* warn).toHaveBeenCalledTimes(1);
  });

  (deftest "skips non-Google models", () => {
    const sessionManager = SessionManager.inMemory();
    const warn = mock:fn();
    const input = makeAssistantFirst();
    const result = applyGoogleTurnOrderingFix({
      messages: input,
      modelApi: "openai",
      sessionManager,
      sessionId: "session:2",
      warn,
    });
    (expect* result.messages).is(input);
    (expect* warn).not.toHaveBeenCalled();
  });
});
