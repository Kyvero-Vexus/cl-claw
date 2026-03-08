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
import type { AssistantMessage, UserMessage, Usage } from "@mariozechner/pi-ai";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as helpers from "./pi-embedded-helpers.js";
import {
  expectGoogleModelApiFullSanitizeCall,
  loadSanitizeSessionHistoryWithCleanMocks,
  makeMockSessionManager,
  makeInMemorySessionManager,
  makeModelSnapshotEntry,
  makeReasoningAssistantMessages,
  makeSimpleUserMessages,
  sanitizeSnapshotChangedOpenAIReasoning,
  type SanitizeSessionHistoryFn,
  sanitizeWithOpenAIResponses,
  TEST_SESSION_ID,
} from "./pi-embedded-runner.sanitize-session-history.test-harness.js";
import { castAgentMessage, castAgentMessages } from "./test-helpers/agent-message-fixtures.js";
import { makeZeroUsageSnapshot } from "./usage.js";

mock:mock("./pi-embedded-helpers.js", async () => ({
  ...(await mock:importActual("./pi-embedded-helpers.js")),
  isGoogleModelApi: mock:fn(),
  sanitizeSessionMessagesImages: mock:fn(async (msgs) => msgs),
}));

let sanitizeSessionHistory: SanitizeSessionHistoryFn;
let testTimestamp = 1;
const nextTimestamp = () => testTimestamp++;

// We don't mock session-transcript-repair.js as it is a pure function and complicates mocking.
// We rely on the real implementation which should pass through our simple messages.

(deftest-group "sanitizeSessionHistory", () => {
  const mockSessionManager = makeMockSessionManager();
  const mockMessages = makeSimpleUserMessages();
  const setNonGoogleModelApi = () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);
  };

  const sanitizeGithubCopilotHistory = async (params: {
    messages: AgentMessage[];
    modelApi?: string;
    modelId?: string;
  }) =>
    sanitizeSessionHistory({
      messages: params.messages,
      modelApi: params.modelApi ?? "openai-completions",
      provider: "github-copilot",
      modelId: params.modelId ?? "claude-opus-4.6",
      sessionManager: makeMockSessionManager(),
      sessionId: TEST_SESSION_ID,
    });

  const getAssistantMessage = (messages: AgentMessage[]) => {
    (expect* messages[1]?.role).is("assistant");
    return messages[1] as Extract<AgentMessage, { role: "assistant" }>;
  };

  const getAssistantContentTypes = (messages: AgentMessage[]) =>
    getAssistantMessage(messages).content.map((block: { type: string }) => block.type);

  const makeThinkingAndTextAssistantMessages = (
    thinkingSignature: string = "some_sig",
  ): AgentMessage[] => {
    const user: UserMessage = {
      role: "user",
      content: "hello",
      timestamp: nextTimestamp(),
    };
    const assistant: AssistantMessage = {
      role: "assistant",
      content: [
        {
          type: "thinking",
          thinking: "internal",
          thinkingSignature,
        },
        { type: "text", text: "hi" },
      ],
      api: "openai-responses",
      provider: "openai",
      model: "gpt-5.2",
      usage: makeUsage(0, 0, 0),
      stopReason: "stop",
      timestamp: nextTimestamp(),
    };
    return [user, assistant];
  };

  const makeUsage = (input: number, output: number, totalTokens: number): Usage => ({
    input,
    output,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  });

  const makeAssistantUsageMessage = (params: {
    text: string;
    usage: ReturnType<typeof makeUsage>;
    timestamp?: number;
  }): AssistantMessage => ({
    role: "assistant",
    content: [{ type: "text", text: params.text }],
    api: "openai-responses",
    provider: "openai",
    model: "gpt-5.2",
    stopReason: "stop",
    timestamp: params.timestamp ?? nextTimestamp(),
    usage: params.usage,
  });

  const makeUserMessage = (content: string, timestamp = nextTimestamp()): UserMessage => ({
    role: "user",
    content,
    timestamp,
  });

  const makeAssistantMessage = (
    content: AssistantMessage["content"],
    params: {
      stopReason?: AssistantMessage["stopReason"];
      usage?: Usage;
      timestamp?: number;
    } = {},
  ): AssistantMessage => ({
    role: "assistant",
    content,
    api: "openai-responses",
    provider: "openai",
    model: "gpt-5.2",
    usage: params.usage ?? makeUsage(0, 0, 0),
    stopReason: params.stopReason ?? "stop",
    timestamp: params.timestamp ?? nextTimestamp(),
  });

  const makeCompactionSummaryMessage = (tokensBefore: number, timestamp: string) =>
    castAgentMessage({
      role: "compactionSummary",
      summary: "compressed",
      tokensBefore,
      timestamp,
    });

  const sanitizeOpenAIHistory = async (
    messages: AgentMessage[],
    overrides: Partial<Parameters<SanitizeSessionHistoryFn>[0]> = {},
  ) =>
    sanitizeSessionHistory({
      messages,
      modelApi: "openai-responses",
      provider: "openai",
      sessionManager: mockSessionManager,
      sessionId: TEST_SESSION_ID,
      ...overrides,
    });

  const getAssistantMessages = (messages: AgentMessage[]) =>
    messages.filter((message) => message.role === "assistant") as Array<
      AgentMessage & { usage?: unknown; content?: unknown }
    >;

  beforeEach(async () => {
    testTimestamp = 1;
    sanitizeSessionHistory = await loadSanitizeSessionHistoryWithCleanMocks();
  });

  (deftest "sanitizes tool call ids for Google model APIs", async () => {
    await expectGoogleModelApiFullSanitizeCall({
      sanitizeSessionHistory,
      messages: mockMessages,
      sessionManager: mockSessionManager,
    });
  });

  (deftest "sanitizes tool call ids with strict9 for Mistral models", async () => {
    setNonGoogleModelApi();

    await sanitizeSessionHistory({
      messages: mockMessages,
      modelApi: "openai-responses",
      provider: "openrouter",
      modelId: "mistralai/devstral-2512:free",
      sessionManager: mockSessionManager,
      sessionId: TEST_SESSION_ID,
    });

    (expect* helpers.sanitizeSessionMessagesImages).toHaveBeenCalledWith(
      mockMessages,
      "session:history",
      expect.objectContaining({
        sanitizeMode: "full",
        sanitizeToolCallIds: true,
        toolCallIdMode: "strict9",
      }),
    );
  });

  (deftest "sanitizes tool call ids for Anthropic APIs", async () => {
    setNonGoogleModelApi();

    await sanitizeSessionHistory({
      messages: mockMessages,
      modelApi: "anthropic-messages",
      provider: "anthropic",
      sessionManager: mockSessionManager,
      sessionId: TEST_SESSION_ID,
    });

    (expect* helpers.sanitizeSessionMessagesImages).toHaveBeenCalledWith(
      mockMessages,
      "session:history",
      expect.objectContaining({ sanitizeMode: "full", sanitizeToolCallIds: true }),
    );
  });

  (deftest "does not sanitize tool call ids for openai-responses", async () => {
    setNonGoogleModelApi();

    await sanitizeWithOpenAIResponses({
      sanitizeSessionHistory,
      messages: mockMessages,
      sessionManager: mockSessionManager,
    });

    (expect* helpers.sanitizeSessionMessagesImages).toHaveBeenCalledWith(
      mockMessages,
      "session:history",
      expect.objectContaining({ sanitizeMode: "images-only", sanitizeToolCallIds: false }),
    );
  });

  (deftest "sanitizes tool call ids for openai-completions", async () => {
    setNonGoogleModelApi();

    await sanitizeSessionHistory({
      messages: mockMessages,
      modelApi: "openai-completions",
      provider: "openai",
      modelId: "gpt-5.2",
      sessionManager: mockSessionManager,
      sessionId: TEST_SESSION_ID,
    });

    (expect* helpers.sanitizeSessionMessagesImages).toHaveBeenCalledWith(
      mockMessages,
      "session:history",
      expect.objectContaining({
        sanitizeMode: "images-only",
        sanitizeToolCallIds: true,
        toolCallIdMode: "strict",
      }),
    );
  });

  (deftest "prepends a bootstrap user turn for strict OpenAI-compatible assistant-first history", async () => {
    setNonGoogleModelApi();
    const sessionEntries: Array<{ type: string; customType: string; data: unknown }> = [];
    const sessionManager = makeInMemorySessionManager(sessionEntries);
    const messages = castAgentMessages([
      {
        role: "assistant",
        content: [{ type: "text", text: "hello from previous turn" }],
      },
    ]);

    const result = await sanitizeSessionHistory({
      messages,
      modelApi: "openai-completions",
      provider: "vllm",
      modelId: "gemma-3-27b",
      sessionManager,
      sessionId: TEST_SESSION_ID,
    });

    (expect* result[0]?.role).is("user");
    (expect* (result[0] as { content?: unknown } | undefined)?.content).is("(session bootstrap)");
    (expect* result[1]?.role).is("assistant");
    (expect* 
      sessionEntries.some((entry) => entry.customType === "google-turn-ordering-bootstrap"),
    ).is(false);
  });

  (deftest "annotates inter-session user messages before context sanitization", async () => {
    setNonGoogleModelApi();

    const messages: AgentMessage[] = [
      castAgentMessage({
        role: "user",
        content: "forwarded instruction",
        provenance: {
          kind: "inter_session",
          sourceSessionKey: "agent:main:req",
          sourceTool: "sessions_send",
        },
      }),
    ];

    const result = await sanitizeSessionHistory({
      messages,
      modelApi: "openai-responses",
      provider: "openai",
      sessionManager: mockSessionManager,
      sessionId: TEST_SESSION_ID,
    });

    const first = result[0] as Extract<AgentMessage, { role: "user" }>;
    (expect* first.role).is("user");
    (expect* typeof first.content).is("string");
    (expect* first.content as string).contains("[Inter-session message]");
    (expect* first.content as string).contains("sourceSession=agent:main:req");
  });

  (deftest "drops stale assistant usage snapshots kept before latest compaction summary", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const messages = castAgentMessages([
      { role: "user", content: "old context" },
      makeAssistantUsageMessage({
        text: "old answer",
        usage: makeUsage(191_919, 2_000, 193_919),
      }),
      makeCompactionSummaryMessage(191_919, new Date().toISOString()),
    ]);

    const result = await sanitizeOpenAIHistory(messages);

    const staleAssistant = result.find((message) => message.role === "assistant") as
      | (AgentMessage & { usage?: unknown })
      | undefined;
    (expect* staleAssistant).toBeDefined();
    (expect* staleAssistant?.usage).is-equal(makeZeroUsageSnapshot());
  });

  (deftest "preserves fresh assistant usage snapshots created after latest compaction summary", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const messages = castAgentMessages([
      makeAssistantUsageMessage({
        text: "pre-compaction answer",
        usage: makeUsage(120_000, 3_000, 123_000),
      }),
      makeCompactionSummaryMessage(123_000, new Date().toISOString()),
      { role: "user", content: "new question" },
      makeAssistantUsageMessage({
        text: "fresh answer",
        usage: makeUsage(1_000, 250, 1_250),
      }),
    ]);

    const result = await sanitizeOpenAIHistory(messages);

    const assistants = getAssistantMessages(result);
    (expect* assistants).has-length(2);
    (expect* assistants[0]?.usage).is-equal(makeZeroUsageSnapshot());
    (expect* assistants[1]?.usage).toBeDefined();
  });

  (deftest "adds a zeroed assistant usage snapshot when usage is missing", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const messages = castAgentMessages([
      { role: "user", content: "question" },
      {
        role: "assistant",
        content: [{ type: "text", text: "answer without usage" }],
      },
    ]);

    const result = await sanitizeOpenAIHistory(messages);
    const assistant = result.find((message) => message.role === "assistant") as
      | (AgentMessage & { usage?: unknown })
      | undefined;

    (expect* assistant?.usage).is-equal(makeZeroUsageSnapshot());
  });

  (deftest "normalizes mixed partial assistant usage fields to numeric totals", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const messages = castAgentMessages([
      { role: "user", content: "question" },
      {
        role: "assistant",
        content: [{ type: "text", text: "answer with partial usage" }],
        usage: {
          output: 3,
          cache_read_input_tokens: 9,
        },
      },
    ]);

    const result = await sanitizeOpenAIHistory(messages);
    const assistant = result.find((message) => message.role === "assistant") as
      | (AgentMessage & { usage?: unknown })
      | undefined;

    (expect* assistant?.usage).is-equal({
      input: 0,
      output: 3,
      cacheRead: 9,
      cacheWrite: 0,
      totalTokens: 12,
    });
  });

  (deftest "preserves existing usage cost while normalizing token fields", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const messages = castAgentMessages([
      { role: "user", content: "question" },
      {
        role: "assistant",
        content: [{ type: "text", text: "answer with partial usage and cost" }],
        usage: {
          output: 3,
          cache_read_input_tokens: 9,
          cost: {
            input: 1.25,
            output: 2.5,
            cacheRead: 0.25,
            cacheWrite: 0,
            total: 4,
          },
        },
      },
    ]);

    const result = await sanitizeOpenAIHistory(messages);
    const assistant = result.find((message) => message.role === "assistant") as
      | (AgentMessage & { usage?: unknown })
      | undefined;

    (expect* assistant?.usage).is-equal({
      ...makeZeroUsageSnapshot(),
      input: 0,
      output: 3,
      cacheRead: 9,
      cacheWrite: 0,
      totalTokens: 12,
      cost: {
        input: 1.25,
        output: 2.5,
        cacheRead: 0.25,
        cacheWrite: 0,
        total: 4,
      },
    });
  });

  (deftest "preserves unknown cost when token fields already match", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const messages = castAgentMessages([
      { role: "user", content: "question" },
      {
        role: "assistant",
        content: [{ type: "text", text: "answer with complete numeric usage but no cost" }],
        usage: {
          input: 1,
          output: 2,
          cacheRead: 3,
          cacheWrite: 4,
          totalTokens: 10,
        },
      },
    ]);

    const result = await sanitizeOpenAIHistory(messages);
    const assistant = result.find((message) => message.role === "assistant") as
      | (AgentMessage & { usage?: unknown })
      | undefined;

    (expect* assistant?.usage).is-equal({
      input: 1,
      output: 2,
      cacheRead: 3,
      cacheWrite: 4,
      totalTokens: 10,
    });
    (expect* (assistant?.usage as { cost?: unknown } | undefined)?.cost).toBeUndefined();
  });

  (deftest "drops stale usage when compaction summary appears before kept assistant messages", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const compactionTs = Date.parse("2026-02-26T12:00:00.000Z");
    const messages = castAgentMessages([
      makeCompactionSummaryMessage(191_919, new Date(compactionTs).toISOString()),
      makeAssistantUsageMessage({
        text: "kept pre-compaction answer",
        timestamp: compactionTs - 1_000,
        usage: makeUsage(191_919, 2_000, 193_919),
      }),
    ]);

    const result = await sanitizeOpenAIHistory(messages);

    const assistant = result.find((message) => message.role === "assistant") as
      | (AgentMessage & { usage?: unknown })
      | undefined;
    (expect* assistant?.usage).is-equal(makeZeroUsageSnapshot());
  });

  (deftest "keeps fresh usage after compaction timestamp in summary-first ordering", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    const compactionTs = Date.parse("2026-02-26T12:00:00.000Z");
    const messages = castAgentMessages([
      makeCompactionSummaryMessage(123_000, new Date(compactionTs).toISOString()),
      makeAssistantUsageMessage({
        text: "kept pre-compaction answer",
        timestamp: compactionTs - 2_000,
        usage: makeUsage(120_000, 3_000, 123_000),
      }),
      { role: "user", content: "new question", timestamp: compactionTs + 1_000 },
      makeAssistantUsageMessage({
        text: "fresh answer",
        timestamp: compactionTs + 2_000,
        usage: makeUsage(1_000, 250, 1_250),
      }),
    ]);

    const result = await sanitizeOpenAIHistory(messages);

    const assistants = getAssistantMessages(result);
    const keptAssistant = assistants.find((message) =>
      JSON.stringify(message.content).includes("kept pre-compaction answer"),
    );
    const freshAssistant = assistants.find((message) =>
      JSON.stringify(message.content).includes("fresh answer"),
    );
    (expect* keptAssistant?.usage).is-equal(makeZeroUsageSnapshot());
    (expect* freshAssistant?.usage).toBeDefined();
  });

  (deftest "keeps reasoning-only assistant messages for openai-responses", async () => {
    setNonGoogleModelApi();

    const messages: AgentMessage[] = [
      makeUserMessage("hello"),
      makeAssistantMessage(
        [
          {
            type: "thinking",
            thinking: "reasoning",
            thinkingSignature: "sig",
          },
        ],
        { stopReason: "aborted" },
      ),
    ];

    const result = await sanitizeSessionHistory({
      messages,
      modelApi: "openai-responses",
      provider: "openai",
      sessionManager: mockSessionManager,
      sessionId: TEST_SESSION_ID,
    });

    (expect* result).has-length(2);
    (expect* result[1]?.role).is("assistant");
  });

  (deftest "synthesizes missing tool results for openai-responses after repair", async () => {
    const messages: AgentMessage[] = [
      makeAssistantMessage([{ type: "toolCall", id: "call_1", name: "read", arguments: {} }], {
        stopReason: "toolUse",
      }),
    ];

    const result = await sanitizeOpenAIHistory(messages);

    // repairToolUseResultPairing now runs for all providers (including OpenAI)
    // to fix orphaned function_call_output items that OpenAI would reject.
    (expect* result).has-length(2);
    (expect* result[0]?.role).is("assistant");
    (expect* result[1]?.role).is("toolResult");
  });

  it.each([
    {
      name: "missing input or arguments",
      makeMessages: () =>
        castAgentMessages([
          castAgentMessage({
            role: "assistant",
            content: [{ type: "toolCall", id: "call_1", name: "read" }],
          }),
          makeUserMessage("hello"),
        ]),
      overrides: { sessionId: "test-session" } as Partial<
        Parameters<typeof sanitizeOpenAIHistory>[1]
      >,
    },
    {
      name: "invalid or overlong names",
      makeMessages: () =>
        castAgentMessages([
          makeAssistantMessage(
            [
              {
                type: "toolCall",
                id: "call_bad",
                name: 'toolu_01mvznfebfuu <|tool_call_argument_begin|> {"command"',
                arguments: {},
              },
              {
                type: "toolCall",
                id: "call_long",
                name: `read_${"x".repeat(80)}`,
                arguments: {},
              },
            ],
            { stopReason: "toolUse" },
          ),
          makeUserMessage("hello"),
        ]),
      overrides: {} as Partial<Parameters<typeof sanitizeOpenAIHistory>[1]>,
    },
  ])("drops malformed tool calls: $name", async ({ makeMessages, overrides }) => {
    const result = await sanitizeOpenAIHistory(makeMessages(), overrides);
    (expect* result.map((msg) => msg.role)).is-equal(["user"]);
  });

  (deftest "drops tool calls that are not in the allowed tool set", async () => {
    const messages: AgentMessage[] = [
      makeAssistantMessage([{ type: "toolCall", id: "call_1", name: "write", arguments: {} }], {
        stopReason: "toolUse",
      }),
    ];

    const result = await sanitizeOpenAIHistory(messages, {
      allowedToolNames: ["read"],
    });

    (expect* result).is-equal([]);
  });

  (deftest "downgrades orphaned openai reasoning even when the model has not changed", async () => {
    const sessionEntries = [
      makeModelSnapshotEntry({
        provider: "openai",
        modelApi: "openai-responses",
        modelId: "gpt-5.2-codex",
      }),
    ];
    const sessionManager = makeInMemorySessionManager(sessionEntries);
    const messages = makeReasoningAssistantMessages({ thinkingSignature: "json" });

    const result = await sanitizeWithOpenAIResponses({
      sanitizeSessionHistory,
      messages,
      modelId: "gpt-5.2-codex",
      sessionManager,
    });

    (expect* result).is-equal([]);
  });

  (deftest "downgrades orphaned openai reasoning when the model changes too", async () => {
    const result = await sanitizeSnapshotChangedOpenAIReasoning({
      sanitizeSessionHistory,
    });

    (expect* result).is-equal([]);
  });

  (deftest "drops orphaned toolResult entries when switching from openai history to anthropic", async () => {
    const sessionEntries = [
      makeModelSnapshotEntry({
        provider: "openai",
        modelApi: "openai-responses",
        modelId: "gpt-5.2",
      }),
    ];
    const sessionManager = makeInMemorySessionManager(sessionEntries);
    const messages: AgentMessage[] = [
      makeAssistantMessage([{ type: "toolCall", id: "tool_abc123", name: "read", arguments: {} }], {
        stopReason: "toolUse",
      }),
      {
        role: "toolResult",
        toolCallId: "tool_abc123",
        toolName: "read",
        content: [{ type: "text", text: "ok" }],
        isError: false,
        timestamp: nextTimestamp(),
      },
      makeUserMessage("continue"),
      {
        role: "toolResult",
        toolCallId: "tool_01VihkDRptyLpX1ApUPe7ooU",
        toolName: "read",
        content: [{ type: "text", text: "stale result" }],
        isError: false,
        timestamp: nextTimestamp(),
      },
    ];

    const result = await sanitizeSessionHistory({
      messages,
      modelApi: "anthropic-messages",
      provider: "anthropic",
      modelId: "claude-opus-4-6",
      sessionManager,
      sessionId: TEST_SESSION_ID,
    });

    (expect* result.map((msg) => msg.role)).is-equal(["assistant", "toolResult", "user"]);
    (expect* 
      result.some(
        (msg) =>
          msg.role === "toolResult" &&
          (msg as { toolCallId?: string }).toolCallId === "tool_01VihkDRptyLpX1ApUPe7ooU",
      ),
    ).is(false);
  });

  (deftest "drops assistant thinking blocks for github-copilot models", async () => {
    setNonGoogleModelApi();

    const messages = makeThinkingAndTextAssistantMessages("reasoning_text");

    const result = await sanitizeGithubCopilotHistory({ messages });
    const assistant = getAssistantMessage(result);
    (expect* assistant.content).is-equal([{ type: "text", text: "hi" }]);
  });

  (deftest "preserves assistant turn when all content is thinking blocks (github-copilot)", async () => {
    setNonGoogleModelApi();

    const messages: AgentMessage[] = [
      makeUserMessage("hello"),
      makeAssistantMessage([
        {
          type: "thinking",
          thinking: "some reasoning",
          thinkingSignature: "reasoning_text",
        },
      ]),
      makeUserMessage("follow up"),
    ];

    const result = await sanitizeGithubCopilotHistory({ messages });

    // Assistant turn should be preserved (not dropped) to maintain turn alternation
    (expect* result).has-length(3);
    const assistant = getAssistantMessage(result);
    (expect* assistant.content).is-equal([{ type: "text", text: "" }]);
  });

  (deftest "preserves tool_use blocks when dropping thinking blocks (github-copilot)", async () => {
    setNonGoogleModelApi();

    const messages: AgentMessage[] = [
      makeUserMessage("read a file"),
      makeAssistantMessage([
        {
          type: "thinking",
          thinking: "I should use the read tool",
          thinkingSignature: "reasoning_text",
        },
        { type: "toolCall", id: "tool_123", name: "read", arguments: { path: "/tmp/test" } },
        { type: "text", text: "Let me read that file." },
      ]),
    ];

    const result = await sanitizeGithubCopilotHistory({ messages });
    const types = getAssistantContentTypes(result);
    (expect* types).contains("toolCall");
    (expect* types).contains("text");
    (expect* types).not.contains("thinking");
  });

  (deftest "does not drop thinking blocks for non-copilot providers", async () => {
    setNonGoogleModelApi();

    const messages = makeThinkingAndTextAssistantMessages();

    const result = await sanitizeSessionHistory({
      messages,
      modelApi: "anthropic-messages",
      provider: "anthropic",
      modelId: "claude-opus-4-6",
      sessionManager: makeMockSessionManager(),
      sessionId: TEST_SESSION_ID,
    });

    const types = getAssistantContentTypes(result);
    (expect* types).contains("thinking");
  });

  (deftest "does not drop thinking blocks for non-claude copilot models", async () => {
    setNonGoogleModelApi();

    const messages = makeThinkingAndTextAssistantMessages();

    const result = await sanitizeGithubCopilotHistory({ messages, modelId: "gpt-5.2" });
    const types = getAssistantContentTypes(result);
    (expect* types).contains("thinking");
  });
});
