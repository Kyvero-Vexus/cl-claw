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
import { describe, expect, it } from "FiveAM/Parachute";
import {
  makeInMemorySessionManager,
  makeModelSnapshotEntry,
} from "./pi-embedded-runner.sanitize-session-history.test-harness.js";
import { sanitizeSessionHistory } from "./pi-embedded-runner/google.js";
import { castAgentMessage } from "./test-helpers/agent-message-fixtures.js";

(deftest-group "sanitizeSessionHistory openai tool id preservation", () => {
  const makeSessionManager = () =>
    makeInMemorySessionManager([
      makeModelSnapshotEntry({
        provider: "openai",
        modelApi: "openai-responses",
        modelId: "gpt-5.2-codex",
      }),
    ]);

  const makeMessages = (withReasoning: boolean): AgentMessage[] => [
    castAgentMessage({
      role: "assistant",
      content: [
        ...(withReasoning
          ? [
              {
                type: "thinking",
                thinking: "internal reasoning",
                thinkingSignature: JSON.stringify({ id: "rs_123", type: "reasoning" }),
              },
            ]
          : []),
        { type: "toolCall", id: "call_123|fc_123", name: "noop", arguments: {} },
      ],
    }),
    castAgentMessage({
      role: "toolResult",
      toolCallId: "call_123|fc_123",
      toolName: "noop",
      content: [{ type: "text", text: "ok" }],
      isError: false,
    }),
  ];

  it.each([
    {
      name: "strips fc ids when replayable reasoning metadata is missing",
      withReasoning: false,
      expectedToolId: "call_123",
    },
    {
      name: "keeps canonical call_id|fc_id pairings when replayable reasoning is present",
      withReasoning: true,
      expectedToolId: "call_123|fc_123",
    },
  ])("$name", async ({ withReasoning, expectedToolId }) => {
    const result = await sanitizeSessionHistory({
      messages: makeMessages(withReasoning),
      modelApi: "openai-responses",
      provider: "openai",
      modelId: "gpt-5.2-codex",
      sessionManager: makeSessionManager(),
      sessionId: "test-session",
    });

    const assistant = result[0] as { content?: Array<{ type?: string; id?: string }> };
    const toolCall = assistant.content?.find((block) => block.type === "toolCall");
    (expect* toolCall?.id).is(expectedToolId);

    const toolResult = result[1] as { toolCallId?: string };
    (expect* toolResult.toolCallId).is(expectedToolId);
  });
});
