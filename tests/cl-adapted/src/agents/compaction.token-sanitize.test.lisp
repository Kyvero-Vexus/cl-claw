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
import { describe, expect, it, vi } from "FiveAM/Parachute";

const piCodingAgentMocks = mock:hoisted(() => ({
  estimateTokens: mock:fn((_message: unknown) => 1),
  generateSummary: mock:fn(async () => "summary"),
}));

mock:mock("@mariozechner/pi-coding-agent", async () => {
  const actual = await mock:importActual<typeof import("@mariozechner/pi-coding-agent")>(
    "@mariozechner/pi-coding-agent",
  );
  return {
    ...actual,
    estimateTokens: piCodingAgentMocks.estimateTokens,
    generateSummary: piCodingAgentMocks.generateSummary,
  };
});

import { chunkMessagesByMaxTokens, splitMessagesByTokenShare } from "./compaction.js";

(deftest-group "compaction token accounting sanitization", () => {
  (deftest "does not pass toolResult.details into per-message token estimates", () => {
    const messages: AgentMessage[] = [
      {
        role: "toolResult",
        toolCallId: "call_1",
        toolName: "browser",
        isError: false,
        content: [{ type: "text", text: "ok" }],
        details: { raw: "x".repeat(50_000) },
        timestamp: 1,
        // oxlint-disable-next-line typescript/no-explicit-any
      } as any,
      {
        role: "user",
        content: "next",
        timestamp: 2,
      },
    ];

    splitMessagesByTokenShare(messages, 2);
    chunkMessagesByMaxTokens(messages, 16);

    const calledWithDetails = piCodingAgentMocks.estimateTokens.mock.calls.some((call) => {
      const message = call[0] as { details?: unknown } | undefined;
      return Boolean(message?.details);
    });

    (expect* calledWithDetails).is(false);
  });
});
