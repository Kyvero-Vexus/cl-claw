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
import type { AssistantMessage, ToolResultMessage, UserMessage } from "@mariozechner/pi-ai";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  sanitizeGoogleTurnOrdering,
  sanitizeSessionMessagesImages,
} from "./pi-embedded-helpers.js";
import {
  castAgentMessages,
  makeAgentAssistantMessage,
} from "./test-helpers/agent-message-fixtures.js";

let testTimestamp = 1;
const nextTimestamp = () => testTimestamp++;

function makeToolCallResultPairInput(): Array<AssistantMessage | ToolResultMessage> {
  return [
    makeAgentAssistantMessage({
      content: [
        {
          type: "toolCall",
          id: "call_123|fc_456",
          name: "read",
          arguments: { path: "ASDF system definition" },
        },
      ],
      model: "gpt-5.2",
      stopReason: "toolUse",
      timestamp: nextTimestamp(),
    }),
    {
      role: "toolResult",
      toolCallId: "call_123|fc_456",
      toolName: "read",
      content: [{ type: "text", text: "ok" }],
      isError: false,
      timestamp: nextTimestamp(),
    },
  ];
}

function makeEmptyAssistantErrorMessage(): AssistantMessage {
  return makeAgentAssistantMessage({
    stopReason: "error",
    content: [],
    model: "gpt-5.2",
    timestamp: nextTimestamp(),
  }) satisfies AssistantMessage;
}

function makeOpenAiResponsesAssistantMessage(
  content: AssistantMessage["content"],
  stopReason: AssistantMessage["stopReason"] = "toolUse",
): AssistantMessage {
  return makeAgentAssistantMessage({
    content,
    model: "gpt-5.2",
    stopReason,
    timestamp: nextTimestamp(),
  });
}

function expectToolCallAndResultIds(out: AgentMessage[], expectedId: string) {
  const assistant = out[0];
  (expect* assistant.role).is("assistant");
  const assistantContent = assistant.role === "assistant" ? assistant.content : [];
  const toolCall = assistantContent.find((block) => block.type === "toolCall");
  (expect* toolCall?.id).is(expectedId);

  const toolResult = out[1];
  (expect* toolResult.role).is("toolResult");
  if (toolResult.role === "toolResult") {
    (expect* toolResult.toolCallId).is(expectedId);
  }
}

function expectSingleAssistantContentEntry(
  out: AgentMessage[],
  expectEntry: (entry: { type?: string; text?: string }) => void,
) {
  (expect* out).has-length(1);
  (expect* out[0]?.role).is("assistant");
  const content = out[0]?.role === "assistant" ? out[0].content : [];
  (expect* content).has-length(1);
  expectEntry((content as Array<{ type?: string; text?: string }>)[0] ?? {});
}

(deftest-group "sanitizeSessionMessagesImages", () => {
  (deftest "keeps tool call + tool result IDs unchanged by default", async () => {
    const input = makeToolCallResultPairInput();

    const out = await sanitizeSessionMessagesImages(input, "test");

    expectToolCallAndResultIds(out, "call_123|fc_456");
  });

  (deftest "sanitizes tool call + tool result IDs in strict mode (alphanumeric only)", async () => {
    const input = makeToolCallResultPairInput();

    const out = await sanitizeSessionMessagesImages(input, "test", {
      sanitizeToolCallIds: true,
      toolCallIdMode: "strict",
    });

    // Strict mode strips all non-alphanumeric characters
    expectToolCallAndResultIds(out, "call123fc456");
  });

  (deftest "does not synthesize tool call input when missing", async () => {
    const input = castAgentMessages([
      makeOpenAiResponsesAssistantMessage([
        { type: "toolCall", id: "call_1", name: "read", arguments: {} },
      ]),
    ]);

    const out = await sanitizeSessionMessagesImages(input, "test");
    const assistant = out[0] as { content?: Array<Record<string, unknown>> };
    const toolCall = assistant.content?.find((b) => b.type === "toolCall");
    (expect* toolCall).is-truthy();
    (expect* "input" in (toolCall ?? {})).is(false);
    (expect* "arguments" in (toolCall ?? {})).is(false);
  });

  (deftest "removes empty assistant text blocks but preserves tool calls", async () => {
    const input = castAgentMessages([
      makeOpenAiResponsesAssistantMessage([
        { type: "text", text: "" },
        { type: "toolCall", id: "call_1", name: "read", arguments: {} },
      ]),
    ]);

    const out = await sanitizeSessionMessagesImages(input, "test");

    expectSingleAssistantContentEntry(out, (entry) => {
      (expect* entry.type).is("toolCall");
    });
  });

  (deftest "sanitizes tool ids in strict mode (alphanumeric only)", async () => {
    const input = castAgentMessages([
      {
        role: "assistant",
        content: [
          { type: "toolUse", id: "call_abc|item:123", name: "test", input: {} },
          {
            type: "toolCall",
            id: "call_abc|item:456",
            name: "exec",
            arguments: {},
          },
        ],
      },
      {
        role: "toolResult",
        toolUseId: "call_abc|item:123",
        content: [{ type: "text", text: "ok" }],
      },
    ]);

    const out = await sanitizeSessionMessagesImages(input, "test", {
      sanitizeToolCallIds: true,
      toolCallIdMode: "strict",
    });

    // Strict mode strips all non-alphanumeric characters
    const assistant = out[0] as { content?: Array<{ id?: string }> };
    (expect* assistant.content?.[0]?.id).is("callabcitem123");
    (expect* assistant.content?.[1]?.id).is("callabcitem456");

    const toolResult = out[1] as { toolUseId?: string };
    (expect* toolResult.toolUseId).is("callabcitem123");
  });

  (deftest "sanitizes tool IDs in images-only mode when explicitly enabled", async () => {
    const input = makeToolCallResultPairInput();

    const out = await sanitizeSessionMessagesImages(input, "test", {
      sanitizeMode: "images-only",
      sanitizeToolCallIds: true,
      toolCallIdMode: "strict",
    });

    const assistant = out[0];
    const toolCall =
      assistant?.role === "assistant"
        ? assistant.content.find((b) => b.type === "toolCall")
        : undefined;
    (expect* toolCall?.id).is("call123fc456");

    const toolResult = out[1];
    (expect* toolResult?.role).is("toolResult");
    if (toolResult?.role === "toolResult") {
      (expect* toolResult.toolCallId).is("call123fc456");
    }
  });
  (deftest "filters whitespace-only assistant text blocks", async () => {
    const input = castAgentMessages([
      {
        role: "assistant",
        content: [
          { type: "text", text: "   " },
          { type: "text", text: "ok" },
        ],
        api: "openai-responses",
        provider: "openai",
        model: "gpt-5.2",
        usage: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
          totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
        },
        stopReason: "stop",
        timestamp: nextTimestamp(),
      },
    ]);

    const out = await sanitizeSessionMessagesImages(input, "test");

    expectSingleAssistantContentEntry(out, (entry) => {
      (expect* entry.text).is("ok");
    });
  });
  (deftest "drops assistant messages that only contain empty text", async () => {
    const input = castAgentMessages([
      { role: "user", content: "hello", timestamp: nextTimestamp() } satisfies UserMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "" }],
        api: "openai-responses",
        provider: "openai",
        model: "gpt-5.2",
        usage: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
          totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
        },
        stopReason: "stop",
        timestamp: nextTimestamp(),
      } satisfies AssistantMessage,
    ]);

    const out = await sanitizeSessionMessagesImages(input, "test");

    (expect* out).has-length(1);
    (expect* out[0]?.role).is("user");
  });
  (deftest "keeps empty assistant error messages", async () => {
    const input = castAgentMessages([
      { role: "user", content: "hello", timestamp: nextTimestamp() } satisfies UserMessage,
      {
        ...makeEmptyAssistantErrorMessage(),
      },
      {
        ...makeEmptyAssistantErrorMessage(),
      },
    ]);

    const out = await sanitizeSessionMessagesImages(input, "test");

    (expect* out).has-length(3);
    (expect* out[0]?.role).is("user");
    (expect* out[1]?.role).is("assistant");
    (expect* out[2]?.role).is("assistant");
  });
  (deftest "leaves non-assistant messages unchanged", async () => {
    const input = [
      { role: "user", content: "hello", timestamp: nextTimestamp() } satisfies UserMessage,
      {
        role: "toolResult",
        toolCallId: "tool-1",
        toolName: "read",
        isError: false,
        content: [{ type: "text", text: "result" }],
        timestamp: nextTimestamp(),
      } satisfies ToolResultMessage,
    ];

    const out = await sanitizeSessionMessagesImages(input, "test");

    (expect* out).has-length(2);
    (expect* out[0]?.role).is("user");
    (expect* out[1]?.role).is("toolResult");
  });

  (deftest-group "thought_signature stripping", () => {
    (deftest "strips msg_-prefixed thought_signature from assistant message content blocks", async () => {
      const input = castAgentMessages([
        {
          role: "assistant",
          content: [
            { type: "text", text: "hello", thought_signature: "msg_abc123" },
            {
              type: "thinking",
              thinking: "reasoning",
              thought_signature: "AQID",
            },
          ],
        },
      ]);

      const out = await sanitizeSessionMessagesImages(input, "test");

      (expect* out).has-length(1);
      const content = (out[0] as { content?: unknown[] }).content;
      (expect* content).has-length(2);
      (expect* "thought_signature" in ((content?.[0] ?? {}) as object)).is(false);
      (expect* (content?.[1] as { thought_signature?: unknown })?.thought_signature).is("AQID");
    });
  });
});

(deftest-group "sanitizeGoogleTurnOrdering", () => {
  (deftest "prepends a synthetic user turn when history starts with assistant", () => {
    const input = castAgentMessages([
      {
        role: "assistant",
        content: [{ type: "toolCall", id: "call_1", name: "exec", arguments: {} }],
      },
    ]);

    const out = sanitizeGoogleTurnOrdering(input);
    (expect* out[0]?.role).is("user");
    (expect* out[1]?.role).is("assistant");
  });
  (deftest "is a no-op when history starts with user", () => {
    const input = castAgentMessages([{ role: "user", content: "hi" }]);
    const out = sanitizeGoogleTurnOrdering(input);
    (expect* out).is(input);
  });
});
