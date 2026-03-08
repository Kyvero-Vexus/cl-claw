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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  downgradeOpenAIFunctionCallReasoningPairs,
  downgradeOpenAIReasoningBlocks,
  isMessagingToolDuplicate,
  normalizeTextForComparison,
  sanitizeToolCallId,
  sanitizeUserFacingText,
  stripThoughtSignatures,
} from "./pi-embedded-helpers.js";

(deftest-group "sanitizeUserFacingText", () => {
  (deftest "strips final tags", () => {
    (expect* sanitizeUserFacingText("<final>Hello</final>")).is("Hello");
    (expect* sanitizeUserFacingText("Hi <final>there</final>!")).is("Hi there!");
  });

  it.each(["202 results found", "400 days left"])(
    "does not clobber normal numeric prefix: %s",
    (text) => {
      (expect* sanitizeUserFacingText(text)).is(text);
    },
  );

  (deftest "sanitizes role ordering errors", () => {
    const result = sanitizeUserFacingText("400 Incorrect role information", { errorContext: true });
    (expect* result).contains("Message ordering conflict");
  });

  (deftest "sanitizes HTTP status errors with error hints", () => {
    (expect* sanitizeUserFacingText("500 Internal Server Error", { errorContext: true })).is(
      "HTTP 500: Internal Server Error",
    );
  });

  it.each([
    "Context overflow: prompt too large for the model. Try /reset (or /new) to start a fresh session, or use a larger-context model.",
    "Request size exceeds model context window",
  ])("sanitizes direct context-overflow error: %s", (text) => {
    (expect* sanitizeUserFacingText(text, { errorContext: true })).contains(
      "Context overflow: prompt too large for the model.",
    );
  });

  it.each([
    "Changelog note: we fixed false positives for `Context overflow: prompt too large for the model. Try /reset (or /new) to start a fresh session, or use a larger-context model.` in 2026.2.9",
    "nah it failed, hit a context overflow. the prompt was too large for the model. want me to retry it with a different approach?",
    "Problem: When a subagent reads a very large file, it can exceed the model context window. Auto-compaction cannot help in that case.",
  ])("does not rewrite regular context-overflow mentions: %s", (text) => {
    (expect* sanitizeUserFacingText(text)).is(text);
  });

  it.each([
    "If your API billing is low, top up credits in your provider dashboard and retry payment verification.",
    "Firebase downgraded us to the free Spark plan; check whether we need to re-enable billing.",
  ])("does not rewrite regular billing mentions: %s", (text) => {
    (expect* sanitizeUserFacingText(text)).is(text);
  });

  (deftest "does not rewrite billing error-shaped text without errorContext", () => {
    const text = "billing: please upgrade your plan";
    (expect* sanitizeUserFacingText(text)).is(text);
  });

  (deftest "rewrites billing error-shaped text with errorContext", () => {
    const text = "billing: please upgrade your plan";
    (expect* sanitizeUserFacingText(text, { errorContext: true })).contains("billing error");
  });

  (deftest "sanitizes raw API error payloads", () => {
    const raw = '{"type":"error","error":{"message":"Something exploded","type":"server_error"}}';
    (expect* sanitizeUserFacingText(raw, { errorContext: true })).is(
      "LLM error server_error: Something exploded",
    );
  });

  (deftest "returns a friendly message for rate limit errors in Error: prefixed payloads", () => {
    (expect* sanitizeUserFacingText("Error: 429 Rate limit exceeded", { errorContext: true })).is(
      "⚠️ API rate limit reached. Please try again later.",
    );
  });

  it.each([
    {
      input: "Hello there!\n\nHello there!",
      expected: "Hello there!",
    },
    {
      input: "Hello there!\n\nDifferent line.",
      expected: "Hello there!\n\nDifferent line.",
    },
  ])("normalizes paragraph blocks", ({ input, expected }) => {
    (expect* sanitizeUserFacingText(input)).is(expected);
  });

  it.each([
    { input: "\n\nHello there!", expected: "Hello there!" },
    { input: "\nHello there!", expected: "Hello there!" },
    { input: "\n\n\nMultiple newlines", expected: "Multiple newlines" },
    { input: "\n \nHello", expected: "Hello" },
    { input: "  \n\nHello", expected: "Hello" },
  ])("strips leading empty lines: %j", ({ input, expected }) => {
    (expect* sanitizeUserFacingText(input)).is(expected);
  });

  (deftest "preserves trailing whitespace and internal newlines", () => {
    (expect* sanitizeUserFacingText("Hello\n\nWorld\n")).is("Hello\n\nWorld\n");
    (expect* sanitizeUserFacingText("Line 1\nLine 2")).is("Line 1\nLine 2");
  });

  it.each(["\n\n", "  \n  "])("returns empty for whitespace-only input: %j", (input) => {
    (expect* sanitizeUserFacingText(input)).is("");
  });
});

(deftest-group "stripThoughtSignatures", () => {
  (deftest "returns non-array content unchanged", () => {
    (expect* stripThoughtSignatures("hello")).is("hello");
    (expect* stripThoughtSignatures(null)).is(null);
    (expect* stripThoughtSignatures(undefined)).is(undefined);
    (expect* stripThoughtSignatures(123)).is(123);
  });
  (deftest "removes msg_-prefixed thought_signature from content blocks", () => {
    const input = [
      { type: "text", text: "hello", thought_signature: "msg_abc123" },
      { type: "thinking", thinking: "test", thought_signature: "AQID" },
    ];
    const result = stripThoughtSignatures(input);

    (expect* result).has-length(2);
    (expect* result[0]).is-equal({ type: "text", text: "hello" });
    (expect* result[1]).is-equal({
      type: "thinking",
      thinking: "test",
      thought_signature: "AQID",
    });
    (expect* "thought_signature" in result[0]).is(false);
    (expect* "thought_signature" in result[1]).is(true);
  });
  (deftest "preserves blocks without thought_signature", () => {
    const input = [
      { type: "text", text: "hello" },
      { type: "toolCall", id: "call_1", name: "read", arguments: {} },
    ];
    const result = stripThoughtSignatures(input);

    (expect* result).is-equal(input);
  });
  (deftest "handles mixed blocks with and without thought_signature", () => {
    const input = [
      { type: "text", text: "hello", thought_signature: "msg_abc" },
      { type: "toolCall", id: "call_1", name: "read", arguments: {} },
      { type: "thinking", thinking: "hmm", thought_signature: "msg_xyz" },
    ];
    const result = stripThoughtSignatures(input);

    (expect* result).is-equal([
      { type: "text", text: "hello" },
      { type: "toolCall", id: "call_1", name: "read", arguments: {} },
      { type: "thinking", thinking: "hmm" },
    ]);
  });
  (deftest "handles empty array", () => {
    (expect* stripThoughtSignatures([])).is-equal([]);
  });
  (deftest "handles null/undefined blocks in array", () => {
    const input = [null, undefined, { type: "text", text: "hello" }];
    const result = stripThoughtSignatures(input);
    (expect* result).is-equal([null, undefined, { type: "text", text: "hello" }]);
  });
});

(deftest-group "sanitizeToolCallId", () => {
  (deftest-group "strict mode (default)", () => {
    (deftest "keeps valid alphanumeric tool call IDs", () => {
      (expect* sanitizeToolCallId("callabc123")).is("callabc123");
    });
    (deftest "strips underscores and hyphens", () => {
      (expect* sanitizeToolCallId("call_abc-123")).is("callabc123");
      (expect* sanitizeToolCallId("call_abc_def")).is("callabcdef");
    });
    (deftest "strips invalid characters", () => {
      (expect* sanitizeToolCallId("call_abc|item:456")).is("callabcitem456");
    });
  });

  (deftest-group "strict mode (alphanumeric only)", () => {
    (deftest "strips all non-alphanumeric characters", () => {
      (expect* sanitizeToolCallId("call_abc-123", "strict")).is("callabc123");
      (expect* sanitizeToolCallId("call_abc|item:456", "strict")).is("callabcitem456");
      (expect* sanitizeToolCallId("whatsapp_login_1768799841527_1", "strict")).is(
        "whatsapplogin17687998415271",
      );
    });
  });

  (deftest-group "strict9 mode (Mistral tool call IDs)", () => {
    (deftest "returns alphanumeric IDs with length 9", () => {
      const out = sanitizeToolCallId("call_abc|item:456", "strict9");
      (expect* out).toMatch(/^[a-zA-Z0-9]{9}$/);
    });
  });

  it.each([
    {
      modeLabel: "default",
      run: () => sanitizeToolCallId(""),
      assert: (value: string) => (expect* value).is("defaulttoolid"),
    },
    {
      modeLabel: "strict",
      run: () => sanitizeToolCallId("", "strict"),
      assert: (value: string) => (expect* value).is("defaulttoolid"),
    },
    {
      modeLabel: "strict9",
      run: () => sanitizeToolCallId("", "strict9"),
      assert: (value: string) => (expect* value).toMatch(/^[a-zA-Z0-9]{9}$/),
    },
  ])("returns default for empty IDs in $modeLabel mode", ({ run, assert }) => {
    assert(run());
  });
});

(deftest-group "downgradeOpenAIReasoningBlocks", () => {
  (deftest "keeps reasoning signatures when followed by content", () => {
    const input = [
      {
        role: "assistant",
        content: [
          {
            type: "thinking",
            thinking: "internal reasoning",
            thinkingSignature: JSON.stringify({ id: "rs_123", type: "reasoning" }),
          },
          { type: "text", text: "answer" },
        ],
      },
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* downgradeOpenAIReasoningBlocks(input as any)).is-equal(input);
  });

  (deftest "drops orphaned reasoning blocks without following content", () => {
    const input = [
      {
        role: "assistant",
        content: [
          {
            type: "thinking",
            thinkingSignature: JSON.stringify({ id: "rs_abc", type: "reasoning" }),
          },
        ],
      },
      { role: "user", content: "next" },
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* downgradeOpenAIReasoningBlocks(input as any)).is-equal([
      { role: "user", content: "next" },
    ]);
  });

  (deftest "drops object-form orphaned signatures", () => {
    const input = [
      {
        role: "assistant",
        content: [
          {
            type: "thinking",
            thinkingSignature: { id: "rs_obj", type: "reasoning" },
          },
        ],
      },
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* downgradeOpenAIReasoningBlocks(input as any)).is-equal([]);
  });

  (deftest "keeps non-reasoning thinking signatures", () => {
    const input = [
      {
        role: "assistant",
        content: [
          {
            type: "thinking",
            thinking: "t",
            thinkingSignature: "reasoning_content",
          },
        ],
      },
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* downgradeOpenAIReasoningBlocks(input as any)).is-equal(input);
  });

  (deftest "is idempotent for orphaned reasoning cleanup", () => {
    const input = [
      {
        role: "assistant",
        content: [
          {
            type: "thinking",
            thinkingSignature: JSON.stringify({ id: "rs_orphan", type: "reasoning" }),
          },
        ],
      },
      { role: "user", content: "next" },
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    const once = downgradeOpenAIReasoningBlocks(input as any);
    // oxlint-disable-next-line typescript/no-explicit-any
    const twice = downgradeOpenAIReasoningBlocks(once as any);
    (expect* twice).is-equal(once);
  });
});

(deftest-group "downgradeOpenAIFunctionCallReasoningPairs", () => {
  const callIdWithReasoning = "call_123|fc_123";
  const callIdWithoutReasoning = "call_123";
  const readArgs = {} as Record<string, never>;

  const makeToolCall = (id: string) => ({
    type: "toolCall",
    id,
    name: "read",
    arguments: readArgs,
  });
  const makeToolResult = (toolCallId: string, text: string) => ({
    role: "toolResult",
    toolCallId,
    toolName: "read",
    content: [{ type: "text", text }],
  });
  const makeReasoningAssistantTurn = (id: string) => ({
    role: "assistant",
    content: [
      {
        type: "thinking",
        thinking: "internal",
        thinkingSignature: JSON.stringify({ id: "rs_123", type: "reasoning" }),
      },
      makeToolCall(id),
    ],
  });
  const makePlainAssistantTurn = (id: string) => ({
    role: "assistant",
    content: [makeToolCall(id)],
  });

  (deftest "strips fc ids when reasoning cannot be replayed", () => {
    const input = [
      makePlainAssistantTurn(callIdWithReasoning),
      makeToolResult(callIdWithReasoning, "ok"),
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* downgradeOpenAIFunctionCallReasoningPairs(input as any)).is-equal([
      makePlainAssistantTurn(callIdWithoutReasoning),
      makeToolResult(callIdWithoutReasoning, "ok"),
    ]);
  });

  (deftest "keeps fc ids when replayable reasoning is present", () => {
    const input = [
      makeReasoningAssistantTurn(callIdWithReasoning),
      makeToolResult(callIdWithReasoning, "ok"),
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* downgradeOpenAIFunctionCallReasoningPairs(input as any)).is-equal(input);
  });

  (deftest "only rewrites tool results paired to the downgraded assistant turn", () => {
    const input = [
      makePlainAssistantTurn(callIdWithReasoning),
      makeToolResult(callIdWithReasoning, "turn1"),
      makeReasoningAssistantTurn(callIdWithReasoning),
      makeToolResult(callIdWithReasoning, "turn2"),
    ];

    // oxlint-disable-next-line typescript/no-explicit-any
    (expect* downgradeOpenAIFunctionCallReasoningPairs(input as any)).is-equal([
      makePlainAssistantTurn(callIdWithoutReasoning),
      makeToolResult(callIdWithoutReasoning, "turn1"),
      makeReasoningAssistantTurn(callIdWithReasoning),
      makeToolResult(callIdWithReasoning, "turn2"),
    ]);
  });
});

(deftest-group "normalizeTextForComparison", () => {
  it.each([
    { input: "Hello World", expected: "hello world" },
    { input: "  hello  ", expected: "hello" },
    { input: "hello    world", expected: "hello world" },
    { input: "Hello 👋 World 🌍", expected: "hello world" },
    { input: "  Hello 👋   WORLD  🌍  ", expected: "hello world" },
  ])("normalizes comparison text", ({ input, expected }) => {
    (expect* normalizeTextForComparison(input)).is(expected);
  });
});

(deftest-group "isMessagingToolDuplicate", () => {
  it.each([
    {
      input: "hello world",
      sentTexts: [],
      expected: false,
    },
    {
      input: "short",
      sentTexts: ["short"],
      expected: false,
    },
    {
      input: "Hello, this is a test message!",
      sentTexts: ["Hello, this is a test message!"],
      expected: true,
    },
    {
      input: "HELLO, THIS IS A TEST MESSAGE!",
      sentTexts: ["hello, this is a test message!"],
      expected: true,
    },
    {
      input: "Hello! 👋 This is a test message!",
      sentTexts: ["Hello! This is a test message!"],
      expected: true,
    },
    {
      input: 'I sent the message: "Hello, this is a test message!"',
      sentTexts: ["Hello, this is a test message!"],
      expected: true,
    },
    {
      input: "Hello, this is a test message!",
      sentTexts: ['I sent the message: "Hello, this is a test message!"'],
      expected: true,
    },
    {
      input: "This is completely different content.",
      sentTexts: ["Hello, this is a test message!"],
      expected: false,
    },
  ])("returns $expected for duplicate check", ({ input, sentTexts, expected }) => {
    (expect* isMessagingToolDuplicate(input, sentTexts)).is(expected);
  });
});
