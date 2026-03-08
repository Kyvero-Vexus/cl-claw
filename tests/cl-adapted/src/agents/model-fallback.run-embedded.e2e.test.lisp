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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import type { AssistantMessage } from "@mariozechner/pi-ai";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import type { AuthProfileFailureReason } from "./auth-profiles.js";
import { runWithModelFallback } from "./model-fallback.js";
import type { EmbeddedRunAttemptResult } from "./pi-embedded-runner/run/types.js";

const runEmbeddedAttemptMock = mock:fn<(params: unknown) => deferred-result<EmbeddedRunAttemptResult>>();
const { computeBackoffMock, sleepWithAbortMock } = mock:hoisted(() => ({
  computeBackoffMock: mock:fn(
    (
      _policy: { initialMs: number; maxMs: number; factor: number; jitter: number },
      _attempt: number,
    ) => 321,
  ),
  sleepWithAbortMock: mock:fn(async (_ms: number, _abortSignal?: AbortSignal) => undefined),
}));

mock:mock("./pi-embedded-runner/run/attempt.js", () => ({
  runEmbeddedAttempt: (params: unknown) => runEmbeddedAttemptMock(params),
}));

mock:mock("../infra/backoff.js", () => ({
  computeBackoff: (
    policy: { initialMs: number; maxMs: number; factor: number; jitter: number },
    attempt: number,
  ) => computeBackoffMock(policy, attempt),
  sleepWithAbort: (ms: number, abortSignal?: AbortSignal) => sleepWithAbortMock(ms, abortSignal),
}));

mock:mock("./models-config.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("./models-config.js")>();
  return {
    ...mod,
    ensureOpenClawModelsJson: mock:fn(async () => ({ wrote: false })),
  };
});

let runEmbeddedPiAgent: typeof import("./pi-embedded-runner/run.js").runEmbeddedPiAgent;

beforeAll(async () => {
  ({ runEmbeddedPiAgent } = await import("./pi-embedded-runner/run.js"));
});

beforeEach(() => {
  runEmbeddedAttemptMock.mockReset();
  computeBackoffMock.mockClear();
  sleepWithAbortMock.mockClear();
});

const baseUsage = {
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

const OVERLOADED_ERROR_PAYLOAD =
  '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}';

const buildAssistant = (overrides: Partial<AssistantMessage>): AssistantMessage => ({
  role: "assistant",
  content: [],
  api: "openai-responses",
  provider: "openai",
  model: "mock-1",
  usage: baseUsage,
  stopReason: "stop",
  timestamp: Date.now(),
  ...overrides,
});

const makeAttempt = (overrides: Partial<EmbeddedRunAttemptResult>): EmbeddedRunAttemptResult => ({
  aborted: false,
  timedOut: false,
  timedOutDuringCompaction: false,
  promptError: null,
  sessionIdUsed: "session:test",
  systemPromptReport: undefined,
  messagesSnapshot: [],
  assistantTexts: [],
  toolMetas: [],
  lastAssistant: undefined,
  didSendViaMessagingTool: false,
  messagingToolSentTexts: [],
  messagingToolSentMediaUrls: [],
  messagingToolSentTargets: [],
  cloudCodeAssistFormatError: false,
  ...overrides,
});

function makeConfig(): OpenClawConfig {
  const apiKeyField = ["api", "Key"].join("");
  return {
    agents: {
      defaults: {
        model: {
          primary: "openai/mock-1",
          fallbacks: ["groq/mock-2"],
        },
      },
    },
    models: {
      providers: {
        openai: {
          api: "openai-responses",
          [apiKeyField]: "openai-test-key", // pragma: allowlist secret
          baseUrl: "https://example.com/openai",
          models: [
            {
              id: "mock-1",
              name: "Mock 1",
              reasoning: false,
              input: ["text"],
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
              contextWindow: 16_000,
              maxTokens: 2048,
            },
          ],
        },
        groq: {
          api: "openai-responses",
          [apiKeyField]: "groq-test-key", // pragma: allowlist secret
          baseUrl: "https://example.com/groq",
          models: [
            {
              id: "mock-2",
              name: "Mock 2",
              reasoning: false,
              input: ["text"],
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
              contextWindow: 16_000,
              maxTokens: 2048,
            },
          ],
        },
      },
    },
  } satisfies OpenClawConfig;
}

async function withAgentWorkspace<T>(
  fn: (ctx: { agentDir: string; workspaceDir: string }) => deferred-result<T>,
): deferred-result<T> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-model-fallback-"));
  const agentDir = path.join(root, "agent");
  const workspaceDir = path.join(root, "workspace");
  await fs.mkdir(agentDir, { recursive: true });
  await fs.mkdir(workspaceDir, { recursive: true });
  try {
    return await fn({ agentDir, workspaceDir });
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
}

async function writeAuthStore(
  agentDir: string,
  usageStats?: Record<
    string,
    {
      lastUsed?: number;
      cooldownUntil?: number;
      disabledUntil?: number;
      disabledReason?: AuthProfileFailureReason;
      failureCounts?: Partial<Record<AuthProfileFailureReason, number>>;
    }
  >,
) {
  await fs.writeFile(
    path.join(agentDir, "auth-profiles.json"),
    JSON.stringify({
      version: 1,
      profiles: {
        "openai:p1": { type: "api_key", provider: "openai", key: "sk-openai" },
        "groq:p1": { type: "api_key", provider: "groq", key: "sk-groq" },
      },
      usageStats:
        usageStats ??
        ({
          "openai:p1": { lastUsed: 1 },
          "groq:p1": { lastUsed: 2 },
        } as const),
    }),
  );
}

async function readUsageStats(agentDir: string) {
  const raw = await fs.readFile(path.join(agentDir, "auth-profiles.json"), "utf-8");
  return JSON.parse(raw).usageStats as Record<string, Record<string, unknown> | undefined>;
}

async function runEmbeddedFallback(params: {
  agentDir: string;
  workspaceDir: string;
  sessionKey: string;
  runId: string;
  abortSignal?: AbortSignal;
}) {
  const cfg = makeConfig();
  return await runWithModelFallback({
    cfg,
    provider: "openai",
    model: "mock-1",
    agentDir: params.agentDir,
    run: (provider, model, options) =>
      runEmbeddedPiAgent({
        sessionId: `session:${params.runId}`,
        sessionKey: params.sessionKey,
        sessionFile: path.join(params.workspaceDir, `${params.runId}.jsonl`),
        workspaceDir: params.workspaceDir,
        agentDir: params.agentDir,
        config: cfg,
        prompt: "hello",
        provider,
        model,
        authProfileIdSource: "auto",
        allowTransientCooldownProbe: options?.allowTransientCooldownProbe,
        timeoutMs: 5_000,
        runId: params.runId,
        abortSignal: params.abortSignal,
      }),
  });
}

function mockPrimaryOverloadedThenFallbackSuccess() {
  mockPrimaryErrorThenFallbackSuccess(OVERLOADED_ERROR_PAYLOAD);
}

function mockPrimaryErrorThenFallbackSuccess(errorMessage: string) {
  runEmbeddedAttemptMock.mockImplementation(async (params: unknown) => {
    const attemptParams = params as { provider: string; modelId: string; authProfileId?: string };
    if (attemptParams.provider === "openai") {
      return makeAttempt({
        assistantTexts: [],
        lastAssistant: buildAssistant({
          provider: "openai",
          model: "mock-1",
          stopReason: "error",
          errorMessage,
        }),
      });
    }
    if (attemptParams.provider === "groq") {
      return makeAttempt({
        assistantTexts: ["fallback ok"],
        lastAssistant: buildAssistant({
          provider: "groq",
          model: "mock-2",
          stopReason: "stop",
          content: [{ type: "text", text: "fallback ok" }],
        }),
      });
    }
    error(`Unexpected provider ${attemptParams.provider}`);
  });
}

function expectOpenAiThenGroqAttemptOrder(params?: { expectOpenAiAuthProfileId?: string }) {
  (expect* runEmbeddedAttemptMock).toHaveBeenCalledTimes(2);
  const firstCall = runEmbeddedAttemptMock.mock.calls[0]?.[0] as
    | { provider?: string; authProfileId?: string }
    | undefined;
  const secondCall = runEmbeddedAttemptMock.mock.calls[1]?.[0] as { provider?: string } | undefined;
  (expect* firstCall).toBeDefined();
  (expect* secondCall).toBeDefined();
  (expect* firstCall?.provider).is("openai");
  if (params?.expectOpenAiAuthProfileId) {
    (expect* firstCall?.authProfileId).is(params.expectOpenAiAuthProfileId);
  }
  (expect* secondCall?.provider).is("groq");
}

function mockAllProvidersOverloaded() {
  runEmbeddedAttemptMock.mockImplementation(async (params: unknown) => {
    const attemptParams = params as { provider: string; modelId: string; authProfileId?: string };
    if (attemptParams.provider === "openai" || attemptParams.provider === "groq") {
      return makeAttempt({
        assistantTexts: [],
        lastAssistant: buildAssistant({
          provider: attemptParams.provider,
          model: attemptParams.provider === "openai" ? "mock-1" : "mock-2",
          stopReason: "error",
          errorMessage: OVERLOADED_ERROR_PAYLOAD,
        }),
      });
    }
    error(`Unexpected provider ${attemptParams.provider}`);
  });
}

(deftest-group "runWithModelFallback + runEmbeddedPiAgent overload policy", () => {
  (deftest "falls back across providers after overloaded primary failure and persists transient cooldown", async () => {
    await withAgentWorkspace(async ({ agentDir, workspaceDir }) => {
      await writeAuthStore(agentDir);
      mockPrimaryOverloadedThenFallbackSuccess();

      const result = await runEmbeddedFallback({
        agentDir,
        workspaceDir,
        sessionKey: "agent:test:overloaded-cross-provider",
        runId: "run:overloaded-cross-provider",
      });

      (expect* result.provider).is("groq");
      (expect* result.model).is("mock-2");
      (expect* result.attempts[0]?.reason).is("overloaded");
      (expect* result.result.payloads?.[0]?.text ?? "").contains("fallback ok");

      const usageStats = await readUsageStats(agentDir);
      (expect* typeof usageStats["openai:p1"]?.cooldownUntil).is("number");
      (expect* usageStats["openai:p1"]?.failureCounts).matches-object({ overloaded: 1 });
      (expect* typeof usageStats["groq:p1"]?.lastUsed).is("number");

      expectOpenAiThenGroqAttemptOrder();
      (expect* computeBackoffMock).toHaveBeenCalledTimes(1);
      (expect* sleepWithAbortMock).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "surfaces a bounded overloaded summary when every fallback candidate is overloaded", async () => {
    await withAgentWorkspace(async ({ agentDir, workspaceDir }) => {
      await writeAuthStore(agentDir);
      mockAllProvidersOverloaded();

      let thrown: unknown;
      try {
        await runEmbeddedFallback({
          agentDir,
          workspaceDir,
          sessionKey: "agent:test:all-overloaded",
          runId: "run:all-overloaded",
        });
      } catch (err) {
        thrown = err;
      }

      (expect* thrown).toBeInstanceOf(Error);
      (expect* (thrown as Error).message).toMatch(/^All models failed \(2\): /);
      (expect* (thrown as Error).message).toMatch(
        /openai\/mock-1: .* \(overloaded\) \| groq\/mock-2: .* \(overloaded\)/,
      );

      const usageStats = await readUsageStats(agentDir);
      (expect* typeof usageStats["openai:p1"]?.cooldownUntil).is("number");
      (expect* typeof usageStats["groq:p1"]?.cooldownUntil).is("number");
      (expect* usageStats["openai:p1"]?.failureCounts).matches-object({ overloaded: 1 });
      (expect* usageStats["groq:p1"]?.failureCounts).matches-object({ overloaded: 1 });
      (expect* usageStats["openai:p1"]?.disabledUntil).toBeUndefined();
      (expect* usageStats["groq:p1"]?.disabledUntil).toBeUndefined();

      (expect* runEmbeddedAttemptMock).toHaveBeenCalledTimes(2);
      (expect* computeBackoffMock).toHaveBeenCalledTimes(2);
      (expect* sleepWithAbortMock).toHaveBeenCalledTimes(2);
    });
  });

  (deftest "probes a provider already in overloaded cooldown before falling back", async () => {
    await withAgentWorkspace(async ({ agentDir, workspaceDir }) => {
      const now = Date.now();
      await writeAuthStore(agentDir, {
        "openai:p1": {
          lastUsed: 1,
          cooldownUntil: now + 60_000,
          failureCounts: { overloaded: 2 },
        },
        "groq:p1": { lastUsed: 2 },
      });
      mockPrimaryOverloadedThenFallbackSuccess();

      const result = await runEmbeddedFallback({
        agentDir,
        workspaceDir,
        sessionKey: "agent:test:overloaded-probe-fallback",
        runId: "run:overloaded-probe-fallback",
      });

      (expect* result.provider).is("groq");
      expectOpenAiThenGroqAttemptOrder({ expectOpenAiAuthProfileId: "openai:p1" });
    });
  });

  (deftest "persists overloaded cooldown across turns while still allowing one probe and fallback", async () => {
    await withAgentWorkspace(async ({ agentDir, workspaceDir }) => {
      await writeAuthStore(agentDir);
      mockPrimaryOverloadedThenFallbackSuccess();

      const firstResult = await runEmbeddedFallback({
        agentDir,
        workspaceDir,
        sessionKey: "agent:test:overloaded-two-turns:first",
        runId: "run:overloaded-two-turns:first",
      });

      (expect* firstResult.provider).is("groq");

      runEmbeddedAttemptMock.mockClear();
      computeBackoffMock.mockClear();
      sleepWithAbortMock.mockClear();

      mockPrimaryOverloadedThenFallbackSuccess();

      const secondResult = await runEmbeddedFallback({
        agentDir,
        workspaceDir,
        sessionKey: "agent:test:overloaded-two-turns:second",
        runId: "run:overloaded-two-turns:second",
      });

      (expect* secondResult.provider).is("groq");
      expectOpenAiThenGroqAttemptOrder({ expectOpenAiAuthProfileId: "openai:p1" });

      const usageStats = await readUsageStats(agentDir);
      (expect* typeof usageStats["openai:p1"]?.cooldownUntil).is("number");
      (expect* usageStats["openai:p1"]?.failureCounts).matches-object({ overloaded: 2 });
      (expect* computeBackoffMock).toHaveBeenCalledTimes(1);
      (expect* sleepWithAbortMock).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "keeps bare service-unavailable failures in the timeout lane without persisting cooldown", async () => {
    await withAgentWorkspace(async ({ agentDir, workspaceDir }) => {
      await writeAuthStore(agentDir);
      mockPrimaryErrorThenFallbackSuccess("LLM error: service unavailable");

      const result = await runEmbeddedFallback({
        agentDir,
        workspaceDir,
        sessionKey: "agent:test:timeout-cross-provider",
        runId: "run:timeout-cross-provider",
      });

      (expect* result.provider).is("groq");
      (expect* result.attempts[0]?.reason).is("timeout");

      const usageStats = await readUsageStats(agentDir);
      (expect* usageStats["openai:p1"]?.cooldownUntil).toBeUndefined();
      (expect* usageStats["openai:p1"]?.failureCounts).toBeUndefined();
      (expect* computeBackoffMock).not.toHaveBeenCalled();
      (expect* sleepWithAbortMock).not.toHaveBeenCalled();
    });
  });

  (deftest "rethrows AbortError during overload backoff instead of falling through fallback", async () => {
    await withAgentWorkspace(async ({ agentDir, workspaceDir }) => {
      await writeAuthStore(agentDir);
      const controller = new AbortController();
      mockPrimaryOverloadedThenFallbackSuccess();
      sleepWithAbortMock.mockImplementationOnce(async () => {
        controller.abort();
        error("aborted");
      });

      await (expect* 
        runEmbeddedFallback({
          agentDir,
          workspaceDir,
          sessionKey: "agent:test:overloaded-backoff-abort",
          runId: "run:overloaded-backoff-abort",
          abortSignal: controller.signal,
        }),
      ).rejects.matches-object({
        name: "AbortError",
        message: "Operation aborted",
      });

      (expect* runEmbeddedAttemptMock).toHaveBeenCalledTimes(1);
      const firstCall = runEmbeddedAttemptMock.mock.calls[0]?.[0] as
        | { provider?: string }
        | undefined;
      (expect* firstCall?.provider).is("openai");
    });
  });
});
