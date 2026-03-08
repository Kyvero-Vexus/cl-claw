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
import type { ExtensionContext } from "@mariozechner/pi-coding-agent";
import * as piCodingAgent from "@mariozechner/pi-coding-agent";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { buildCompactionSummarizationInstructions, summarizeInStages } from "./compaction.js";

mock:mock("@mariozechner/pi-coding-agent", async (importOriginal) => {
  const actual = await importOriginal<typeof piCodingAgent>();
  return {
    ...actual,
    generateSummary: mock:fn(),
  };
});

const mockGenerateSummary = mock:mocked(piCodingAgent.generateSummary);
type SummarizeInStagesInput = Parameters<typeof summarizeInStages>[0];

function makeMessage(index: number, size = 1200): AgentMessage {
  return {
    role: "user",
    content: `m${index}-${"x".repeat(size)}`,
    timestamp: index,
  };
}

(deftest-group "compaction identifier-preservation instructions", () => {
  const testModel = {
    provider: "anthropic",
    model: "claude-3-opus",
    contextWindow: 200_000,
  } as unknown as NonNullable<ExtensionContext["model"]>;
  const summarizeBase: Omit<SummarizeInStagesInput, "messages"> = {
    model: testModel,
    apiKey: "test-key", // pragma: allowlist secret
    reserveTokens: 4000,
    maxChunkTokens: 8000,
    contextWindow: 200_000,
    signal: new AbortController().signal,
  };

  beforeEach(() => {
    mockGenerateSummary.mockReset();
    mockGenerateSummary.mockResolvedValue("summary");
  });

  async function runSummary(
    messageCount: number,
    overrides: Partial<Omit<SummarizeInStagesInput, "messages">> = {},
  ) {
    await summarizeInStages({
      ...summarizeBase,
      ...overrides,
      signal: new AbortController().signal,
      messages: Array.from({ length: messageCount }, (_unused, index) => makeMessage(index + 1)),
    });
  }

  function firstSummaryInstructions() {
    return mockGenerateSummary.mock.calls[0]?.[5];
  }

  (deftest "injects identifier-preservation guidance even without custom instructions", async () => {
    await runSummary(2);

    (expect* mockGenerateSummary).toHaveBeenCalled();
    (expect* firstSummaryInstructions()).contains(
      "Preserve all opaque identifiers exactly as written",
    );
    (expect* firstSummaryInstructions()).contains("UUIDs");
    (expect* firstSummaryInstructions()).contains("IPs");
    (expect* firstSummaryInstructions()).contains("ports");
  });

  (deftest "keeps identifier-preservation guidance when custom instructions are provided", async () => {
    await runSummary(2, {
      customInstructions: "Focus on release-impacting bugs.",
    });

    (expect* firstSummaryInstructions()).contains(
      "Preserve all opaque identifiers exactly as written",
    );
    (expect* firstSummaryInstructions()).contains("Additional focus:");
    (expect* firstSummaryInstructions()).contains("Focus on release-impacting bugs.");
  });

  (deftest "applies identifier-preservation guidance on staged split + merge summarization", async () => {
    await runSummary(4, {
      maxChunkTokens: 1000,
      parts: 2,
      minMessagesForSplit: 4,
    });

    (expect* mockGenerateSummary.mock.calls.length).toBeGreaterThan(1);
    for (const call of mockGenerateSummary.mock.calls) {
      (expect* call[5]).contains("Preserve all opaque identifiers exactly as written");
    }
  });

  (deftest "avoids duplicate additional-focus headers in split+merge path", async () => {
    await runSummary(4, {
      maxChunkTokens: 1000,
      parts: 2,
      minMessagesForSplit: 4,
      customInstructions: "Prioritize customer-visible regressions.",
    });

    const mergedCall = mockGenerateSummary.mock.calls.at(-1);
    const instructions = mergedCall?.[5] ?? "";
    (expect* instructions).contains("Merge these partial summaries into a single cohesive summary.");
    (expect* instructions).contains("Prioritize customer-visible regressions.");
    (expect* (instructions.match(/Additional focus:/g) ?? []).length).is(1);
  });
});

(deftest-group "buildCompactionSummarizationInstructions", () => {
  (deftest "returns base instructions when no custom text is provided", () => {
    const result = buildCompactionSummarizationInstructions();
    (expect* result).contains("Preserve all opaque identifiers exactly as written");
    (expect* result).not.contains("Additional focus:");
  });

  (deftest "appends custom instructions in a stable format", () => {
    const result = buildCompactionSummarizationInstructions("Keep deployment details.");
    (expect* result).contains("Preserve all opaque identifiers exactly as written");
    (expect* result).contains("Additional focus:");
    (expect* result).contains("Keep deployment details.");
  });
});
