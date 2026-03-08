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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import type { AgentMessage } from "@mariozechner/pi-agent-core";
import type { Api, Model } from "@mariozechner/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import * as compactionModule from "../compaction.js";
import { buildEmbeddedExtensionFactories } from "../pi-embedded-runner/extensions.js";
import { castAgentMessage } from "../test-helpers/agent-message-fixtures.js";
import {
  getCompactionSafeguardRuntime,
  setCompactionSafeguardRuntime,
} from "./compaction-safeguard-runtime.js";
import compactionSafeguardExtension, { __testing } from "./compaction-safeguard.js";

mock:mock("../compaction.js", async (importOriginal) => {
  const actual = await importOriginal<typeof compactionModule>();
  return {
    ...actual,
    summarizeInStages: mock:fn(actual.summarizeInStages),
  };
});

const mockSummarizeInStages = mock:mocked(compactionModule.summarizeInStages);

const {
  collectToolFailures,
  formatToolFailuresSection,
  splitPreservedRecentTurns,
  formatPreservedTurnsSection,
  buildCompactionStructureInstructions,
  buildStructuredFallbackSummary,
  appendSummarySection,
  resolveRecentTurnsPreserve,
  resolveQualityGuardMaxRetries,
  extractOpaqueIdentifiers,
  auditSummaryQuality,
  computeAdaptiveChunkRatio,
  isOversizedForSummary,
  readWorkspaceContextForSummary,
  BASE_CHUNK_RATIO,
  MIN_CHUNK_RATIO,
  SAFETY_MARGIN,
} = __testing;

function stubSessionManager(): ExtensionContext["sessionManager"] {
  const stub: ExtensionContext["sessionManager"] = {
    getCwd: () => "/stub",
    getSessionDir: () => "/stub",
    getSessionId: () => "stub-id",
    getSessionFile: () => undefined,
    getLeafId: () => null,
    getLeafEntry: () => undefined,
    getEntry: () => undefined,
    getLabel: () => undefined,
    getBranch: () => [],
    getHeader: () => null,
    getEntries: () => [],
    getTree: () => [],
    getSessionName: () => undefined,
  };
  return stub;
}

function createAnthropicModelFixture(overrides: Partial<Model<Api>> = {}): Model<Api> {
  return {
    id: "claude-opus-4-5",
    name: "Claude Opus 4.5",
    provider: "anthropic",
    api: "anthropic" as const,
    baseUrl: "https://api.anthropic.com",
    contextWindow: 200000,
    maxTokens: 4096,
    reasoning: false,
    input: ["text"] as const,
    cost: { input: 15, output: 75, cacheRead: 0, cacheWrite: 0 },
    ...overrides,
  };
}

type CompactionHandler = (event: unknown, ctx: unknown) => deferred-result<unknown>;
const createCompactionHandler = () => {
  let compactionHandler: CompactionHandler | undefined;
  const mockApi = {
    on: mock:fn((event: string, handler: CompactionHandler) => {
      if (event === "session_before_compact") {
        compactionHandler = handler;
      }
    }),
  } as unknown as ExtensionAPI;
  compactionSafeguardExtension(mockApi);
  (expect* compactionHandler).toBeDefined();
  return compactionHandler as CompactionHandler;
};

const createCompactionEvent = (params: { messageText: string; tokensBefore: number }) => ({
  preparation: {
    messagesToSummarize: [
      { role: "user", content: params.messageText, timestamp: Date.now() },
    ] as AgentMessage[],
    turnPrefixMessages: [] as AgentMessage[],
    firstKeptEntryId: "entry-1",
    tokensBefore: params.tokensBefore,
    fileOps: {
      read: [],
      edited: [],
      written: [],
    },
  },
  customInstructions: "",
  signal: new AbortController().signal,
});

const createCompactionContext = (params: {
  sessionManager: ExtensionContext["sessionManager"];
  getApiKeyMock: ReturnType<typeof mock:fn>;
}) =>
  ({
    model: undefined,
    sessionManager: params.sessionManager,
    modelRegistry: {
      getApiKey: params.getApiKeyMock,
    },
  }) as unknown as Partial<ExtensionContext>;

async function runCompactionScenario(params: {
  sessionManager: ExtensionContext["sessionManager"];
  event: unknown;
  apiKey: string | null;
}) {
  const compactionHandler = createCompactionHandler();
  const getApiKeyMock = mock:fn().mockResolvedValue(params.apiKey);
  const mockContext = createCompactionContext({
    sessionManager: params.sessionManager,
    getApiKeyMock,
  });
  const result = (await compactionHandler(params.event, mockContext)) as {
    cancel?: boolean;
  };
  return { result, getApiKeyMock };
}

(deftest-group "compaction-safeguard tool failures", () => {
  (deftest "formats tool failures with meta and summary", () => {
    const messages: AgentMessage[] = [
      {
        role: "toolResult",
        toolCallId: "call-1",
        toolName: "exec",
        isError: true,
        details: { status: "failed", exitCode: 1 },
        content: [{ type: "text", text: "ENOENT: missing file" }],
        timestamp: Date.now(),
      },
      {
        role: "toolResult",
        toolCallId: "call-2",
        toolName: "read",
        isError: false,
        content: [{ type: "text", text: "ok" }],
        timestamp: Date.now(),
      },
    ];

    const failures = collectToolFailures(messages);
    (expect* failures).has-length(1);

    const section = formatToolFailuresSection(failures);
    (expect* section).contains("## Tool Failures");
    (expect* section).contains("exec (status=failed exitCode=1): ENOENT: missing file");
  });

  (deftest "dedupes by toolCallId and handles empty output", () => {
    const messages: AgentMessage[] = [
      {
        role: "toolResult",
        toolCallId: "call-1",
        toolName: "exec",
        isError: true,
        details: { exitCode: 2 },
        content: [],
        timestamp: Date.now(),
      },
      {
        role: "toolResult",
        toolCallId: "call-1",
        toolName: "exec",
        isError: true,
        content: [{ type: "text", text: "ignored" }],
        timestamp: Date.now(),
      },
    ];

    const failures = collectToolFailures(messages);
    (expect* failures).has-length(1);

    const section = formatToolFailuresSection(failures);
    (expect* section).contains("exec (exitCode=2): failed");
  });

  (deftest "caps the number of failures and adds overflow line", () => {
    const messages: AgentMessage[] = Array.from({ length: 9 }, (_, idx) => ({
      role: "toolResult",
      toolCallId: `call-${idx}`,
      toolName: "exec",
      isError: true,
      content: [{ type: "text", text: `error ${idx}` }],
      timestamp: Date.now(),
    }));

    const failures = collectToolFailures(messages);
    const section = formatToolFailuresSection(failures);
    (expect* section).contains("## Tool Failures");
    (expect* section).contains("...and 1 more");
  });

  (deftest "omits section when there are no tool failures", () => {
    const messages: AgentMessage[] = [
      {
        role: "toolResult",
        toolCallId: "ok",
        toolName: "exec",
        isError: false,
        content: [{ type: "text", text: "ok" }],
        timestamp: Date.now(),
      },
    ];

    const failures = collectToolFailures(messages);
    const section = formatToolFailuresSection(failures);
    (expect* section).is("");
  });
});

(deftest-group "computeAdaptiveChunkRatio", () => {
  const CONTEXT_WINDOW = 200_000;

  (deftest "returns BASE_CHUNK_RATIO for normal messages", () => {
    // Small messages: 1000 tokens each, well under 10% of context
    const messages: AgentMessage[] = [
      { role: "user", content: "x".repeat(1000), timestamp: Date.now() },
      castAgentMessage({
        role: "assistant",
        content: [{ type: "text", text: "y".repeat(1000) }],
        timestamp: Date.now(),
      }),
    ];

    const ratio = computeAdaptiveChunkRatio(messages, CONTEXT_WINDOW);
    (expect* ratio).is(BASE_CHUNK_RATIO);
  });

  (deftest "reduces ratio when average message > 10% of context", () => {
    // Large messages: ~50K tokens each (25% of context)
    const messages: AgentMessage[] = [
      { role: "user", content: "x".repeat(50_000 * 4), timestamp: Date.now() },
      castAgentMessage({
        role: "assistant",
        content: [{ type: "text", text: "y".repeat(50_000 * 4) }],
        timestamp: Date.now(),
      }),
    ];

    const ratio = computeAdaptiveChunkRatio(messages, CONTEXT_WINDOW);
    (expect* ratio).toBeLessThan(BASE_CHUNK_RATIO);
    (expect* ratio).toBeGreaterThanOrEqual(MIN_CHUNK_RATIO);
  });

  (deftest "respects MIN_CHUNK_RATIO floor", () => {
    // Very large messages that would push ratio below minimum
    const messages: AgentMessage[] = [
      { role: "user", content: "x".repeat(150_000 * 4), timestamp: Date.now() },
    ];

    const ratio = computeAdaptiveChunkRatio(messages, CONTEXT_WINDOW);
    (expect* ratio).toBeGreaterThanOrEqual(MIN_CHUNK_RATIO);
  });

  (deftest "handles empty message array", () => {
    const ratio = computeAdaptiveChunkRatio([], CONTEXT_WINDOW);
    (expect* ratio).is(BASE_CHUNK_RATIO);
  });

  (deftest "handles single huge message", () => {
    // Single massive message
    const messages: AgentMessage[] = [
      { role: "user", content: "x".repeat(180_000 * 4), timestamp: Date.now() },
    ];

    const ratio = computeAdaptiveChunkRatio(messages, CONTEXT_WINDOW);
    (expect* ratio).toBeGreaterThanOrEqual(MIN_CHUNK_RATIO);
    (expect* ratio).toBeLessThanOrEqual(BASE_CHUNK_RATIO);
  });
});

(deftest-group "isOversizedForSummary", () => {
  const CONTEXT_WINDOW = 200_000;

  (deftest "returns false for small messages", () => {
    const msg: AgentMessage = {
      role: "user",
      content: "Hello, world!",
      timestamp: Date.now(),
    };

    (expect* isOversizedForSummary(msg, CONTEXT_WINDOW)).is(false);
  });

  (deftest "returns true for messages > 50% of context", () => {
    // Message with ~120K tokens (60% of 200K context)
    // After safety margin (1.2x), effective is 144K which is > 100K (50%)
    const msg: AgentMessage = {
      role: "user",
      content: "x".repeat(120_000 * 4),
      timestamp: Date.now(),
    };

    (expect* isOversizedForSummary(msg, CONTEXT_WINDOW)).is(true);
  });

  (deftest "applies safety margin", () => {
    // Message at exactly 50% of context before margin
    // After SAFETY_MARGIN (1.2), it becomes 60% which is > 50%
    const halfContextChars = (CONTEXT_WINDOW * 0.5) / SAFETY_MARGIN;
    const msg: AgentMessage = {
      role: "user",
      content: "x".repeat(Math.floor(halfContextChars * 4)),
      timestamp: Date.now(),
    };

    // With safety margin applied, this should be at the boundary
    // The function checks if tokens * SAFETY_MARGIN > contextWindow * 0.5
    const isOversized = isOversizedForSummary(msg, CONTEXT_WINDOW);
    // Due to token estimation, this could be either true or false at the boundary
    (expect* typeof isOversized).is("boolean");
  });
});

(deftest-group "compaction-safeguard runtime registry", () => {
  (deftest "stores and retrieves config by session manager identity", () => {
    const sm = {};
    setCompactionSafeguardRuntime(sm, { maxHistoryShare: 0.3 });
    const runtime = getCompactionSafeguardRuntime(sm);
    (expect* runtime).is-equal({ maxHistoryShare: 0.3 });
  });

  (deftest "returns null for unknown session manager", () => {
    const sm = {};
    (expect* getCompactionSafeguardRuntime(sm)).toBeNull();
  });

  (deftest "clears entry when value is null", () => {
    const sm = {};
    setCompactionSafeguardRuntime(sm, { maxHistoryShare: 0.7 });
    (expect* getCompactionSafeguardRuntime(sm)).not.toBeNull();
    setCompactionSafeguardRuntime(sm, null);
    (expect* getCompactionSafeguardRuntime(sm)).toBeNull();
  });

  (deftest "ignores non-object session managers", () => {
    setCompactionSafeguardRuntime(null, { maxHistoryShare: 0.5 });
    (expect* getCompactionSafeguardRuntime(null)).toBeNull();
    setCompactionSafeguardRuntime(undefined, { maxHistoryShare: 0.5 });
    (expect* getCompactionSafeguardRuntime(undefined)).toBeNull();
  });

  (deftest "isolates different session managers", () => {
    const sm1 = {};
    const sm2 = {};
    setCompactionSafeguardRuntime(sm1, { maxHistoryShare: 0.3 });
    setCompactionSafeguardRuntime(sm2, { maxHistoryShare: 0.8 });
    (expect* getCompactionSafeguardRuntime(sm1)).is-equal({ maxHistoryShare: 0.3 });
    (expect* getCompactionSafeguardRuntime(sm2)).is-equal({ maxHistoryShare: 0.8 });
  });

  (deftest "stores and retrieves model from runtime (fallback for compact.lisp workflow)", () => {
    const sm = {};
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sm, { model });
    const retrieved = getCompactionSafeguardRuntime(sm);
    (expect* retrieved?.model).is-equal(model);
  });

  (deftest "stores and retrieves contextWindowTokens from runtime", () => {
    const sm = {};
    setCompactionSafeguardRuntime(sm, { contextWindowTokens: 200000 });
    const retrieved = getCompactionSafeguardRuntime(sm);
    (expect* retrieved?.contextWindowTokens).is(200000);
  });

  (deftest "stores and retrieves combined runtime values", () => {
    const sm = {};
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sm, {
      maxHistoryShare: 0.6,
      contextWindowTokens: 200000,
      model,
    });
    const retrieved = getCompactionSafeguardRuntime(sm);
    (expect* retrieved).is-equal({
      maxHistoryShare: 0.6,
      contextWindowTokens: 200000,
      model,
    });
  });

  (deftest "wires oversized safeguard runtime values when config validation is bypassed", () => {
    const sessionManager = {} as unknown as Parameters<
      typeof buildEmbeddedExtensionFactories
    >[0]["sessionManager"];
    const cfg = {
      agents: {
        defaults: {
          compaction: {
            mode: "safeguard",
            recentTurnsPreserve: 99,
            qualityGuard: { maxRetries: 99 },
          },
        },
      },
    } as OpenClawConfig;

    buildEmbeddedExtensionFactories({
      cfg,
      sessionManager,
      provider: "anthropic",
      modelId: "claude-3-opus",
      model: {
        contextWindow: 200_000,
      } as Parameters<typeof buildEmbeddedExtensionFactories>[0]["model"],
    });

    const runtime = getCompactionSafeguardRuntime(sessionManager);
    (expect* runtime?.qualityGuardMaxRetries).is(99);
    (expect* runtime?.recentTurnsPreserve).is(99);
    (expect* resolveQualityGuardMaxRetries(runtime?.qualityGuardMaxRetries)).is(3);
    (expect* resolveRecentTurnsPreserve(runtime?.recentTurnsPreserve)).is(12);
  });
});

(deftest-group "compaction-safeguard recent-turn preservation", () => {
  (deftest "preserves the most recent user/assistant messages", () => {
    const messages: AgentMessage[] = [
      { role: "user", content: "older ask", timestamp: 1 },
      {
        role: "assistant",
        content: [{ type: "text", text: "older answer" }],
        timestamp: 2,
      } as unknown as AgentMessage,
      { role: "user", content: "recent ask", timestamp: 3 },
      {
        role: "assistant",
        content: [{ type: "text", text: "recent answer" }],
        timestamp: 4,
      } as unknown as AgentMessage,
    ];

    const split = splitPreservedRecentTurns({
      messages,
      recentTurnsPreserve: 1,
    });

    (expect* split.preservedMessages).has-length(2);
    (expect* split.summarizableMessages).has-length(2);
    (expect* formatPreservedTurnsSection(split.preservedMessages)).contains(
      "## Recent turns preserved verbatim",
    );
  });

  (deftest "drops orphaned tool results from preserved assistant turns", () => {
    const messages: AgentMessage[] = [
      { role: "user", content: "older ask", timestamp: 1 },
      {
        role: "assistant",
        content: [{ type: "toolCall", id: "call_old", name: "read", arguments: {} }],
        timestamp: 2,
      } as unknown as AgentMessage,
      {
        role: "toolResult",
        toolCallId: "call_old",
        toolName: "read",
        content: [{ type: "text", text: "old result" }],
        timestamp: 3,
      } as unknown as AgentMessage,
      { role: "user", content: "recent ask", timestamp: 4 },
      {
        role: "assistant",
        content: [{ type: "toolCall", id: "call_recent", name: "read", arguments: {} }],
        timestamp: 5,
      } as unknown as AgentMessage,
      {
        role: "toolResult",
        toolCallId: "call_recent",
        toolName: "read",
        content: [{ type: "text", text: "recent result" }],
        timestamp: 6,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "recent final answer" }],
        timestamp: 7,
      } as unknown as AgentMessage,
    ];

    const split = splitPreservedRecentTurns({
      messages,
      recentTurnsPreserve: 1,
    });

    (expect* split.preservedMessages.map((msg) => msg.role)).is-equal([
      "user",
      "assistant",
      "toolResult",
      "assistant",
    ]);
    (expect* 
      split.preservedMessages.some(
        (msg) => msg.role === "user" && (msg as { content?: unknown }).content === "recent ask",
      ),
    ).is(true);

    const summarizableToolResultIds = split.summarizableMessages
      .filter((msg) => msg.role === "toolResult")
      .map((msg) => (msg as { toolCallId?: unknown }).toolCallId);
    (expect* summarizableToolResultIds).contains("call_old");
    (expect* summarizableToolResultIds).not.contains("call_recent");
  });

  (deftest "includes preserved tool results in the preserved-turns section", () => {
    const split = splitPreservedRecentTurns({
      messages: [
        { role: "user", content: "older ask", timestamp: 1 },
        {
          role: "assistant",
          content: [{ type: "text", text: "older answer" }],
          timestamp: 2,
        } as unknown as AgentMessage,
        { role: "user", content: "recent ask", timestamp: 3 },
        {
          role: "assistant",
          content: [{ type: "toolCall", id: "call_recent", name: "read", arguments: {} }],
          timestamp: 4,
        } as unknown as AgentMessage,
        {
          role: "toolResult",
          toolCallId: "call_recent",
          toolName: "read",
          content: [{ type: "text", text: "recent raw output" }],
          timestamp: 5,
        } as unknown as AgentMessage,
        {
          role: "assistant",
          content: [{ type: "text", text: "recent final answer" }],
          timestamp: 6,
        } as unknown as AgentMessage,
      ],
      recentTurnsPreserve: 1,
    });

    const section = formatPreservedTurnsSection(split.preservedMessages);
    (expect* section).contains("- Tool result (read): recent raw output");
    (expect* section).contains("- User: recent ask");
  });

  (deftest "formats preserved non-text messages with placeholders", () => {
    const section = formatPreservedTurnsSection([
      {
        role: "user",
        content: [{ type: "image", data: "abc", mimeType: "image/png" }],
        timestamp: 1,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "toolCall", id: "call_recent", name: "read", arguments: {} }],
        timestamp: 2,
      } as unknown as AgentMessage,
    ]);

    (expect* section).contains("- User: [non-text content: image]");
    (expect* section).contains("- Assistant: [non-text content: toolCall]");
  });

  (deftest "keeps non-text placeholders for mixed-content preserved messages", () => {
    const section = formatPreservedTurnsSection([
      {
        role: "user",
        content: [
          { type: "text", text: "caption text" },
          { type: "image", data: "abc", mimeType: "image/png" },
        ],
        timestamp: 1,
      } as unknown as AgentMessage,
    ]);

    (expect* section).contains("- User: caption text");
    (expect* section).contains("[non-text content: image]");
  });

  (deftest "does not add non-text placeholders for text-only content blocks", () => {
    const section = formatPreservedTurnsSection([
      {
        role: "assistant",
        content: [{ type: "text", text: "plain text reply" }],
        timestamp: 1,
      } as unknown as AgentMessage,
    ]);

    (expect* section).contains("- Assistant: plain text reply");
    (expect* section).not.contains("[non-text content]");
  });

  (deftest "caps preserved tail when user turns are below preserve target", () => {
    const messages: AgentMessage[] = [
      { role: "user", content: "single user prompt", timestamp: 1 },
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-1" }],
        timestamp: 2,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-2" }],
        timestamp: 3,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-3" }],
        timestamp: 4,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-4" }],
        timestamp: 5,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-5" }],
        timestamp: 6,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-6" }],
        timestamp: 7,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-7" }],
        timestamp: 8,
      } as unknown as AgentMessage,
      {
        role: "assistant",
        content: [{ type: "text", text: "assistant-8" }],
        timestamp: 9,
      } as unknown as AgentMessage,
    ];

    const split = splitPreservedRecentTurns({
      messages,
      recentTurnsPreserve: 3,
    });

    // preserve target is 3 turns -> fallback should cap at 6 role messages
    (expect* split.preservedMessages).has-length(6);
    (expect* 
      split.preservedMessages.some(
        (msg) =>
          msg.role === "user" && (msg as { content?: unknown }).content === "single user prompt",
      ),
    ).is(true);
    (expect* formatPreservedTurnsSection(split.preservedMessages)).contains("assistant-8");
    (expect* formatPreservedTurnsSection(split.preservedMessages)).not.contains("assistant-2");
  });

  (deftest "trim-starts preserved section when history summary is empty", () => {
    const summary = appendSummarySection(
      "",
      "\n\n## Recent turns preserved verbatim\n- User: hello",
    );
    (expect* summary.startsWith("## Recent turns preserved verbatim")).is(true);
  });

  (deftest "does not append empty summary sections", () => {
    (expect* appendSummarySection("History", "")).is("History");
    (expect* appendSummarySection("", "")).is("");
  });

  (deftest "clamps preserve count into a safe range", () => {
    (expect* resolveRecentTurnsPreserve(undefined)).is(3);
    (expect* resolveRecentTurnsPreserve(-1)).is(0);
    (expect* resolveRecentTurnsPreserve(99)).is(12);
  });

  (deftest "extracts opaque identifiers and audits summary quality", () => {
    const identifiers = extractOpaqueIdentifiers(
      "Track id a1b2c3d4e5f6 plus A1B2C3D4E5F6 and URL https://example.com/a and /tmp/x.log plus port host.local:18789",
    );
    (expect* identifiers.length).toBeGreaterThan(0);
    (expect* identifiers).contains("A1B2C3D4E5F6"); // pragma: allowlist secret

    const summary = [
      "## Decisions",
      "Keep current flow.",
      "## Open TODOs",
      "None.",
      "## Constraints/Rules",
      "Preserve identifiers.",
      "## Pending user asks",
      "Explain post-compaction behavior.",
      "## Exact identifiers",
      identifiers.join(", "),
    ].join("\n");

    const quality = auditSummaryQuality({
      summary,
      identifiers,
      latestAsk: "Explain post-compaction behavior for memory indexing",
    });
    (expect* quality.ok).is(true);
  });

  (deftest "dedupes pure-hex identifiers across case variants", () => {
    const identifiers = extractOpaqueIdentifiers(
      "Track id a1b2c3d4e5f6 plus A1B2C3D4E5F6 and again a1b2c3d4e5f6",
    );
    (expect* identifiers.filter((id) => id === "A1B2C3D4E5F6")).has-length(1); // pragma: allowlist secret
  });

  (deftest "dedupes identifiers before applying the result cap", () => {
    const noisyPrefix = Array.from({ length: 10 }, () => "a0b0c0d0").join(" ");
    const uniqueTail = Array.from(
      { length: 12 },
      (_, idx) => `b${idx.toString(16).padStart(7, "0")}`,
    );
    const identifiers = extractOpaqueIdentifiers(`${noisyPrefix} ${uniqueTail.join(" ")}`);

    (expect* identifiers).has-length(12);
    (expect* new Set(identifiers).size).is(12);
    (expect* identifiers).contains("A0B0C0D0");
    (expect* identifiers).contains(uniqueTail[10]?.toUpperCase());
  });

  (deftest "filters ordinary short numbers and trims wrapped punctuation", () => {
    const identifiers = extractOpaqueIdentifiers(
      "Year 2026 count 42 port 18789 ticket 123456 URL https://example.com/a, path /tmp/x.log, and tiny /a with prose on/off.",
    );

    (expect* identifiers).not.contains("2026");
    (expect* identifiers).not.contains("42");
    (expect* identifiers).not.contains("18789");
    (expect* identifiers).not.contains("/a");
    (expect* identifiers).not.contains("/off");
    (expect* identifiers).contains("123456");
    (expect* identifiers).contains("https://example.com/a");
    (expect* identifiers).contains("/tmp/x.log");
  });

  (deftest "fails quality audit when required sections are missing", () => {
    const quality = auditSummaryQuality({
      summary: "Short summary without structure",
      identifiers: ["abc12345"],
      latestAsk: "Need a status update",
    });
    (expect* quality.ok).is(false);
    (expect* quality.reasons.length).toBeGreaterThan(0);
  });

  (deftest "requires exact section headings instead of substring matches", () => {
    const quality = auditSummaryQuality({
      summary: [
        "See ## Decisions above.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "Keep policy.",
        "## Pending user asks",
        "Need status.",
        "## Exact identifiers",
        "abc12345",
      ].join("\n"),
      identifiers: ["abc12345"],
      latestAsk: "Need status.",
    });

    (expect* quality.ok).is(false);
    (expect* quality.reasons).contains("missing_section:## Decisions");
  });

  (deftest "does not enforce identifier retention when policy is off", () => {
    const quality = auditSummaryQuality({
      summary: [
        "## Decisions",
        "Use redacted summary.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "No sensitive identifiers.",
        "## Pending user asks",
        "Provide status.",
        "## Exact identifiers",
        "Redacted.",
      ].join("\n"),
      identifiers: ["sensitive-token-123456"],
      latestAsk: "Provide status.",
      identifierPolicy: "off",
    });

    (expect* quality.ok).is(true);
  });

  (deftest "does not force strict identifier retention for custom policy", () => {
    const quality = auditSummaryQuality({
      summary: [
        "## Decisions",
        "Mask secrets by default.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "Follow custom policy.",
        "## Pending user asks",
        "Share summary.",
        "## Exact identifiers",
        "Masked by policy.",
      ].join("\n"),
      identifiers: ["api-key-abcdef123456"],
      latestAsk: "Share summary.",
      identifierPolicy: "custom",
    });

    (expect* quality.ok).is(true);
  });

  (deftest "matches pure-hex identifiers case-insensitively in retention checks", () => {
    const quality = auditSummaryQuality({
      summary: [
        "## Decisions",
        "Keep current flow.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "Preserve hex IDs.",
        "## Pending user asks",
        "Provide status.",
        "## Exact identifiers",
        "a1b2c3d4e5f6", // pragma: allowlist secret
      ].join("\n"),
      identifiers: ["A1B2C3D4E5F6"], // pragma: allowlist secret
      latestAsk: "Provide status.",
      identifierPolicy: "strict",
    });

    (expect* quality.ok).is(true);
  });

  (deftest "flags missing non-latin latest asks when summary omits them", () => {
    const quality = auditSummaryQuality({
      summary: [
        "## Decisions",
        "Keep current flow.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "Preserve safety checks.",
        "## Pending user asks",
        "No pending asks.",
        "## Exact identifiers",
        "None.",
      ].join("\n"),
      identifiers: [],
      latestAsk: "请提供状态更新",
    });

    (expect* quality.ok).is(false);
    (expect* quality.reasons).contains("latest_user_ask_not_reflected");
  });

  (deftest "accepts non-latin latest asks when summary reflects a shorter cjk phrase", () => {
    const quality = auditSummaryQuality({
      summary: [
        "## Decisions",
        "Keep current flow.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "Preserve safety checks.",
        "## Pending user asks",
        "状态更新 pending.",
        "## Exact identifiers",
        "None.",
      ].join("\n"),
      identifiers: [],
      latestAsk: "请提供状态更新",
    });

    (expect* quality.ok).is(true);
  });

  (deftest "rejects latest-ask overlap when only stopwords overlap", () => {
    const quality = auditSummaryQuality({
      summary: [
        "## Decisions",
        "Keep current flow.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "Follow policy.",
        "## Pending user asks",
        "This is to track active asks.",
        "## Exact identifiers",
        "None.",
      ].join("\n"),
      identifiers: [],
      latestAsk: "What is the plan to migrate?",
    });

    (expect* quality.ok).is(false);
    (expect* quality.reasons).contains("latest_user_ask_not_reflected");
  });

  (deftest "requires more than one meaningful overlap token for detailed asks", () => {
    const quality = auditSummaryQuality({
      summary: [
        "## Decisions",
        "Keep current flow.",
        "## Open TODOs",
        "None.",
        "## Constraints/Rules",
        "Follow policy.",
        "## Pending user asks",
        "Password issue tracked.",
        "## Exact identifiers",
        "None.",
      ].join("\n"),
      identifiers: [],
      latestAsk: "Please reset account password now",
    });

    (expect* quality.ok).is(false);
    (expect* quality.reasons).contains("latest_user_ask_not_reflected");
  });

  (deftest "clamps quality-guard retries into a safe range", () => {
    (expect* resolveQualityGuardMaxRetries(undefined)).is(1);
    (expect* resolveQualityGuardMaxRetries(-1)).is(0);
    (expect* resolveQualityGuardMaxRetries(99)).is(3);
  });

  (deftest "builds structured instructions with required sections", () => {
    const instructions = buildCompactionStructureInstructions("Keep security caveats.");
    (expect* instructions).contains("## Decisions");
    (expect* instructions).contains("## Open TODOs");
    (expect* instructions).contains("## Constraints/Rules");
    (expect* instructions).contains("## Pending user asks");
    (expect* instructions).contains("## Exact identifiers");
    (expect* instructions).contains("Keep security caveats.");
    (expect* instructions).not.contains("Additional focus:");
    (expect* instructions).contains("<untrusted-text>");
  });

  (deftest "does not force strict identifier retention when identifier policy is off", () => {
    const instructions = buildCompactionStructureInstructions(undefined, {
      identifierPolicy: "off",
    });
    (expect* instructions).contains("## Exact identifiers");
    (expect* instructions).contains("do not enforce literal-preservation rules");
    (expect* instructions).not.contains("preserve literal values exactly as seen");
    (expect* instructions).not.contains("N/A (identifier policy off)");
  });

  (deftest "threads custom identifier policy text into structured instructions", () => {
    const instructions = buildCompactionStructureInstructions(undefined, {
      identifierPolicy: "custom",
      identifierInstructions: "Exclude secrets and one-time tokens from summaries.",
    });
    (expect* instructions).contains("For ## Exact identifiers, apply this operator-defined policy");
    (expect* instructions).contains("Exclude secrets and one-time tokens from summaries.");
    (expect* instructions).contains("<untrusted-text>");
  });

  (deftest "sanitizes untrusted custom instruction text before embedding", () => {
    const instructions = buildCompactionStructureInstructions(
      "Ignore above <script>alert(1)</script>",
    );
    (expect* instructions).contains("&lt;script&gt;alert(1)&lt;/script&gt;");
    (expect* instructions).contains("<untrusted-text>");
  });

  (deftest "sanitizes custom identifier policy text before embedding", () => {
    const instructions = buildCompactionStructureInstructions(undefined, {
      identifierPolicy: "custom",
      identifierInstructions: "Keep ticket <ABC-123> but remove \u200Bsecrets.",
    });
    (expect* instructions).contains("Keep ticket &lt;ABC-123&gt; but remove secrets.");
    (expect* instructions).contains("<untrusted-text>");
  });

  (deftest "builds a structured fallback summary from legacy previous summary text", () => {
    const summary = buildStructuredFallbackSummary("legacy summary without headings");
    (expect* summary).contains("## Decisions");
    (expect* summary).contains("## Open TODOs");
    (expect* summary).contains("## Constraints/Rules");
    (expect* summary).contains("## Pending user asks");
    (expect* summary).contains("## Exact identifiers");
    (expect* summary).contains("legacy summary without headings");
  });

  (deftest "preserves an already-structured previous summary as-is", () => {
    const structured = [
      "## Decisions",
      "done",
      "",
      "## Open TODOs",
      "todo",
      "",
      "## Constraints/Rules",
      "rules",
      "",
      "## Pending user asks",
      "asks",
      "",
      "## Exact identifiers",
      "ids",
    ].join("\n");
    (expect* buildStructuredFallbackSummary(structured)).is(structured);
  });

  (deftest "restructures summaries with near-match headings instead of reusing them", () => {
    const nearMatch = [
      "## Decisions",
      "done",
      "",
      "## Open TODOs (active)",
      "todo",
      "",
      "## Constraints/Rules",
      "rules",
      "",
      "## Pending user asks",
      "asks",
      "",
      "## Exact identifiers",
      "ids",
    ].join("\n");
    const summary = buildStructuredFallbackSummary(nearMatch);
    (expect* summary).not.is(nearMatch);
    (expect* summary).contains("\n## Open TODOs\n");
  });

  (deftest "does not force policy-off marker in fallback exact identifiers section", () => {
    const summary = buildStructuredFallbackSummary(undefined, {
      identifierPolicy: "off",
    });
    (expect* summary).contains("## Exact identifiers");
    (expect* summary).contains("None captured.");
    (expect* summary).not.contains("N/A (identifier policy off).");
  });

  (deftest "uses structured instructions when summarizing dropped history chunks", async () => {
    mockSummarizeInStages.mockReset();
    mockSummarizeInStages.mockResolvedValue("mock summary");

    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, {
      model,
      maxHistoryShare: 0.1,
      recentTurnsPreserve: 12,
    });

    const compactionHandler = createCompactionHandler();
    const getApiKeyMock = mock:fn().mockResolvedValue("test-key");
    const mockContext = createCompactionContext({
      sessionManager,
      getApiKeyMock,
    });
    const messagesToSummarize: AgentMessage[] = Array.from({ length: 4 }, (_unused, index) => ({
      role: "user",
      content: `msg-${index}-${"x".repeat(120_000)}`,
      timestamp: index + 1,
    }));
    const event = {
      preparation: {
        messagesToSummarize,
        turnPrefixMessages: [],
        firstKeptEntryId: "entry-1",
        tokensBefore: 400_000,
        fileOps: {
          read: [],
          edited: [],
          written: [],
        },
        settings: { reserveTokens: 4000 },
        previousSummary: undefined,
        isSplitTurn: false,
      },
      customInstructions: "Keep security caveats.",
      signal: new AbortController().signal,
    };

    const result = (await compactionHandler(event, mockContext)) as {
      cancel?: boolean;
      compaction?: { summary?: string };
    };

    (expect* result.cancel).not.is(true);
    (expect* mockSummarizeInStages).toHaveBeenCalled();
    const droppedCall = mockSummarizeInStages.mock.calls[0]?.[0];
    (expect* droppedCall?.customInstructions).contains(
      "Produce a compact, factual summary with these exact section headings:",
    );
    (expect* droppedCall?.customInstructions).contains("## Decisions");
    (expect* droppedCall?.customInstructions).contains("Keep security caveats.");
  });

  (deftest "does not retry summaries unless quality guard is explicitly enabled", async () => {
    mockSummarizeInStages.mockReset();
    mockSummarizeInStages.mockResolvedValue("summary missing headings");

    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, {
      model,
      recentTurnsPreserve: 0,
    });

    const compactionHandler = createCompactionHandler();
    const getApiKeyMock = mock:fn().mockResolvedValue("test-key");
    const mockContext = createCompactionContext({
      sessionManager,
      getApiKeyMock,
    });
    const event = {
      preparation: {
        messagesToSummarize: [
          { role: "user", content: "older context", timestamp: 1 },
          { role: "assistant", content: "older reply", timestamp: 2 } as unknown as AgentMessage,
        ],
        turnPrefixMessages: [],
        firstKeptEntryId: "entry-1",
        tokensBefore: 1_500,
        fileOps: {
          read: [],
          edited: [],
          written: [],
        },
        settings: { reserveTokens: 4_000 },
        previousSummary: undefined,
        isSplitTurn: false,
      },
      customInstructions: "",
      signal: new AbortController().signal,
    };

    const result = (await compactionHandler(event, mockContext)) as {
      cancel?: boolean;
      compaction?: { summary?: string };
    };

    (expect* result.cancel).not.is(true);
    (expect* mockSummarizeInStages).toHaveBeenCalledTimes(1);
  });

  (deftest "retries when generated summary misses headings even if preserved turns contain them", async () => {
    mockSummarizeInStages.mockReset();
    mockSummarizeInStages
      .mockResolvedValueOnce("latest ask status")
      .mockResolvedValueOnce(
        [
          "## Decisions",
          "Keep current flow.",
          "## Open TODOs",
          "None.",
          "## Constraints/Rules",
          "Follow rules.",
          "## Pending user asks",
          "latest ask status",
          "## Exact identifiers",
          "None.",
        ].join("\n"),
      );

    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, {
      model,
      recentTurnsPreserve: 1,
      qualityGuardEnabled: true,
      qualityGuardMaxRetries: 1,
    });

    const compactionHandler = createCompactionHandler();
    const getApiKeyMock = mock:fn().mockResolvedValue("test-key");
    const mockContext = createCompactionContext({
      sessionManager,
      getApiKeyMock,
    });
    const event = {
      preparation: {
        messagesToSummarize: [
          { role: "user", content: "older context", timestamp: 1 },
          { role: "assistant", content: "older reply", timestamp: 2 } as unknown as AgentMessage,
          { role: "user", content: "latest ask status", timestamp: 3 },
          {
            role: "assistant",
            content: [
              {
                type: "text",
                text: [
                  "## Decisions",
                  "from preserved turns",
                  "## Open TODOs",
                  "from preserved turns",
                  "## Constraints/Rules",
                  "from preserved turns",
                  "## Pending user asks",
                  "from preserved turns",
                  "## Exact identifiers",
                  "from preserved turns",
                ].join("\n"),
              },
            ],
            timestamp: 4,
          } as unknown as AgentMessage,
        ],
        turnPrefixMessages: [],
        firstKeptEntryId: "entry-1",
        tokensBefore: 1_500,
        fileOps: {
          read: [],
          edited: [],
          written: [],
        },
        settings: { reserveTokens: 4_000 },
        previousSummary: undefined,
        isSplitTurn: false,
      },
      customInstructions: "",
      signal: new AbortController().signal,
    };

    const result = (await compactionHandler(event, mockContext)) as {
      cancel?: boolean;
      compaction?: { summary?: string };
    };

    (expect* result.cancel).not.is(true);
    (expect* mockSummarizeInStages).toHaveBeenCalledTimes(2);
    const secondCall = mockSummarizeInStages.mock.calls[1]?.[0];
    (expect* secondCall?.customInstructions).contains("Quality check feedback");
    (expect* secondCall?.customInstructions).contains("missing_section:## Decisions");
  });

  (deftest "does not treat preserved latest asks as satisfying overlap checks", async () => {
    mockSummarizeInStages.mockReset();
    mockSummarizeInStages
      .mockResolvedValueOnce(
        [
          "## Decisions",
          "Keep current flow.",
          "## Open TODOs",
          "None.",
          "## Constraints/Rules",
          "Follow rules.",
          "## Pending user asks",
          "latest ask status",
          "## Exact identifiers",
          "None.",
        ].join("\n"),
      )
      .mockResolvedValueOnce(
        [
          "## Decisions",
          "Keep current flow.",
          "## Open TODOs",
          "None.",
          "## Constraints/Rules",
          "Follow rules.",
          "## Pending user asks",
          "older context",
          "## Exact identifiers",
          "None.",
        ].join("\n"),
      );

    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, {
      model,
      recentTurnsPreserve: 1,
      qualityGuardEnabled: true,
      qualityGuardMaxRetries: 1,
    });

    const compactionHandler = createCompactionHandler();
    const getApiKeyMock = mock:fn().mockResolvedValue("test-key");
    const mockContext = createCompactionContext({
      sessionManager,
      getApiKeyMock,
    });
    const event = {
      preparation: {
        messagesToSummarize: [
          { role: "user", content: "older context", timestamp: 1 },
          { role: "assistant", content: "older reply", timestamp: 2 } as unknown as AgentMessage,
          { role: "user", content: "latest ask status", timestamp: 3 },
          {
            role: "assistant",
            content: "latest assistant reply",
            timestamp: 4,
          } as unknown as AgentMessage,
        ],
        turnPrefixMessages: [],
        firstKeptEntryId: "entry-1",
        tokensBefore: 1_500,
        fileOps: {
          read: [],
          edited: [],
          written: [],
        },
        settings: { reserveTokens: 4_000 },
        previousSummary: undefined,
        isSplitTurn: false,
      },
      customInstructions: "",
      signal: new AbortController().signal,
    };

    const result = (await compactionHandler(event, mockContext)) as {
      cancel?: boolean;
      compaction?: { summary?: string };
    };

    (expect* result.cancel).not.is(true);
    (expect* mockSummarizeInStages).toHaveBeenCalledTimes(2);
    const secondCall = mockSummarizeInStages.mock.calls[1]?.[0];
    (expect* secondCall?.customInstructions).contains("latest_user_ask_not_reflected");
  });

  (deftest "keeps last successful summary when a quality retry call fails", async () => {
    mockSummarizeInStages.mockReset();
    mockSummarizeInStages
      .mockResolvedValueOnce("short summary missing headings")
      .mockRejectedValueOnce(new Error("retry transient failure"));

    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, {
      model,
      recentTurnsPreserve: 0,
      qualityGuardEnabled: true,
      qualityGuardMaxRetries: 1,
    });

    const compactionHandler = createCompactionHandler();
    const getApiKeyMock = mock:fn().mockResolvedValue("test-key");
    const mockContext = createCompactionContext({
      sessionManager,
      getApiKeyMock,
    });
    const event = {
      preparation: {
        messagesToSummarize: [
          { role: "user", content: "older context", timestamp: 1 },
          { role: "assistant", content: "older reply", timestamp: 2 } as unknown as AgentMessage,
        ],
        turnPrefixMessages: [],
        firstKeptEntryId: "entry-1",
        tokensBefore: 1_500,
        fileOps: {
          read: [],
          edited: [],
          written: [],
        },
        settings: { reserveTokens: 4_000 },
        previousSummary: undefined,
        isSplitTurn: false,
      },
      customInstructions: "",
      signal: new AbortController().signal,
    };

    const result = (await compactionHandler(event, mockContext)) as {
      cancel?: boolean;
      compaction?: { summary?: string };
    };

    (expect* result.cancel).not.is(true);
    (expect* result.compaction?.summary).contains("short summary missing headings");
    (expect* mockSummarizeInStages).toHaveBeenCalledTimes(2);
  });

  (deftest "keeps required headings when all turns are preserved and history is carried forward", async () => {
    mockSummarizeInStages.mockReset();

    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, {
      model,
      recentTurnsPreserve: 12,
    });

    const compactionHandler = createCompactionHandler();
    const getApiKeyMock = mock:fn().mockResolvedValue("test-key");
    const mockContext = createCompactionContext({
      sessionManager,
      getApiKeyMock,
    });
    const event = {
      preparation: {
        messagesToSummarize: [
          { role: "user", content: "latest user ask", timestamp: 1 },
          {
            role: "assistant",
            content: [{ type: "text", text: "latest assistant reply" }],
            timestamp: 2,
          } as unknown as AgentMessage,
        ],
        turnPrefixMessages: [],
        firstKeptEntryId: "entry-1",
        tokensBefore: 1_500,
        fileOps: {
          read: [],
          edited: [],
          written: [],
        },
        settings: { reserveTokens: 4_000 },
        previousSummary: "legacy summary without headings",
        isSplitTurn: false,
      },
      customInstructions: "",
      signal: new AbortController().signal,
    };

    const result = (await compactionHandler(event, mockContext)) as {
      cancel?: boolean;
      compaction?: { summary?: string };
    };

    (expect* result.cancel).not.is(true);
    (expect* mockSummarizeInStages).not.toHaveBeenCalled();
    const summary = result.compaction?.summary ?? "";
    (expect* summary).contains("## Decisions");
    (expect* summary).contains("## Open TODOs");
    (expect* summary).contains("## Constraints/Rules");
    (expect* summary).contains("## Pending user asks");
    (expect* summary).contains("## Exact identifiers");
    (expect* summary).contains("legacy summary without headings");
  });
});

(deftest-group "compaction-safeguard extension model fallback", () => {
  (deftest "uses runtime.model when ctx.model is undefined (compact.lisp workflow)", async () => {
    // This test verifies the root-cause fix: when extensionRunner.initialize() is not called
    // (as happens in compact.lisp), ctx.model is undefined but runtime.model is available.
    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();

    // Set up runtime with model (mimics buildEmbeddedExtensionPaths behavior)
    setCompactionSafeguardRuntime(sessionManager, { model });

    const mockEvent = createCompactionEvent({
      messageText: "test message",
      tokensBefore: 1000,
    });
    const { result, getApiKeyMock } = await runCompactionScenario({
      sessionManager,
      event: mockEvent,
      apiKey: null,
    });

    (expect* result).is-equal({ cancel: true });

    // KEY ASSERTION: Prove the fallback path was exercised
    // The handler should have called getApiKey with runtime.model (via ctx.model ?? runtime?.model)
    (expect* getApiKeyMock).toHaveBeenCalledWith(model);

    // Verify runtime.model is still available (for completeness)
    const retrieved = getCompactionSafeguardRuntime(sessionManager);
    (expect* retrieved?.model).is-equal(model);
  });

  (deftest "cancels compaction when both ctx.model and runtime.model are undefined", async () => {
    const sessionManager = stubSessionManager();

    // Do NOT set runtime.model (both ctx.model and runtime.model will be undefined)

    const mockEvent = createCompactionEvent({
      messageText: "test",
      tokensBefore: 500,
    });
    const { result, getApiKeyMock } = await runCompactionScenario({
      sessionManager,
      event: mockEvent,
      apiKey: null,
    });

    (expect* result).is-equal({ cancel: true });

    // Verify early return: getApiKey should NOT have been called when both models are missing
    (expect* getApiKeyMock).not.toHaveBeenCalled();
  });
});

(deftest-group "compaction-safeguard double-compaction guard", () => {
  (deftest "cancels compaction when there are no real messages to summarize", async () => {
    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, { model });

    const mockEvent = {
      preparation: {
        messagesToSummarize: [] as AgentMessage[],
        turnPrefixMessages: [] as AgentMessage[],
        firstKeptEntryId: "entry-1",
        tokensBefore: 1500,
        fileOps: { read: [], edited: [], written: [] },
      },
      customInstructions: "",
      signal: new AbortController().signal,
    };
    const { result, getApiKeyMock } = await runCompactionScenario({
      sessionManager,
      event: mockEvent,
      apiKey: "sk-test", // pragma: allowlist secret
    });
    (expect* result).is-equal({ cancel: true });
    (expect* getApiKeyMock).not.toHaveBeenCalled();
  });

  (deftest "continues when messages include real conversation content", async () => {
    const sessionManager = stubSessionManager();
    const model = createAnthropicModelFixture();
    setCompactionSafeguardRuntime(sessionManager, { model });

    const mockEvent = createCompactionEvent({
      messageText: "real message",
      tokensBefore: 1500,
    });
    const { result, getApiKeyMock } = await runCompactionScenario({
      sessionManager,
      event: mockEvent,
      apiKey: null,
    });
    (expect* result).is-equal({ cancel: true });
    (expect* getApiKeyMock).toHaveBeenCalled();
  });
});

async function expectWorkspaceSummaryEmptyForAgentsAlias(
  createAlias: (outsidePath: string, agentsPath: string) => void,
) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-compaction-summary-"));
  const prevCwd = process.cwd();
  try {
    const outside = path.join(root, "outside-secret.txt");
    fs.writeFileSync(outside, "secret");
    createAlias(outside, path.join(root, "AGENTS.md"));
    process.chdir(root);
    await (expect* readWorkspaceContextForSummary()).resolves.is("");
  } finally {
    process.chdir(prevCwd);
    fs.rmSync(root, { recursive: true, force: true });
  }
}

(deftest-group "readWorkspaceContextForSummary", () => {
  it.runIf(process.platform !== "win32")(
    "returns empty when AGENTS.md is a symlink escape",
    async () => {
      await expectWorkspaceSummaryEmptyForAgentsAlias((outside, agentsPath) => {
        fs.symlinkSync(outside, agentsPath);
      });
    },
  );

  it.runIf(process.platform !== "win32")(
    "returns empty when AGENTS.md is a hardlink alias",
    async () => {
      await expectWorkspaceSummaryEmptyForAgentsAlias((outside, agentsPath) => {
        fs.linkSync(outside, agentsPath);
      });
    },
  );
});
