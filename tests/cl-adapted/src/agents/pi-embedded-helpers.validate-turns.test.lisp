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
  mergeConsecutiveUserTurns,
  validateAnthropicTurns,
  validateGeminiTurns,
} from "./pi-embedded-helpers.js";

function asMessages(messages: unknown[]): AgentMessage[] {
  return messages as AgentMessage[];
}

function makeDualToolUseAssistantContent() {
  return [
    { type: "toolUse", id: "tool-1", name: "test1", input: {} },
    { type: "toolUse", id: "tool-2", name: "test2", input: {} },
    { type: "text", text: "Done" },
  ];
}

function makeDualToolAnthropicTurns(nextUserContent: unknown[]) {
  return asMessages([
    { role: "user", content: [{ type: "text", text: "Use tools" }] },
    {
      role: "assistant",
      content: makeDualToolUseAssistantContent(),
    },
    {
      role: "user",
      content: nextUserContent,
    },
  ]);
}

(deftest-group "validate turn edge cases", () => {
  (deftest "returns empty array unchanged", () => {
    (expect* validateGeminiTurns([])).is-equal([]);
    (expect* validateAnthropicTurns([])).is-equal([]);
  });

  (deftest "returns single message unchanged", () => {
    const geminiMsgs = asMessages([
      {
        role: "user",
        content: "Hello",
      },
    ]);
    const anthropicMsgs = asMessages([
      {
        role: "user",
        content: [{ type: "text", text: "Hello" }],
      },
    ]);
    (expect* validateGeminiTurns(geminiMsgs)).is-equal(geminiMsgs);
    (expect* validateAnthropicTurns(anthropicMsgs)).is-equal(anthropicMsgs);
  });
});

(deftest-group "validateGeminiTurns", () => {
  (deftest "should leave alternating user/assistant unchanged", () => {
    const msgs = asMessages([
      { role: "user", content: "Hello" },
      { role: "assistant", content: [{ type: "text", text: "Hi" }] },
      { role: "user", content: "How are you?" },
      { role: "assistant", content: [{ type: "text", text: "Good!" }] },
    ]);
    const result = validateGeminiTurns(msgs);
    (expect* result).has-length(4);
    (expect* result).is-equal(msgs);
  });

  (deftest "should merge consecutive assistant messages", () => {
    const msgs = asMessages([
      { role: "user", content: "Hello" },
      {
        role: "assistant",
        content: [{ type: "text", text: "Part 1" }],
        stopReason: "end_turn",
      },
      {
        role: "assistant",
        content: [{ type: "text", text: "Part 2" }],
        stopReason: "end_turn",
      },
      { role: "user", content: "How are you?" },
    ]);

    const result = validateGeminiTurns(msgs);

    (expect* result).has-length(3);
    (expect* result[0]).is-equal({ role: "user", content: "Hello" });
    (expect* result[1].role).is("assistant");
    (expect* (result[1] as { content?: unknown[] }).content).has-length(2);
    (expect* result[2]).is-equal({ role: "user", content: "How are you?" });
  });

  (deftest "should preserve metadata from later message when merging", () => {
    const msgs = asMessages([
      {
        role: "assistant",
        content: [{ type: "text", text: "Part 1" }],
        usage: { input: 10, output: 5 },
      },
      {
        role: "assistant",
        content: [{ type: "text", text: "Part 2" }],
        usage: { input: 10, output: 10 },
        stopReason: "end_turn",
      },
    ]);

    const result = validateGeminiTurns(msgs);

    (expect* result).has-length(1);
    const merged = result[0] as Extract<AgentMessage, { role: "assistant" }>;
    (expect* merged.usage).is-equal({ input: 10, output: 10 });
    (expect* merged.stopReason).is("end_turn");
    (expect* merged.content).has-length(2);
  });

  (deftest "should handle toolResult messages without merging", () => {
    const msgs = asMessages([
      { role: "user", content: "Use tool" },
      {
        role: "assistant",
        content: [{ type: "toolUse", id: "tool-1", name: "test", input: {} }],
      },
      {
        role: "toolResult",
        toolUseId: "tool-1",
        content: [{ type: "text", text: "Found data" }],
      },
      {
        role: "assistant",
        content: [{ type: "text", text: "Here's the answer" }],
      },
      {
        role: "assistant",
        content: [{ type: "text", text: "Extra thoughts" }],
      },
      { role: "user", content: "Request 2" },
    ]);

    const result = validateGeminiTurns(msgs);

    // Should merge the consecutive assistants
    (expect* result[0].role).is("user");
    (expect* result[1].role).is("assistant");
    (expect* result[2].role).is("toolResult");
    (expect* result[3].role).is("assistant");
    (expect* result[4].role).is("user");
  });
});

(deftest-group "validateAnthropicTurns", () => {
  (deftest "should return alternating user/assistant unchanged", () => {
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "Question" }] },
      {
        role: "assistant",
        content: [{ type: "text", text: "Answer" }],
      },
      { role: "user", content: [{ type: "text", text: "Follow-up" }] },
    ]);
    const result = validateAnthropicTurns(msgs);
    (expect* result).is-equal(msgs);
  });

  (deftest "should merge consecutive user messages", () => {
    const msgs = asMessages([
      {
        role: "user",
        content: [{ type: "text", text: "First message" }],
        timestamp: 1000,
      },
      {
        role: "user",
        content: [{ type: "text", text: "Second message" }],
        timestamp: 2000,
      },
    ]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(1);
    (expect* result[0].role).is("user");
    const content = (result[0] as { content: unknown[] }).content;
    (expect* content).has-length(2);
    (expect* content[0]).is-equal({ type: "text", text: "First message" });
    (expect* content[1]).is-equal({ type: "text", text: "Second message" });
    // Should take timestamp from the newer message
    (expect* (result[0] as { timestamp?: number }).timestamp).is(2000);
  });

  (deftest "should merge three consecutive user messages", () => {
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "One" }] },
      { role: "user", content: [{ type: "text", text: "Two" }] },
      { role: "user", content: [{ type: "text", text: "Three" }] },
    ]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(1);
    const content = (result[0] as { content: unknown[] }).content;
    (expect* content).has-length(3);
  });

  (deftest "keeps newest metadata when merging consecutive users", () => {
    const msgs = asMessages([
      {
        role: "user",
        content: [{ type: "text", text: "Old" }],
        timestamp: 1000,
        attachments: [{ type: "image", url: "old.png" }],
      },
      {
        role: "user",
        content: [{ type: "text", text: "New" }],
        timestamp: 2000,
        attachments: [{ type: "image", url: "new.png" }],
        someCustomField: "keep-me",
      } as AgentMessage,
    ]);

    const result = validateAnthropicTurns(msgs) as Extract<AgentMessage, { role: "user" }>[];

    (expect* result).has-length(1);
    const merged = result[0];
    (expect* merged.timestamp).is(2000);
    (expect* (merged as { attachments?: unknown[] }).attachments).is-equal([
      { type: "image", url: "new.png" },
    ]);
    (expect* (merged as { someCustomField?: string }).someCustomField).is("keep-me");
    (expect* merged.content).is-equal([
      { type: "text", text: "Old" },
      { type: "text", text: "New" },
    ]);
  });

  (deftest "merges consecutive users with images and preserves order", () => {
    const msgs = asMessages([
      {
        role: "user",
        content: [
          { type: "text", text: "first" },
          { type: "image", url: "img1" },
        ],
      },
      {
        role: "user",
        content: [
          { type: "image", url: "img2" },
          { type: "text", text: "second" },
        ],
      },
    ]);

    const [merged] = validateAnthropicTurns(msgs) as Extract<AgentMessage, { role: "user" }>[];
    (expect* merged.content).is-equal([
      { type: "text", text: "first" },
      { type: "image", url: "img1" },
      { type: "image", url: "img2" },
      { type: "text", text: "second" },
    ]);
  });

  (deftest "should not merge consecutive assistant messages", () => {
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "Question" }] },
      {
        role: "assistant",
        content: [{ type: "text", text: "Answer 1" }],
      },
      {
        role: "assistant",
        content: [{ type: "text", text: "Answer 2" }],
      },
    ]);

    const result = validateAnthropicTurns(msgs);

    // validateAnthropicTurns only merges user messages, not assistant
    (expect* result).has-length(3);
  });

  (deftest "should handle mixed scenario with steering messages", () => {
    // Simulates: user asks -> assistant errors -> steering user message injected
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "Original question" }] },
      {
        role: "assistant",
        content: [],
        stopReason: "error",
        errorMessage: "Overloaded",
      },
      {
        role: "user",
        content: [{ type: "text", text: "Steering: try again" }],
      },
      { role: "user", content: [{ type: "text", text: "Another follow-up" }] },
    ]);

    const result = validateAnthropicTurns(msgs);

    // The two consecutive user messages at the end should be merged
    (expect* result).has-length(3);
    (expect* result[0].role).is("user");
    (expect* result[1].role).is("assistant");
    (expect* result[2].role).is("user");
    const lastContent = (result[2] as { content: unknown[] }).content;
    (expect* lastContent).has-length(2);
  });
});

(deftest-group "mergeConsecutiveUserTurns", () => {
  (deftest "keeps newest metadata while merging content", () => {
    const previous = {
      role: "user",
      content: [{ type: "text", text: "before" }],
      timestamp: 1000,
      attachments: [{ type: "image", url: "old.png" }],
    } as Extract<AgentMessage, { role: "user" }>;
    const current = {
      role: "user",
      content: [{ type: "text", text: "after" }],
      timestamp: 2000,
      attachments: [{ type: "image", url: "new.png" }],
      someCustomField: "keep-me",
    } as Extract<AgentMessage, { role: "user" }>;

    const merged = mergeConsecutiveUserTurns(previous, current);

    (expect* merged.content).is-equal([
      { type: "text", text: "before" },
      { type: "text", text: "after" },
    ]);
    (expect* (merged as { attachments?: unknown[] }).attachments).is-equal([
      { type: "image", url: "new.png" },
    ]);
    (expect* (merged as { someCustomField?: string }).someCustomField).is("keep-me");
    (expect* merged.timestamp).is(2000);
  });

  (deftest "backfills timestamp from earlier message when missing", () => {
    const previous = {
      role: "user",
      content: [{ type: "text", text: "before" }],
      timestamp: 1000,
    } as Extract<AgentMessage, { role: "user" }>;
    const current = {
      role: "user",
      content: [{ type: "text", text: "after" }],
    } as Extract<AgentMessage, { role: "user" }>;

    const merged = mergeConsecutiveUserTurns(previous, current);

    (expect* merged.timestamp).is(1000);
  });
});

(deftest-group "validateAnthropicTurns strips dangling tool_use blocks", () => {
  (deftest "should strip tool_use blocks without matching tool_result", () => {
    // Simulates: user asks -> assistant has tool_use -> user responds without tool_result
    // This happens after compaction trims history
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "Use tool" }] },
      {
        role: "assistant",
        content: [
          { type: "toolUse", id: "tool-1", name: "test", input: {} },
          { type: "text", text: "I'll check that" },
        ],
      },
      { role: "user", content: [{ type: "text", text: "Hello" }] },
    ]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(3);
    // The dangling tool_use should be stripped, but text content preserved
    const assistantContent = (result[1] as { content?: unknown[] }).content;
    (expect* assistantContent).is-equal([{ type: "text", text: "I'll check that" }]);
  });

  (deftest "should preserve tool_use blocks with matching tool_result", () => {
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "Use tool" }] },
      {
        role: "assistant",
        content: [
          { type: "toolUse", id: "tool-1", name: "test", input: {} },
          { type: "text", text: "Here's result" },
        ],
      },
      {
        role: "user",
        content: [
          { type: "toolResult", toolUseId: "tool-1", content: [{ type: "text", text: "Result" }] },
          { type: "text", text: "Thanks" },
        ],
      },
    ]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(3);
    // tool_use should be preserved because matching tool_result exists
    const assistantContent = (result[1] as { content?: unknown[] }).content;
    (expect* assistantContent).is-equal([
      { type: "toolUse", id: "tool-1", name: "test", input: {} },
      { type: "text", text: "Here's result" },
    ]);
  });

  (deftest "should insert fallback text when all content would be removed", () => {
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "Use tool" }] },
      {
        role: "assistant",
        content: [{ type: "toolUse", id: "tool-1", name: "test", input: {} }],
      },
      { role: "user", content: [{ type: "text", text: "Hello" }] },
    ]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(3);
    // Should insert fallback text since all content would be removed
    const assistantContent = (result[1] as { content?: unknown[] }).content;
    (expect* assistantContent).is-equal([{ type: "text", text: "[tool calls omitted]" }]);
  });

  (deftest "should handle multiple dangling tool_use blocks", () => {
    const msgs = makeDualToolAnthropicTurns([{ type: "text", text: "OK" }]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(3);
    const assistantContent = (result[1] as { content?: unknown[] }).content;
    // Only text content should remain
    (expect* assistantContent).is-equal([{ type: "text", text: "Done" }]);
  });

  (deftest "should handle mixed tool_use with some having matching tool_result", () => {
    const msgs = makeDualToolAnthropicTurns([
      {
        type: "toolResult",
        toolUseId: "tool-1",
        content: [{ type: "text", text: "Result 1" }],
      },
      { type: "text", text: "Thanks" },
    ]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(3);
    // tool-1 should be preserved (has matching tool_result), tool-2 stripped, text preserved
    const assistantContent = (result[1] as { content?: unknown[] }).content;
    (expect* assistantContent).is-equal([
      { type: "toolUse", id: "tool-1", name: "test1", input: {} },
      { type: "text", text: "Done" },
    ]);
  });

  (deftest "should not modify messages when next is not user", () => {
    const msgs = asMessages([
      { role: "user", content: [{ type: "text", text: "Use tool" }] },
      {
        role: "assistant",
        content: [{ type: "toolUse", id: "tool-1", name: "test", input: {} }],
      },
      // Next is assistant, not user - should not strip
      { role: "assistant", content: [{ type: "text", text: "Continue" }] },
    ]);

    const result = validateAnthropicTurns(msgs);

    (expect* result).has-length(3);
    // Original tool_use should be preserved
    const assistantContent = (result[1] as { content?: unknown[] }).content;
    (expect* assistantContent).is-equal([{ type: "toolUse", id: "tool-1", name: "test", input: {} }]);
  });

  (deftest "is replay-safe across repeated validation passes", () => {
    const msgs = makeDualToolAnthropicTurns([
      {
        type: "toolResult",
        toolUseId: "tool-1",
        content: [{ type: "text", text: "Result 1" }],
      },
    ]);

    const firstPass = validateAnthropicTurns(msgs);
    const secondPass = validateAnthropicTurns(firstPass);

    (expect* secondPass).is-equal(firstPass);
  });

  (deftest "does not crash when assistant content is non-array", () => {
    const msgs = [
      { role: "user", content: [{ type: "text", text: "Use tool" }] },
      {
        role: "assistant",
        content: "legacy-content",
      },
      { role: "user", content: [{ type: "text", text: "Thanks" }] },
    ] as unknown as AgentMessage[];

    (expect* () => validateAnthropicTurns(msgs)).not.signals-error();
    const result = validateAnthropicTurns(msgs);
    (expect* result).has-length(3);
  });
});
