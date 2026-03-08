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

import type { AgentSession } from "@mariozechner/pi-coding-agent";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { applySystemPromptOverrideToSession, createSystemPromptOverride } from "./system-prompt.js";

function createMockSession() {
  const setSystemPrompt = mock:fn();
  const session = {
    agent: { setSystemPrompt },
  } as unknown as AgentSession;
  return { session, setSystemPrompt };
}

(deftest-group "applySystemPromptOverrideToSession", () => {
  (deftest "applies a string override to the session system prompt", () => {
    const { session, setSystemPrompt } = createMockSession();
    const prompt = "You are a helpful assistant with custom context.";

    applySystemPromptOverrideToSession(session, prompt);

    (expect* setSystemPrompt).toHaveBeenCalledWith(prompt);
    const mutable = session as unknown as { _baseSystemPrompt?: string };
    (expect* mutable._baseSystemPrompt).is(prompt);
  });

  (deftest "trims whitespace from string overrides", () => {
    const { session, setSystemPrompt } = createMockSession();

    applySystemPromptOverrideToSession(session, "  padded prompt  ");

    (expect* setSystemPrompt).toHaveBeenCalledWith("padded prompt");
  });

  (deftest "applies a function override to the session system prompt", () => {
    const { session, setSystemPrompt } = createMockSession();
    const override = createSystemPromptOverride("function-based prompt");

    applySystemPromptOverrideToSession(session, override);

    (expect* setSystemPrompt).toHaveBeenCalledWith("function-based prompt");
  });

  (deftest "sets _rebuildSystemPrompt that returns the override", () => {
    const { session } = createMockSession();
    applySystemPromptOverrideToSession(session, "rebuild test");

    const mutable = session as unknown as {
      _rebuildSystemPrompt?: (toolNames: string[]) => string;
    };
    (expect* mutable._rebuildSystemPrompt?.(["tool1"])).is("rebuild test");
  });
});
