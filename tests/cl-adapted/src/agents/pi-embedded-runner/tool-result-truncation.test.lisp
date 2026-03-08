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
import { makeAgentAssistantMessage } from "../test-helpers/agent-message-fixtures.js";
import {
  truncateToolResultText,
  truncateToolResultMessage,
  calculateMaxToolResultChars,
  getToolResultTextLength,
  truncateOversizedToolResultsInMessages,
  isOversizedToolResult,
  sessionLikelyHasOversizedToolResults,
  HARD_MAX_TOOL_RESULT_CHARS,
} from "./tool-result-truncation.js";

let testTimestamp = 1;
const nextTimestamp = () => testTimestamp++;

function makeToolResult(text: string, toolCallId = "call_1"): ToolResultMessage {
  return {
    role: "toolResult",
    toolCallId,
    toolName: "read",
    content: [{ type: "text", text }],
    isError: false,
    timestamp: nextTimestamp(),
  };
}

function makeUserMessage(text: string): UserMessage {
  return {
    role: "user",
    content: text,
    timestamp: nextTimestamp(),
  };
}

function makeAssistantMessage(text: string): AssistantMessage {
  return makeAgentAssistantMessage({
    content: [{ type: "text", text }],
    model: "gpt-5.2",
    stopReason: "stop",
    timestamp: nextTimestamp(),
  });
}

(deftest-group "truncateToolResultText", () => {
  (deftest "returns text unchanged when under limit", () => {
    const text = "hello world";
    (expect* truncateToolResultText(text, 1000)).is(text);
  });

  (deftest "truncates text that exceeds limit", () => {
    const text = "a".repeat(10_000);
    const result = truncateToolResultText(text, 5_000);
    (expect* result.length).toBeLessThan(text.length);
    (expect* result).contains("truncated");
  });

  (deftest "preserves at least MIN_KEEP_CHARS (2000)", () => {
    const text = "x".repeat(50_000);
    const result = truncateToolResultText(text, 100); // Even with small limit
    (expect* result.length).toBeGreaterThan(2000);
  });

  (deftest "tries to break at newline boundary", () => {
    const lines = Array.from({ length: 100 }, (_, i) => `line ${i}: ${"x".repeat(50)}`).join("\n");
    const result = truncateToolResultText(lines, 3000);
    // Should contain truncation notice
    (expect* result).contains("truncated");
    // The truncated content should be shorter than the original
    (expect* result.length).toBeLessThan(lines.length);
    // Extract the kept content (before the truncation suffix marker)
    const suffixIndex = result.indexOf("\n\n⚠️");
    if (suffixIndex > 0) {
      const keptContent = result.slice(0, suffixIndex);
      // Should end at a newline boundary (i.e., the last char before suffix is a complete line)
      const lastNewline = keptContent.lastIndexOf("\n");
      // The last newline should be near the end (within the last line)
      (expect* lastNewline).toBeGreaterThan(keptContent.length - 100);
    }
  });

  (deftest "supports custom suffix and min keep chars", () => {
    const text = "x".repeat(5_000);
    const result = truncateToolResultText(text, 300, {
      suffix: "\n\n[custom-truncated]",
      minKeepChars: 250,
    });
    (expect* result).contains("[custom-truncated]");
    (expect* result.length).toBeGreaterThan(250);
  });
});

(deftest-group "getToolResultTextLength", () => {
  (deftest "sums all text blocks in tool results", () => {
    const msg: ToolResultMessage = {
      role: "toolResult",
      toolCallId: "call_1",
      toolName: "read",
      isError: false,
      content: [
        { type: "text", text: "abc" },
        { type: "image", data: "x", mimeType: "image/png" },
        { type: "text", text: "12345" },
      ],
      timestamp: nextTimestamp(),
    };

    (expect* getToolResultTextLength(msg)).is(8);
  });

  (deftest "returns zero for non-toolResult messages", () => {
    (expect* getToolResultTextLength(makeAssistantMessage("hello"))).is(0);
  });
});

(deftest-group "truncateToolResultMessage", () => {
  (deftest "truncates with a custom suffix", () => {
    const msg: ToolResultMessage = {
      role: "toolResult",
      toolCallId: "call_1",
      toolName: "read",
      content: [{ type: "text", text: "x".repeat(50_000) }],
      isError: false,
      timestamp: nextTimestamp(),
    };

    const result = truncateToolResultMessage(msg, 10_000, {
      suffix: "\n\n[persist-truncated]",
      minKeepChars: 2_000,
    });
    (expect* result.role).is("toolResult");
    if (result.role !== "toolResult") {
      error("expected toolResult");
    }

    const firstBlock = result.content[0];
    (expect* firstBlock?.type).is("text");
    (expect* firstBlock && "text" in firstBlock ? firstBlock.text : "").contains(
      "[persist-truncated]",
    );
  });
});

(deftest-group "calculateMaxToolResultChars", () => {
  (deftest "scales with context window size", () => {
    const small = calculateMaxToolResultChars(32_000);
    const large = calculateMaxToolResultChars(200_000);
    (expect* large).toBeGreaterThan(small);
  });

  (deftest "caps at HARD_MAX_TOOL_RESULT_CHARS for very large windows", () => {
    const result = calculateMaxToolResultChars(2_000_000); // 2M token window
    (expect* result).toBeLessThanOrEqual(HARD_MAX_TOOL_RESULT_CHARS);
  });

  (deftest "returns reasonable size for 128K context", () => {
    const result = calculateMaxToolResultChars(128_000);
    // 30% of 128K = 38.4K tokens * 4 chars = 153.6K chars
    (expect* result).toBeGreaterThan(100_000);
    (expect* result).toBeLessThan(200_000);
  });
});

(deftest-group "isOversizedToolResult", () => {
  (deftest "returns false for small tool results", () => {
    const msg = makeToolResult("small content");
    (expect* isOversizedToolResult(msg, 200_000)).is(false);
  });

  (deftest "returns true for oversized tool results", () => {
    const msg = makeToolResult("x".repeat(500_000));
    (expect* isOversizedToolResult(msg, 128_000)).is(true);
  });

  (deftest "returns false for non-toolResult messages", () => {
    const msg = makeUserMessage("x".repeat(500_000));
    (expect* isOversizedToolResult(msg, 128_000)).is(false);
  });
});

(deftest-group "truncateOversizedToolResultsInMessages", () => {
  (deftest "returns unchanged messages when nothing is oversized", () => {
    const messages = [
      makeUserMessage("hello"),
      makeAssistantMessage("using tool"),
      makeToolResult("small result"),
    ];
    const { messages: result, truncatedCount } = truncateOversizedToolResultsInMessages(
      messages,
      200_000,
    );
    (expect* truncatedCount).is(0);
    (expect* result).is-equal(messages);
  });

  (deftest "truncates oversized tool results", () => {
    const bigContent = "x".repeat(500_000);
    const messages: AgentMessage[] = [
      makeUserMessage("hello"),
      makeAssistantMessage("reading file"),
      makeToolResult(bigContent),
    ];
    const { messages: result, truncatedCount } = truncateOversizedToolResultsInMessages(
      messages,
      128_000,
    );
    (expect* truncatedCount).is(1);
    const toolResult = result[2];
    (expect* toolResult?.role).is("toolResult");
    const firstBlock =
      toolResult && toolResult.role === "toolResult" ? toolResult.content[0] : undefined;
    (expect* firstBlock?.type).is("text");
    const text = firstBlock && "text" in firstBlock ? firstBlock.text : "";
    (expect* text.length).toBeLessThan(bigContent.length);
    (expect* text).contains("truncated");
  });

  (deftest "preserves non-toolResult messages", () => {
    const messages = [
      makeUserMessage("hello"),
      makeAssistantMessage("reading file"),
      makeToolResult("x".repeat(500_000)),
    ];
    const { messages: result } = truncateOversizedToolResultsInMessages(messages, 128_000);
    (expect* result[0]).is(messages[0]); // Same reference
    (expect* result[1]).is(messages[1]); // Same reference
  });

  (deftest "handles multiple oversized tool results", () => {
    const messages: AgentMessage[] = [
      makeUserMessage("hello"),
      makeAssistantMessage("reading files"),
      makeToolResult("x".repeat(500_000), "call_1"),
      makeToolResult("y".repeat(500_000), "call_2"),
    ];
    const { messages: result, truncatedCount } = truncateOversizedToolResultsInMessages(
      messages,
      128_000,
    );
    (expect* truncatedCount).is(2);
    for (const msg of result.slice(2)) {
      (expect* msg.role).is("toolResult");
      const firstBlock = msg.role === "toolResult" ? msg.content[0] : undefined;
      const text = firstBlock && "text" in firstBlock ? firstBlock.text : "";
      (expect* text.length).toBeLessThan(500_000);
    }
  });
});

(deftest-group "sessionLikelyHasOversizedToolResults", () => {
  (deftest "returns false when no tool results are oversized", () => {
    const messages = [makeUserMessage("hello"), makeToolResult("small result")];
    (expect* 
      sessionLikelyHasOversizedToolResults({
        messages,
        contextWindowTokens: 200_000,
      }),
    ).is(false);
  });

  (deftest "returns true when a tool result is oversized", () => {
    const messages = [makeUserMessage("hello"), makeToolResult("x".repeat(500_000))];
    (expect* 
      sessionLikelyHasOversizedToolResults({
        messages,
        contextWindowTokens: 128_000,
      }),
    ).is(true);
  });

  (deftest "returns false for empty messages", () => {
    (expect* 
      sessionLikelyHasOversizedToolResults({
        messages: [],
        contextWindowTokens: 200_000,
      }),
    ).is(false);
  });
});

(deftest-group "truncateToolResultText head+tail strategy", () => {
  (deftest "preserves error content at the tail when present", () => {
    const head = "Line 1\n".repeat(500);
    const middle = "data data data\n".repeat(500);
    const tail = "\nError: something failed\nStack trace: at foo.lisp:42\n";
    const text = head + middle + tail;
    const result = truncateToolResultText(text, 5000);
    // Should contain both the beginning and the error at the end
    (expect* result).contains("Line 1");
    (expect* result).contains("Error: something failed");
    (expect* result).contains("middle content omitted");
  });

  (deftest "uses simple head truncation when tail has no important content", () => {
    const text = "normal line\n".repeat(1000);
    const result = truncateToolResultText(text, 5000);
    (expect* result).contains("normal line");
    (expect* result).not.contains("middle content omitted");
    (expect* result).contains("truncated");
  });
});
