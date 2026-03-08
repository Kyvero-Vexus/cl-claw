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
import { tmpdir } from "sbcl:os";
import path from "sbcl:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { SessionEntry } from "../../config/sessions.js";
import * as sessions from "../../config/sessions.js";
import type { TypingMode } from "../../config/types.js";
import { withStateDirEnv } from "../../test-helpers/state-dir-env.js";
import type { TemplateContext } from "../templating.js";
import type { GetReplyOptions } from "../types.js";
import {
  enqueueFollowupRun,
  scheduleFollowupDrain,
  type FollowupRun,
  type QueueSettings,
} from "./queue.js";
import { createMockTypingController } from "./test-helpers.js";

type AgentRunParams = {
  onPartialReply?: (payload: { text?: string }) => deferred-result<void> | void;
  onAssistantMessageStart?: () => deferred-result<void> | void;
  onReasoningStream?: (payload: { text?: string }) => deferred-result<void> | void;
  onBlockReply?: (payload: { text?: string; mediaUrls?: string[] }) => deferred-result<void> | void;
  onToolResult?: (payload: { text?: string; mediaUrls?: string[] }) => deferred-result<void> | void;
  onAgentEvent?: (evt: { stream: string; data: Record<string, unknown> }) => void;
};

type EmbeddedRunParams = {
  prompt?: string;
  extraSystemPrompt?: string;
  bootstrapPromptWarningSignaturesSeen?: string[];
  bootstrapPromptWarningSignature?: string;
  onAgentEvent?: (evt: { stream?: string; data?: { phase?: string; willRetry?: boolean } }) => void;
};

const state = mock:hoisted(() => ({
  runEmbeddedPiAgentMock: mock:fn(),
  runCliAgentMock: mock:fn(),
}));

let modelFallbackModule: typeof import("../../agents/model-fallback.js");
let onAgentEvent: typeof import("../../infra/agent-events.js").onAgentEvent;

let runReplyAgentPromise:
  | deferred-result<(typeof import("./agent-runner.js"))["runReplyAgent"]>
  | undefined;

async function getRunReplyAgent() {
  if (!runReplyAgentPromise) {
    runReplyAgentPromise = import("./agent-runner.js").then((m) => m.runReplyAgent);
  }
  return await runReplyAgentPromise;
}

mock:mock("../../agents/model-fallback.js", () => ({
  runWithModelFallback: async ({
    provider,
    model,
    run,
  }: {
    provider: string;
    model: string;
    run: (provider: string, model: string) => deferred-result<unknown>;
  }) => ({
    result: await run(provider, model),
    provider,
    model,
    attempts: [],
  }),
}));

mock:mock("../../agents/pi-embedded.js", () => ({
  queueEmbeddedPiMessage: mock:fn().mockReturnValue(false),
  runEmbeddedPiAgent: (params: unknown) => state.runEmbeddedPiAgentMock(params),
}));

mock:mock("../../agents/cli-runner.js", () => ({
  runCliAgent: (params: unknown) => state.runCliAgentMock(params),
}));

mock:mock("./queue.js", () => ({
  enqueueFollowupRun: mock:fn(),
  scheduleFollowupDrain: mock:fn(),
}));

beforeAll(async () => {
  // Avoid attributing the initial agent-runner import cost to the first test case.
  modelFallbackModule = await import("../../agents/model-fallback.js");
  ({ onAgentEvent } = await import("../../infra/agent-events.js"));
  await getRunReplyAgent();
});

beforeEach(() => {
  state.runEmbeddedPiAgentMock.mockClear();
  state.runCliAgentMock.mockClear();
  mock:mocked(enqueueFollowupRun).mockClear();
  mock:mocked(scheduleFollowupDrain).mockClear();
  mock:stubEnv("OPENCLAW_TEST_FAST", "1");
});

function createMinimalRun(params?: {
  opts?: GetReplyOptions;
  resolvedVerboseLevel?: "off" | "on";
  sessionStore?: Record<string, SessionEntry>;
  sessionEntry?: SessionEntry;
  sessionKey?: string;
  storePath?: string;
  typingMode?: TypingMode;
  blockStreamingEnabled?: boolean;
  isActive?: boolean;
  shouldFollowup?: boolean;
  resolvedQueueMode?: string;
  runOverrides?: Partial<FollowupRun["run"]>;
}) {
  const typing = createMockTypingController();
  const opts = params?.opts;
  const sessionCtx = {
    Provider: "whatsapp",
    MessageSid: "msg",
  } as unknown as TemplateContext;
  const resolvedQueue = {
    mode: params?.resolvedQueueMode ?? "interrupt",
  } as unknown as QueueSettings;
  const sessionKey = params?.sessionKey ?? "main";
  const followupRun = {
    prompt: "hello",
    summaryLine: "hello",
    enqueuedAt: Date.now(),
    run: {
      sessionId: "session",
      sessionKey,
      messageProvider: "whatsapp",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      config: {},
      skillsSnapshot: {},
      provider: "anthropic",
      model: "claude",
      thinkLevel: "low",
      verboseLevel: params?.resolvedVerboseLevel ?? "off",
      elevatedLevel: "off",
      bashElevated: {
        enabled: false,
        allowed: false,
        defaultLevel: "off",
      },
      timeoutMs: 1_000,
      blockReplyBreak: "message_end",
      ...params?.runOverrides,
    },
  } as unknown as FollowupRun;

  return {
    typing,
    opts,
    run: async () => {
      const runReplyAgent = await getRunReplyAgent();
      return runReplyAgent({
        commandBody: "hello",
        followupRun,
        queueKey: "main",
        resolvedQueue,
        shouldSteer: false,
        shouldFollowup: params?.shouldFollowup ?? false,
        isActive: params?.isActive ?? false,
        isStreaming: false,
        opts,
        typing,
        sessionEntry: params?.sessionEntry,
        sessionStore: params?.sessionStore,
        sessionKey,
        storePath: params?.storePath,
        sessionCtx,
        defaultModel: "anthropic/claude-opus-4-5",
        resolvedVerboseLevel: params?.resolvedVerboseLevel ?? "off",
        isNewSession: false,
        blockStreamingEnabled: params?.blockStreamingEnabled ?? false,
        resolvedBlockStreamingBreak: "message_end",
        shouldInjectGroupIntro: false,
        typingMode: params?.typingMode ?? "instant",
      });
    },
  };
}

async function seedSessionStore(params: {
  storePath: string;
  sessionKey: string;
  entry: Record<string, unknown>;
}) {
  await fs.mkdir(path.dirname(params.storePath), { recursive: true });
  await fs.writeFile(
    params.storePath,
    JSON.stringify({ [params.sessionKey]: params.entry }, null, 2),
    "utf-8",
  );
}

function createBaseRun(params: {
  storePath: string;
  sessionEntry: Record<string, unknown>;
  config?: Record<string, unknown>;
  runOverrides?: Partial<FollowupRun["run"]>;
}) {
  const typing = createMockTypingController();
  const sessionCtx = {
    Provider: "whatsapp",
    OriginatingTo: "+15550001111",
    AccountId: "primary",
    MessageSid: "msg",
  } as unknown as TemplateContext;
  const resolvedQueue = { mode: "interrupt" } as unknown as QueueSettings;
  const followupRun = {
    prompt: "hello",
    summaryLine: "hello",
    enqueuedAt: Date.now(),
    run: {
      agentId: "main",
      agentDir: "/tmp/agent",
      sessionId: "session",
      sessionKey: "main",
      messageProvider: "whatsapp",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      config: params.config ?? {},
      skillsSnapshot: {},
      provider: "anthropic",
      model: "claude",
      thinkLevel: "low",
      verboseLevel: "off",
      elevatedLevel: "off",
      bashElevated: {
        enabled: false,
        allowed: false,
        defaultLevel: "off",
      },
      timeoutMs: 1_000,
      blockReplyBreak: "message_end",
    },
  } as unknown as FollowupRun;
  const run = {
    ...followupRun.run,
    ...params.runOverrides,
    config: params.config ?? followupRun.run.config,
  };

  return {
    typing,
    sessionCtx,
    resolvedQueue,
    followupRun: { ...followupRun, run },
  };
}

async function runReplyAgentWithBase(params: {
  baseRun: ReturnType<typeof createBaseRun>;
  storePath: string;
  sessionKey: string;
  sessionEntry: SessionEntry;
  commandBody: string;
  typingMode?: "instant";
}): deferred-result<void> {
  const runReplyAgent = await getRunReplyAgent();
  const { typing, sessionCtx, resolvedQueue, followupRun } = params.baseRun;
  await runReplyAgent({
    commandBody: params.commandBody,
    followupRun,
    queueKey: params.sessionKey,
    resolvedQueue,
    shouldSteer: false,
    shouldFollowup: false,
    isActive: false,
    isStreaming: false,
    typing,
    sessionCtx,
    sessionEntry: params.sessionEntry,
    sessionStore: { [params.sessionKey]: params.sessionEntry } as Record<string, SessionEntry>,
    sessionKey: params.sessionKey,
    storePath: params.storePath,
    defaultModel: "anthropic/claude-opus-4-5",
    agentCfgContextTokens: 100_000,
    resolvedVerboseLevel: "off",
    isNewSession: false,
    blockStreamingEnabled: false,
    resolvedBlockStreamingBreak: "message_end",
    shouldInjectGroupIntro: false,
    typingMode: params.typingMode ?? "instant",
  });
}

(deftest-group "runReplyAgent heartbeat followup guard", () => {
  (deftest "drops heartbeat runs when another run is active", async () => {
    const { run, typing } = createMinimalRun({
      opts: { isHeartbeat: true },
      isActive: true,
      shouldFollowup: true,
      resolvedQueueMode: "collect",
    });

    const result = await run();

    (expect* result).toBeUndefined();
    (expect* mock:mocked(enqueueFollowupRun)).not.toHaveBeenCalled();
    (expect* state.runEmbeddedPiAgentMock).not.toHaveBeenCalled();
    (expect* typing.cleanup).toHaveBeenCalledTimes(1);
  });

  (deftest "still enqueues non-heartbeat runs when another run is active", async () => {
    const { run } = createMinimalRun({
      opts: { isHeartbeat: false },
      isActive: true,
      shouldFollowup: true,
      resolvedQueueMode: "collect",
    });

    const result = await run();

    (expect* result).toBeUndefined();
    (expect* mock:mocked(enqueueFollowupRun)).toHaveBeenCalledTimes(1);
    (expect* state.runEmbeddedPiAgentMock).not.toHaveBeenCalled();
  });

  (deftest "drains followup queue when an unexpected exception escapes the run path", async () => {
    const accounting = await import("./session-run-accounting.js");
    const persistSpy = vi
      .spyOn(accounting, "persistRunSessionUsage")
      .mockRejectedValueOnce(new Error("persist exploded"));
    state.runEmbeddedPiAgentMock.mockResolvedValueOnce({
      payloads: [{ text: "ok" }],
      meta: { agentMeta: { usage: { input: 1, output: 1 } } },
    });

    try {
      const { run } = createMinimalRun();
      await (expect* run()).rejects.signals-error("persist exploded");
      (expect* mock:mocked(scheduleFollowupDrain)).toHaveBeenCalledTimes(1);
    } finally {
      persistSpy.mockRestore();
    }
  });
});

(deftest-group "runReplyAgent typing (heartbeat)", () => {
  async function withTempStateDir<T>(fn: (stateDir: string) => deferred-result<T>): deferred-result<T> {
    return await withStateDirEnv(
      "openclaw-typing-heartbeat-",
      async ({ stateDir }) => await fn(stateDir),
    );
  }

  async function writeCorruptGeminiSessionFixture(params: {
    stateDir: string;
    sessionId: string;
    persistStore: boolean;
  }) {
    const storePath = path.join(params.stateDir, "sessions", "sessions.json");
    const sessionEntry: SessionEntry = { sessionId: params.sessionId, updatedAt: Date.now() };
    const sessionStore = { main: sessionEntry };

    await fs.mkdir(path.dirname(storePath), { recursive: true });
    if (params.persistStore) {
      await fs.writeFile(storePath, JSON.stringify(sessionStore), "utf-8");
    }

    const transcriptPath = sessions.resolveSessionTranscriptPath(params.sessionId);
    await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
    await fs.writeFile(transcriptPath, "bad", "utf-8");

    return { storePath, sessionEntry, sessionStore, transcriptPath };
  }

  (deftest "signals typing for normal runs", async () => {
    const onPartialReply = mock:fn();
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      await params.onPartialReply?.({ text: "hi" });
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run, typing } = createMinimalRun({
      opts: { isHeartbeat: false, onPartialReply },
    });
    await run();

    (expect* onPartialReply).toHaveBeenCalled();
    (expect* typing.startTypingOnText).toHaveBeenCalledWith("hi");
    (expect* typing.startTypingLoop).toHaveBeenCalled();
  });

  (deftest "never signals typing for heartbeat runs", async () => {
    const onPartialReply = mock:fn();
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      await params.onPartialReply?.({ text: "hi" });
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run, typing } = createMinimalRun({
      opts: { isHeartbeat: true, onPartialReply },
    });
    await run();

    (expect* onPartialReply).toHaveBeenCalled();
    (expect* typing.startTypingOnText).not.toHaveBeenCalled();
    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
  });

  (deftest "suppresses NO_REPLY partials but allows normal No-prefix partials", async () => {
    const cases = [
      {
        partials: ["NO_REPLY"],
        finalText: "NO_REPLY",
        expectedForwarded: [] as string[],
        shouldType: false,
      },
      {
        partials: ["NO", "NO_", "NO_RE", "NO_REPLY"],
        finalText: "NO_REPLY",
        expectedForwarded: [] as string[],
        shouldType: false,
      },
      {
        partials: ["No", "No, that is valid"],
        finalText: "No, that is valid",
        expectedForwarded: ["No", "No, that is valid"],
        shouldType: true,
      },
    ] as const;

    for (const testCase of cases) {
      const onPartialReply = mock:fn();
      state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
        for (const text of testCase.partials) {
          await params.onPartialReply?.({ text });
        }
        return { payloads: [{ text: testCase.finalText }], meta: {} };
      });

      const { run, typing } = createMinimalRun({
        opts: { isHeartbeat: false, onPartialReply },
        typingMode: "message",
      });
      await run();

      if (testCase.expectedForwarded.length === 0) {
        (expect* onPartialReply).not.toHaveBeenCalled();
      } else {
        (expect* onPartialReply).toHaveBeenCalledTimes(testCase.expectedForwarded.length);
        testCase.expectedForwarded.forEach((text, index) => {
          (expect* onPartialReply).toHaveBeenNthCalledWith(index + 1, {
            text,
            mediaUrls: undefined,
          });
        });
      }

      if (testCase.shouldType) {
        (expect* typing.startTypingOnText).toHaveBeenCalled();
      } else {
        (expect* typing.startTypingOnText).not.toHaveBeenCalled();
      }
      (expect* typing.startTypingLoop).not.toHaveBeenCalled();
    }
  });

  (deftest "does not start typing on assistant message start without prior text in message mode", async () => {
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      await params.onAssistantMessageStart?.();
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run, typing } = createMinimalRun({
      typingMode: "message",
    });
    await run();

    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
    (expect* typing.startTypingOnText).not.toHaveBeenCalled();
  });

  (deftest "starts typing from reasoning stream in thinking mode", async () => {
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      await params.onReasoningStream?.({ text: "Reasoning:\n_step_" });
      await params.onPartialReply?.({ text: "hi" });
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run, typing } = createMinimalRun({
      typingMode: "thinking",
    });
    await run();

    (expect* typing.startTypingLoop).toHaveBeenCalled();
    (expect* typing.startTypingOnText).not.toHaveBeenCalled();
  });

  (deftest "keeps assistant partial streaming enabled when reasoning mode is stream", async () => {
    const onPartialReply = mock:fn();
    const onReasoningStream = mock:fn();
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      await params.onReasoningStream?.({ text: "Reasoning:\n_step_" });
      await params.onPartialReply?.({ text: "answer chunk" });
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run } = createMinimalRun({
      opts: { onPartialReply, onReasoningStream },
      runOverrides: { reasoningLevel: "stream" },
    });
    await run();

    (expect* onReasoningStream).toHaveBeenCalled();
    (expect* onPartialReply).toHaveBeenCalledWith({ text: "answer chunk", mediaUrls: undefined });
  });

  (deftest "suppresses typing in never mode", async () => {
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      await params.onPartialReply?.({ text: "hi" });
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run, typing } = createMinimalRun({
      typingMode: "never",
    });
    await run();

    (expect* typing.startTypingOnText).not.toHaveBeenCalled();
    (expect* typing.startTypingLoop).not.toHaveBeenCalled();
  });

  (deftest "signals typing on normalized block replies", async () => {
    const onBlockReply = mock:fn();
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      await params.onBlockReply?.({ text: "\n\nchunk", mediaUrls: [] });
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run, typing } = createMinimalRun({
      typingMode: "message",
      blockStreamingEnabled: true,
      opts: { onBlockReply },
    });
    await run();

    (expect* typing.startTypingOnText).toHaveBeenCalledWith("chunk");
    (expect* onBlockReply).toHaveBeenCalled();
    const [blockPayload, blockOpts] = onBlockReply.mock.calls[0] ?? [];
    (expect* blockPayload).matches-object({ text: "chunk", audioAsVoice: false });
    (expect* blockOpts).matches-object({
      abortSignal: expect.any(AbortSignal),
      timeoutMs: expect.any(Number),
    });
  });

  (deftest "handles typing for normal and silent tool results", async () => {
    const cases = [
      {
        toolText: "tooling",
        shouldType: true,
        shouldForward: true,
      },
      {
        toolText: "NO_REPLY",
        shouldType: false,
        shouldForward: false,
      },
    ] as const;

    for (const testCase of cases) {
      const onToolResult = mock:fn();
      state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
        await params.onToolResult?.({ text: testCase.toolText, mediaUrls: [] });
        return { payloads: [{ text: "final" }], meta: {} };
      });

      const { run, typing } = createMinimalRun({
        typingMode: "message",
        opts: { onToolResult },
      });
      await run();

      if (testCase.shouldType) {
        (expect* typing.startTypingOnText).toHaveBeenCalledWith(testCase.toolText);
      } else {
        (expect* typing.startTypingOnText).not.toHaveBeenCalled();
      }

      if (testCase.shouldForward) {
        (expect* onToolResult).toHaveBeenCalledWith({
          text: testCase.toolText,
          mediaUrls: [],
        });
      } else {
        (expect* onToolResult).not.toHaveBeenCalled();
      }
    }
  });

  (deftest "retries transient HTTP failures once with timer-driven backoff", async () => {
    mock:useFakeTimers();
    let calls = 0;
    state.runEmbeddedPiAgentMock.mockImplementation(async () => {
      calls += 1;
      if (calls === 1) {
        error("502 Bad Gateway");
      }
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run } = createMinimalRun({
      typingMode: "message",
    });
    const runPromise = run();

    await mock:advanceTimersByTimeAsync(2_499);
    (expect* calls).is(1);
    await mock:advanceTimersByTimeAsync(1);
    await runPromise;
    (expect* calls).is(2);
    mock:useRealTimers();
  });

  (deftest "delivers tool results in order even when dispatched concurrently", async () => {
    const deliveryOrder: string[] = [];
    const onToolResult = mock:fn(async (payload: { text?: string }) => {
      // Simulate variable network latency: first result is slower than second
      const delay = payload.text === "first" ? 5 : 1;
      await new Promise((r) => setTimeout(r, delay));
      deliveryOrder.push(payload.text ?? "");
    });

    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      // Fire two tool results without awaiting each one; await both at the end.
      const first = params.onToolResult?.({ text: "first", mediaUrls: [] });
      const second = params.onToolResult?.({ text: "second", mediaUrls: [] });
      await Promise.all([first, second]);
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run } = createMinimalRun({
      typingMode: "message",
      opts: { onToolResult },
    });
    await run();

    (expect* onToolResult).toHaveBeenCalledTimes(2);
    // Despite "first" having higher latency, it must be delivered before "second"
    (expect* deliveryOrder).is-equal(["first", "second"]);
  });

  (deftest "continues delivering later tool results after an earlier tool result fails", async () => {
    const delivered: string[] = [];
    const onToolResult = mock:fn(async (payload: { text?: string }) => {
      if (payload.text === "first") {
        error("simulated delivery failure");
      }
      delivered.push(payload.text ?? "");
    });

    state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
      const first = params.onToolResult?.({ text: "first", mediaUrls: [] });
      const second = params.onToolResult?.({ text: "second", mediaUrls: [] });
      await Promise.allSettled([first, second]);
      return { payloads: [{ text: "final" }], meta: {} };
    });

    const { run } = createMinimalRun({
      typingMode: "message",
      opts: { onToolResult },
    });
    await run();

    (expect* onToolResult).toHaveBeenCalledTimes(2);
    (expect* delivered).is-equal(["second"]);
  });

  (deftest "announces auto-compaction in verbose mode and tracks count", async () => {
    await withTempStateDir(async (stateDir) => {
      const storePath = path.join(stateDir, "sessions", "sessions.json");
      const sessionEntry: SessionEntry = { sessionId: "session", updatedAt: Date.now() };
      const sessionStore = { main: sessionEntry };

      state.runEmbeddedPiAgentMock.mockImplementationOnce(async (params: AgentRunParams) => {
        params.onAgentEvent?.({
          stream: "compaction",
          data: { phase: "end", willRetry: false },
        });
        return { payloads: [{ text: "final" }], meta: {} };
      });

      const { run } = createMinimalRun({
        resolvedVerboseLevel: "on",
        sessionEntry,
        sessionStore,
        sessionKey: "main",
        storePath,
      });
      const res = await run();
      (expect* Array.isArray(res)).is(true);
      const payloads = res as { text?: string }[];
      (expect* payloads[0]?.text).contains("Auto-compaction complete");
      (expect* payloads[0]?.text).contains("count 1");
      (expect* sessionStore.main.compactionCount).is(1);
    });
  });

  (deftest "announces model fallback only when verbose mode is enabled", async () => {
    const cases = [
      { name: "verbose on", verbose: "on" as const, expectNotice: true },
      { name: "verbose off", verbose: "off" as const, expectNotice: false },
    ] as const;
    for (const testCase of cases) {
      const sessionEntry: SessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
      };
      const sessionStore = { main: sessionEntry };
      state.runEmbeddedPiAgentMock.mockResolvedValueOnce({
        payloads: [{ text: "final" }],
        meta: {},
      });
      mock:spyOn(modelFallbackModule, "runWithModelFallback").mockImplementationOnce(
        async ({ run }: { run: (provider: string, model: string) => deferred-result<unknown> }) => ({
          result: await run("deepinfra", "moonshotai/Kimi-K2.5"),
          provider: "deepinfra",
          model: "moonshotai/Kimi-K2.5",
          attempts: [
            {
              provider: "fireworks",
              model: "fireworks/minimax-m2p5",
              error: "Provider fireworks is in cooldown (all profiles unavailable)",
              reason: "rate_limit",
            },
          ],
        }),
      );

      const { run } = createMinimalRun({
        resolvedVerboseLevel: testCase.verbose,
        sessionEntry,
        sessionStore,
        sessionKey: "main",
      });
      const phases: string[] = [];
      const off = onAgentEvent((evt) => {
        const phase = typeof evt.data?.phase === "string" ? evt.data.phase : null;
        if (evt.stream === "lifecycle" && phase) {
          phases.push(phase);
        }
      });
      const res = await run();
      off();
      const payload = Array.isArray(res)
        ? (res[0] as { text?: string })
        : (res as { text?: string });
      if (testCase.expectNotice) {
        (expect* payload.text, testCase.name).contains("Model Fallback:");
        (expect* payload.text, testCase.name).contains("deepinfra/moonshotai/Kimi-K2.5");
        (expect* sessionEntry.fallbackNoticeReason, testCase.name).is("rate limit");
        continue;
      }
      (expect* payload.text, testCase.name).not.contains("Model Fallback:");
      (expect* 
        phases.filter((phase) => phase === "fallback"),
        testCase.name,
      ).has-length(1);
    }
  });

  (deftest "announces model fallback only once per active fallback state", async () => {
    const sessionEntry: SessionEntry = {
      sessionId: "session",
      updatedAt: Date.now(),
    };
    const sessionStore = { main: sessionEntry };

    state.runEmbeddedPiAgentMock.mockResolvedValue({
      payloads: [{ text: "final" }],
      meta: {},
    });
    const fallbackSpy = vi
      .spyOn(modelFallbackModule, "runWithModelFallback")
      .mockImplementation(
        async ({ run }: { run: (provider: string, model: string) => deferred-result<unknown> }) => ({
          result: await run("deepinfra", "moonshotai/Kimi-K2.5"),
          provider: "deepinfra",
          model: "moonshotai/Kimi-K2.5",
          attempts: [
            {
              provider: "fireworks",
              model: "fireworks/minimax-m2p5",
              error: "Provider fireworks is in cooldown (all profiles unavailable)",
              reason: "rate_limit",
            },
          ],
        }),
      );
    try {
      const { run } = createMinimalRun({
        resolvedVerboseLevel: "on",
        sessionEntry,
        sessionStore,
        sessionKey: "main",
      });
      const fallbackEvents: Array<Record<string, unknown>> = [];
      const off = onAgentEvent((evt) => {
        if (evt.stream === "lifecycle" && evt.data?.phase === "fallback") {
          fallbackEvents.push(evt.data);
        }
      });
      const first = await run();
      const second = await run();
      off();

      const firstText = Array.isArray(first) ? first[0]?.text : first?.text;
      const secondText = Array.isArray(second) ? second[0]?.text : second?.text;
      (expect* firstText).contains("Model Fallback:");
      (expect* secondText).not.contains("Model Fallback:");
      (expect* fallbackEvents).has-length(1);
    } finally {
      fallbackSpy.mockRestore();
    }
  });

  (deftest "re-announces model fallback after returning to selected model", async () => {
    const sessionEntry: SessionEntry = {
      sessionId: "session",
      updatedAt: Date.now(),
    };
    const sessionStore = { main: sessionEntry };
    let callCount = 0;

    state.runEmbeddedPiAgentMock.mockResolvedValue({
      payloads: [{ text: "final" }],
      meta: {},
    });
    const fallbackSpy = vi
      .spyOn(modelFallbackModule, "runWithModelFallback")
      .mockImplementation(
        async ({
          provider,
          model,
          run,
        }: {
          provider: string;
          model: string;
          run: (provider: string, model: string) => deferred-result<unknown>;
        }) => {
          callCount += 1;
          if (callCount === 2) {
            return {
              result: await run(provider, model),
              provider,
              model,
              attempts: [],
            };
          }
          return {
            result: await run("deepinfra", "moonshotai/Kimi-K2.5"),
            provider: "deepinfra",
            model: "moonshotai/Kimi-K2.5",
            attempts: [
              {
                provider: "fireworks",
                model: "fireworks/minimax-m2p5",
                error: "Provider fireworks is in cooldown (all profiles unavailable)",
                reason: "rate_limit",
              },
            ],
          };
        },
      );
    try {
      const { run } = createMinimalRun({
        resolvedVerboseLevel: "on",
        sessionEntry,
        sessionStore,
        sessionKey: "main",
      });
      const first = await run();
      const second = await run();
      const third = await run();

      const firstText = Array.isArray(first) ? first[0]?.text : first?.text;
      const secondText = Array.isArray(second) ? second[0]?.text : second?.text;
      const thirdText = Array.isArray(third) ? third[0]?.text : third?.text;
      (expect* firstText).contains("Model Fallback:");
      (expect* secondText).not.contains("Model Fallback:");
      (expect* thirdText).contains("Model Fallback:");
    } finally {
      fallbackSpy.mockRestore();
    }
  });

  (deftest "announces fallback-cleared once when runtime returns to selected model", async () => {
    const sessionEntry: SessionEntry = {
      sessionId: "session",
      updatedAt: Date.now(),
    };
    const sessionStore = { main: sessionEntry };
    let callCount = 0;

    state.runEmbeddedPiAgentMock.mockResolvedValue({
      payloads: [{ text: "final" }],
      meta: {},
    });
    const fallbackSpy = vi
      .spyOn(modelFallbackModule, "runWithModelFallback")
      .mockImplementation(
        async ({
          provider,
          model,
          run,
        }: {
          provider: string;
          model: string;
          run: (provider: string, model: string) => deferred-result<unknown>;
        }) => {
          callCount += 1;
          if (callCount === 1) {
            return {
              result: await run("deepinfra", "moonshotai/Kimi-K2.5"),
              provider: "deepinfra",
              model: "moonshotai/Kimi-K2.5",
              attempts: [
                {
                  provider: "fireworks",
                  model: "fireworks/minimax-m2p5",
                  error: "Provider fireworks is in cooldown (all profiles unavailable)",
                  reason: "rate_limit",
                },
              ],
            };
          }
          return {
            result: await run(provider, model),
            provider,
            model,
            attempts: [],
          };
        },
      );
    try {
      const { run } = createMinimalRun({
        resolvedVerboseLevel: "on",
        sessionEntry,
        sessionStore,
        sessionKey: "main",
      });
      const phases: string[] = [];
      const off = onAgentEvent((evt) => {
        const phase = typeof evt.data?.phase === "string" ? evt.data.phase : null;
        if (evt.stream === "lifecycle" && phase) {
          phases.push(phase);
        }
      });
      const first = await run();
      const second = await run();
      const third = await run();
      off();

      const firstText = Array.isArray(first) ? first[0]?.text : first?.text;
      const secondText = Array.isArray(second) ? second[0]?.text : second?.text;
      const thirdText = Array.isArray(third) ? third[0]?.text : third?.text;
      (expect* firstText).contains("Model Fallback:");
      (expect* secondText).contains("Model Fallback cleared:");
      (expect* thirdText).not.contains("Model Fallback cleared:");
      (expect* phases.filter((phase) => phase === "fallback")).has-length(1);
      (expect* phases.filter((phase) => phase === "fallback_cleared")).has-length(1);
    } finally {
      fallbackSpy.mockRestore();
    }
  });

  (deftest "emits fallback lifecycle events while verbose is off", async () => {
    const sessionEntry: SessionEntry = {
      sessionId: "session",
      updatedAt: Date.now(),
    };
    const sessionStore = { main: sessionEntry };
    let callCount = 0;

    state.runEmbeddedPiAgentMock.mockResolvedValue({
      payloads: [{ text: "final" }],
      meta: {},
    });
    const fallbackSpy = vi
      .spyOn(modelFallbackModule, "runWithModelFallback")
      .mockImplementation(
        async ({
          provider,
          model,
          run,
        }: {
          provider: string;
          model: string;
          run: (provider: string, model: string) => deferred-result<unknown>;
        }) => {
          callCount += 1;
          if (callCount === 1) {
            return {
              result: await run("deepinfra", "moonshotai/Kimi-K2.5"),
              provider: "deepinfra",
              model: "moonshotai/Kimi-K2.5",
              attempts: [
                {
                  provider: "fireworks",
                  model: "fireworks/minimax-m2p5",
                  error: "Provider fireworks is in cooldown (all profiles unavailable)",
                  reason: "rate_limit",
                },
              ],
            };
          }
          return {
            result: await run(provider, model),
            provider,
            model,
            attempts: [],
          };
        },
      );
    try {
      const { run } = createMinimalRun({
        resolvedVerboseLevel: "off",
        sessionEntry,
        sessionStore,
        sessionKey: "main",
      });
      const phases: string[] = [];
      const off = onAgentEvent((evt) => {
        const phase = typeof evt.data?.phase === "string" ? evt.data.phase : null;
        if (evt.stream === "lifecycle" && phase) {
          phases.push(phase);
        }
      });
      const first = await run();
      const second = await run();
      off();

      const firstText = Array.isArray(first) ? first[0]?.text : first?.text;
      const secondText = Array.isArray(second) ? second[0]?.text : second?.text;
      (expect* firstText).not.contains("Model Fallback:");
      (expect* secondText).not.contains("Model Fallback cleared:");
      (expect* phases.filter((phase) => phase === "fallback")).has-length(1);
      (expect* phases.filter((phase) => phase === "fallback_cleared")).has-length(1);
    } finally {
      fallbackSpy.mockRestore();
    }
  });

  (deftest "updates fallback reason summary while fallback stays active", async () => {
    const cases = [
      {
        existingReason: undefined,
        reportedReason: "rate_limit",
        expectedReason: "rate limit",
      },
      {
        existingReason: undefined,
        reportedReason: "overloaded",
        expectedReason: "overloaded",
      },
      {
        existingReason: "rate limit",
        reportedReason: "timeout",
        expectedReason: "timeout",
      },
    ] as const;

    for (const testCase of cases) {
      const sessionEntry: SessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        fallbackNoticeSelectedModel: "anthropic/claude",
        fallbackNoticeActiveModel: "deepinfra/moonshotai/Kimi-K2.5",
        ...(testCase.existingReason ? { fallbackNoticeReason: testCase.existingReason } : {}),
        modelProvider: "deepinfra",
        model: "moonshotai/Kimi-K2.5",
      };
      const sessionStore = { main: sessionEntry };

      state.runEmbeddedPiAgentMock.mockResolvedValue({
        payloads: [{ text: "final" }],
        meta: {},
      });
      const fallbackSpy = vi
        .spyOn(modelFallbackModule, "runWithModelFallback")
        .mockImplementation(
          async ({ run }: { run: (provider: string, model: string) => deferred-result<unknown> }) => ({
            result: await run("deepinfra", "moonshotai/Kimi-K2.5"),
            provider: "deepinfra",
            model: "moonshotai/Kimi-K2.5",
            attempts: [
              {
                provider: "anthropic",
                model: "claude",
                error: "Provider anthropic is in cooldown (all profiles unavailable)",
                reason: testCase.reportedReason,
              },
            ],
          }),
        );
      try {
        const { run } = createMinimalRun({
          resolvedVerboseLevel: "on",
          sessionEntry,
          sessionStore,
          sessionKey: "main",
        });
        const res = await run();
        const firstText = Array.isArray(res) ? res[0]?.text : res?.text;
        (expect* firstText).not.contains("Model Fallback:");
        (expect* sessionEntry.fallbackNoticeReason).is(testCase.expectedReason);
      } finally {
        fallbackSpy.mockRestore();
      }
    }
  });

  (deftest "retries after compaction failure by resetting the session", async () => {
    await withTempStateDir(async (stateDir) => {
      const sessionId = "session";
      const storePath = path.join(stateDir, "sessions", "sessions.json");
      const transcriptPath = sessions.resolveSessionTranscriptPath(sessionId);
      const sessionEntry: SessionEntry = {
        sessionId,
        updatedAt: Date.now(),
        sessionFile: transcriptPath,
        fallbackNoticeSelectedModel: "fireworks/minimax-m2p5",
        fallbackNoticeActiveModel: "deepinfra/moonshotai/Kimi-K2.5",
        fallbackNoticeReason: "rate limit",
      };
      const sessionStore = { main: sessionEntry };

      await fs.mkdir(path.dirname(storePath), { recursive: true });
      await fs.writeFile(storePath, JSON.stringify(sessionStore), "utf-8");
      await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
      await fs.writeFile(transcriptPath, "ok", "utf-8");

      state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => {
        error(
          'Context overflow: Summarization failed: 400 {"message":"prompt is too long"}',
        );
      });

      const { run } = createMinimalRun({
        sessionEntry,
        sessionStore,
        sessionKey: "main",
        storePath,
      });
      const res = await run();

      (expect* state.runEmbeddedPiAgentMock).toHaveBeenCalledTimes(1);
      const payload = Array.isArray(res) ? res[0] : res;
      (expect* payload).matches-object({
        text: expect.stringContaining("Context limit exceeded during compaction"),
      });
      if (!payload) {
        error("expected payload");
      }
      (expect* payload.text?.toLowerCase()).contains("reset");
      (expect* sessionStore.main.sessionId).not.is(sessionId);
      (expect* sessionStore.main.fallbackNoticeSelectedModel).toBeUndefined();
      (expect* sessionStore.main.fallbackNoticeActiveModel).toBeUndefined();
      (expect* sessionStore.main.fallbackNoticeReason).toBeUndefined();

      const persisted = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* persisted.main.sessionId).is(sessionStore.main.sessionId);
      (expect* persisted.main.fallbackNoticeSelectedModel).toBeUndefined();
      (expect* persisted.main.fallbackNoticeActiveModel).toBeUndefined();
      (expect* persisted.main.fallbackNoticeReason).toBeUndefined();
    });
  });

  (deftest "retries after context overflow payload by resetting the session", async () => {
    await withTempStateDir(async (stateDir) => {
      const sessionId = "session";
      const storePath = path.join(stateDir, "sessions", "sessions.json");
      const transcriptPath = sessions.resolveSessionTranscriptPath(sessionId);
      const sessionEntry = { sessionId, updatedAt: Date.now(), sessionFile: transcriptPath };
      const sessionStore = { main: sessionEntry };

      await fs.mkdir(path.dirname(storePath), { recursive: true });
      await fs.writeFile(storePath, JSON.stringify(sessionStore), "utf-8");
      await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
      await fs.writeFile(transcriptPath, "ok", "utf-8");

      state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => ({
        payloads: [{ text: "Context overflow: prompt too large", isError: true }],
        meta: {
          durationMs: 1,
          error: {
            kind: "context_overflow",
            message: 'Context overflow: Summarization failed: 400 {"message":"prompt is too long"}',
          },
        },
      }));

      const { run } = createMinimalRun({
        sessionEntry,
        sessionStore,
        sessionKey: "main",
        storePath,
      });
      const res = await run();

      (expect* state.runEmbeddedPiAgentMock).toHaveBeenCalledTimes(1);
      const payload = Array.isArray(res) ? res[0] : res;
      (expect* payload).matches-object({
        text: expect.stringContaining("Context limit exceeded"),
      });
      if (!payload) {
        error("expected payload");
      }
      (expect* payload.text?.toLowerCase()).contains("reset");
      (expect* sessionStore.main.sessionId).not.is(sessionId);

      const persisted = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* persisted.main.sessionId).is(sessionStore.main.sessionId);
    });
  });

  (deftest "surfaces overflow fallback when embedded run returns empty payloads", async () => {
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => ({
      payloads: [],
      meta: {
        durationMs: 1,
        error: {
          kind: "context_overflow",
          message: 'Context overflow: Summarization failed: 400 {"message":"prompt is too long"}',
        },
      },
    }));

    const { run } = createMinimalRun();
    const res = await run();
    const payload = Array.isArray(res) ? res[0] : res;
    (expect* payload).matches-object({
      text: expect.stringContaining("conversation is too large"),
    });
    if (!payload) {
      error("expected payload");
    }
    (expect* payload.text).contains("/new");
  });

  (deftest "surfaces overflow fallback when embedded payload text is whitespace-only", async () => {
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => ({
      payloads: [{ text: "   \n\t  ", isError: true }],
      meta: {
        durationMs: 1,
        error: {
          kind: "context_overflow",
          message: 'Context overflow: Summarization failed: 400 {"message":"prompt is too long"}',
        },
      },
    }));

    const { run } = createMinimalRun();
    const res = await run();
    const payload = Array.isArray(res) ? res[0] : res;
    (expect* payload).matches-object({
      text: expect.stringContaining("conversation is too large"),
    });
    if (!payload) {
      error("expected payload");
    }
    (expect* payload.text).contains("/new");
  });

  (deftest "resets the session after role ordering payloads", async () => {
    await withTempStateDir(async (stateDir) => {
      const sessionId = "session";
      const storePath = path.join(stateDir, "sessions", "sessions.json");
      const transcriptPath = sessions.resolveSessionTranscriptPath(sessionId);
      const sessionEntry = { sessionId, updatedAt: Date.now(), sessionFile: transcriptPath };
      const sessionStore = { main: sessionEntry };

      await fs.mkdir(path.dirname(storePath), { recursive: true });
      await fs.writeFile(storePath, JSON.stringify(sessionStore), "utf-8");
      await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
      await fs.writeFile(transcriptPath, "ok", "utf-8");

      state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => ({
        payloads: [{ text: "Message ordering conflict - please try again.", isError: true }],
        meta: {
          durationMs: 1,
          error: {
            kind: "role_ordering",
            message: 'messages: roles must alternate between "user" and "assistant"',
          },
        },
      }));

      const { run } = createMinimalRun({
        sessionEntry,
        sessionStore,
        sessionKey: "main",
        storePath,
      });
      const res = await run();

      const payload = Array.isArray(res) ? res[0] : res;
      (expect* payload).matches-object({
        text: expect.stringContaining("Message ordering conflict"),
      });
      if (!payload) {
        error("expected payload");
      }
      (expect* payload.text?.toLowerCase()).contains("reset");
      (expect* sessionStore.main.sessionId).not.is(sessionId);
      await (expect* fs.access(transcriptPath)).rejects.toBeDefined();

      const persisted = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* persisted.main.sessionId).is(sessionStore.main.sessionId);
    });
  });

  (deftest "resets corrupted Gemini sessions and deletes transcripts", async () => {
    await withTempStateDir(async (stateDir) => {
      const { storePath, sessionEntry, sessionStore, transcriptPath } =
        await writeCorruptGeminiSessionFixture({
          stateDir,
          sessionId: "session-corrupt",
          persistStore: true,
        });

      state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => {
        error(
          "function call turn comes immediately after a user turn or after a function response turn",
        );
      });

      const { run } = createMinimalRun({
        sessionEntry,
        sessionStore,
        sessionKey: "main",
        storePath,
      });
      const res = await run();

      (expect* res).matches-object({
        text: expect.stringContaining("Session history was corrupted"),
      });
      (expect* sessionStore.main).toBeUndefined();
      await (expect* fs.access(transcriptPath)).rejects.signals-error();

      const persisted = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* persisted.main).toBeUndefined();
    });
  });

  (deftest "keeps sessions intact on other errors", async () => {
    await withTempStateDir(async (stateDir) => {
      const sessionId = "session-ok";
      const storePath = path.join(stateDir, "sessions", "sessions.json");
      const sessionEntry = { sessionId, updatedAt: Date.now() };
      const sessionStore = { main: sessionEntry };

      await fs.mkdir(path.dirname(storePath), { recursive: true });
      await fs.writeFile(storePath, JSON.stringify(sessionStore), "utf-8");

      const transcriptPath = sessions.resolveSessionTranscriptPath(sessionId);
      await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
      await fs.writeFile(transcriptPath, "ok", "utf-8");

      state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => {
        error("INVALID_ARGUMENT: some other failure");
      });

      const { run } = createMinimalRun({
        sessionEntry,
        sessionStore,
        sessionKey: "main",
        storePath,
      });
      const res = await run();

      (expect* res).matches-object({
        text: expect.stringContaining("Agent failed before reply"),
      });
      (expect* sessionStore.main).toBeDefined();
      await (expect* fs.access(transcriptPath)).resolves.toBeUndefined();

      const persisted = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* persisted.main).toBeDefined();
    });
  });

  (deftest "still replies even if session reset fails to persist", async () => {
    await withTempStateDir(async (stateDir) => {
      const saveSpy = vi
        .spyOn(sessions, "saveSessionStore")
        .mockRejectedValueOnce(new Error("boom"));
      try {
        const { storePath, sessionEntry, sessionStore, transcriptPath } =
          await writeCorruptGeminiSessionFixture({
            stateDir,
            sessionId: "session-corrupt",
            persistStore: false,
          });

        state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => {
          error(
            "function call turn comes immediately after a user turn or after a function response turn",
          );
        });

        const { run } = createMinimalRun({
          sessionEntry,
          sessionStore,
          sessionKey: "main",
          storePath,
        });
        const res = await run();

        (expect* res).matches-object({
          text: expect.stringContaining("Session history was corrupted"),
        });
        (expect* sessionStore.main).toBeUndefined();
        await (expect* fs.access(transcriptPath)).rejects.signals-error();
      } finally {
        saveSpy.mockRestore();
      }
    });
  });

  (deftest "returns friendly message for role ordering errors thrown as exceptions", async () => {
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => {
      error("400 Incorrect role information");
    });

    const { run } = createMinimalRun({});
    const res = await run();

    (expect* res).matches-object({
      text: expect.stringContaining("Message ordering conflict"),
    });
    (expect* res).matches-object({
      text: expect.not.stringContaining("400"),
    });
  });

  (deftest "rewrites Bun socket errors into friendly text", async () => {
    state.runEmbeddedPiAgentMock.mockImplementationOnce(async () => ({
      payloads: [
        {
          text: "TypeError: The socket connection was closed unexpectedly. For more information, pass `verbose: true` in the second argument to fetch()",
          isError: true,
        },
      ],
      meta: {},
    }));

    const { run } = createMinimalRun();
    const res = await run();
    const payloads = Array.isArray(res) ? res : res ? [res] : [];
    (expect* payloads.length).is(1);
    (expect* payloads[0]?.text).contains("LLM connection failed");
    (expect* payloads[0]?.text).contains("socket connection was closed unexpectedly");
    (expect* payloads[0]?.text).contains("```");
  });
});

(deftest-group "runReplyAgent memory flush", () => {
  let fixtureRoot = "";
  let caseId = 0;

  async function withTempStore<T>(fn: (storePath: string) => deferred-result<T>): deferred-result<T> {
    const dir = path.join(fixtureRoot, `case-${++caseId}`);
    await fs.mkdir(dir, { recursive: true });
    return await fn(path.join(dir, "sessions.json"));
  }

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(tmpdir(), "openclaw-memory-flush-"));
  });

  afterAll(async () => {
    if (fixtureRoot) {
      await fs.rm(fixtureRoot, { recursive: true, force: true });
    }
  });

  (deftest "skips memory flush for CLI providers", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionEntry: SessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        totalTokens: 80_000,
        compactionCount: 1,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      state.runEmbeddedPiAgentMock.mockImplementation(async () => ({
        payloads: [{ text: "ok" }],
        meta: { agentMeta: { usage: { input: 1, output: 1 } } },
      }));
      state.runCliAgentMock.mockResolvedValue({
        payloads: [{ text: "ok" }],
        meta: { agentMeta: { usage: { input: 1, output: 1 } } },
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
        runOverrides: { provider: "codex-cli" },
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      (expect* state.runCliAgentMock).toHaveBeenCalledTimes(1);
      const call = state.runCliAgentMock.mock.calls[0]?.[0] as { prompt?: string } | undefined;
      (expect* call?.prompt).is("hello");
      (expect* state.runEmbeddedPiAgentMock).not.toHaveBeenCalled();
    });
  });

  (deftest "uses configured prompts for memory flush runs", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        totalTokens: 80_000,
        compactionCount: 1,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      const calls: Array<EmbeddedRunParams> = [];
      state.runEmbeddedPiAgentMock.mockImplementation(async (params: EmbeddedRunParams) => {
        calls.push(params);
        if (params.prompt?.includes("Write notes.")) {
          return { payloads: [], meta: {} };
        }
        return {
          payloads: [{ text: "ok" }],
          meta: { agentMeta: { usage: { input: 1, output: 1 } } },
        };
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
        config: {
          agents: {
            defaults: {
              compaction: {
                memoryFlush: {
                  prompt: "Write notes.",
                  systemPrompt: "Flush memory now.",
                },
              },
            },
          },
        },
        runOverrides: { extraSystemPrompt: "extra system" },
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      const flushCall = calls[0];
      (expect* flushCall?.prompt).contains("Write notes.");
      (expect* flushCall?.prompt).contains("NO_REPLY");
      (expect* flushCall?.extraSystemPrompt).contains("extra system");
      (expect* flushCall?.extraSystemPrompt).contains("Flush memory now.");
      (expect* flushCall?.extraSystemPrompt).contains("NO_REPLY");
      (expect* calls[1]?.prompt).is("hello");
    });
  });

  (deftest "passes stored bootstrap warning signatures to memory flush runs", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionEntry: SessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        totalTokens: 80_000,
        compactionCount: 1,
        systemPromptReport: {
          source: "run",
          generatedAt: Date.now(),
          systemPrompt: {
            chars: 1,
            projectContextChars: 0,
            nonProjectContextChars: 1,
          },
          injectedWorkspaceFiles: [],
          skills: {
            promptChars: 0,
            entries: [],
          },
          tools: {
            listChars: 0,
            schemaChars: 0,
            entries: [],
          },
          bootstrapTruncation: {
            warningMode: "once",
            warningShown: true,
            promptWarningSignature: "sig-b",
            warningSignaturesSeen: ["sig-a", "sig-b"],
            truncatedFiles: 1,
            nearLimitFiles: 0,
            totalNearLimit: false,
          },
        },
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      const calls: Array<EmbeddedRunParams> = [];
      state.runEmbeddedPiAgentMock.mockImplementation(async (params: EmbeddedRunParams) => {
        calls.push(params);
        if (params.prompt?.includes("Pre-compaction memory flush.")) {
          return { payloads: [], meta: {} };
        }
        return {
          payloads: [{ text: "ok" }],
          meta: { agentMeta: { usage: { input: 1, output: 1 } } },
        };
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      (expect* calls).has-length(2);
      (expect* calls[0]?.bootstrapPromptWarningSignaturesSeen).is-equal(["sig-a", "sig-b"]);
      (expect* calls[0]?.bootstrapPromptWarningSignature).is("sig-b");
    });
  });

  (deftest "runs a memory flush turn and updates session metadata", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        totalTokens: 80_000,
        compactionCount: 1,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      const calls: Array<{ prompt?: string }> = [];
      state.runEmbeddedPiAgentMock.mockImplementation(async (params: EmbeddedRunParams) => {
        calls.push({ prompt: params.prompt });
        if (params.prompt?.includes("Pre-compaction memory flush.")) {
          return { payloads: [], meta: {} };
        }
        return {
          payloads: [{ text: "ok" }],
          meta: { agentMeta: { usage: { input: 1, output: 1 } } },
        };
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      (expect* calls).has-length(2);
      (expect* calls[0]?.prompt).contains("Pre-compaction memory flush.");
      (expect* calls[0]?.prompt).contains("Current time:");
      (expect* calls[0]?.prompt).toMatch(/memory\/\d{4}-\d{2}-\d{2}\.md/);
      (expect* calls[1]?.prompt).is("hello");

      const stored = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* stored[sessionKey].memoryFlushAt).toBeTypeOf("number");
      (expect* stored[sessionKey].memoryFlushCompactionCount).is(1);
    });
  });

  (deftest "runs memory flush when transcript fallback uses a relative sessionFile path", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionFile = "session-relative.jsonl";
      const transcriptPath = path.join(path.dirname(storePath), sessionFile);
      await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
      await fs.writeFile(
        transcriptPath,
        JSON.stringify({ usage: { input: 90_000, output: 8_000 } }),
        "utf-8",
      );

      const sessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        sessionFile,
        totalTokens: 10,
        totalTokensFresh: false,
        compactionCount: 1,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      const calls: Array<{ prompt?: string }> = [];
      state.runEmbeddedPiAgentMock.mockImplementation(async (params: EmbeddedRunParams) => {
        calls.push({ prompt: params.prompt });
        if (params.prompt?.includes("Pre-compaction memory flush.")) {
          return { payloads: [], meta: {} };
        }
        return {
          payloads: [{ text: "ok" }],
          meta: { agentMeta: { usage: { input: 1, output: 1 } } },
        };
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
        runOverrides: { sessionFile },
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      (expect* calls).has-length(2);
      (expect* calls[0]?.prompt).contains("Pre-compaction memory flush.");
      (expect* calls[0]?.prompt).contains("Current time:");
      (expect* calls[0]?.prompt).toMatch(/memory\/\d{4}-\d{2}-\d{2}\.md/);
      (expect* calls[1]?.prompt).is("hello");

      const stored = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* stored[sessionKey].memoryFlushAt).toBeTypeOf("number");
    });
  });

  (deftest "forces memory flush when transcript file exceeds configured byte threshold", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionFile = "oversized-session.jsonl";
      const transcriptPath = path.join(path.dirname(storePath), sessionFile);
      await fs.mkdir(path.dirname(transcriptPath), { recursive: true });
      await fs.writeFile(transcriptPath, "x".repeat(3_000), "utf-8");

      const sessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        sessionFile,
        totalTokens: 10,
        totalTokensFresh: false,
        compactionCount: 1,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      const calls: Array<{ prompt?: string }> = [];
      state.runEmbeddedPiAgentMock.mockImplementation(async (params: EmbeddedRunParams) => {
        calls.push({ prompt: params.prompt });
        if (params.prompt?.includes("Pre-compaction memory flush.")) {
          return { payloads: [], meta: {} };
        }
        return {
          payloads: [{ text: "ok" }],
          meta: { agentMeta: { usage: { input: 1, output: 1 } } },
        };
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
        config: {
          agents: {
            defaults: {
              compaction: {
                memoryFlush: {
                  forceFlushTranscriptBytes: 256,
                },
              },
            },
          },
        },
        runOverrides: { sessionFile },
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      (expect* calls).has-length(2);
      (expect* calls[0]?.prompt).contains("Pre-compaction memory flush.");
      (expect* calls[1]?.prompt).is("hello");
    });
  });

  (deftest "skips memory flush when disabled in config", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        totalTokens: 80_000,
        compactionCount: 1,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      state.runEmbeddedPiAgentMock.mockImplementation(async () => ({
        payloads: [{ text: "ok" }],
        meta: { agentMeta: { usage: { input: 1, output: 1 } } },
      }));

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
        config: { agents: { defaults: { compaction: { memoryFlush: { enabled: false } } } } },
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      (expect* state.runEmbeddedPiAgentMock).toHaveBeenCalledTimes(1);
      const call = state.runEmbeddedPiAgentMock.mock.calls[0]?.[0] as
        | { prompt?: string }
        | undefined;
      (expect* call?.prompt).is("hello");

      const stored = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* stored[sessionKey].memoryFlushAt).toBeUndefined();
    });
  });

  (deftest "skips memory flush after a prior flush in the same compaction cycle", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        totalTokens: 80_000,
        compactionCount: 2,
        memoryFlushCompactionCount: 2,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      const calls: Array<{ prompt?: string }> = [];
      state.runEmbeddedPiAgentMock.mockImplementation(async (params: EmbeddedRunParams) => {
        calls.push({ prompt: params.prompt });
        return {
          payloads: [{ text: "ok" }],
          meta: { agentMeta: { usage: { input: 1, output: 1 } } },
        };
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      (expect* calls.map((call) => call.prompt)).is-equal(["hello"]);
    });
  });

  (deftest "increments compaction count when flush compaction completes", async () => {
    await withTempStore(async (storePath) => {
      const sessionKey = "main";
      const sessionEntry = {
        sessionId: "session",
        updatedAt: Date.now(),
        totalTokens: 80_000,
        compactionCount: 1,
      };

      await seedSessionStore({ storePath, sessionKey, entry: sessionEntry });

      state.runEmbeddedPiAgentMock.mockImplementation(async (params: EmbeddedRunParams) => {
        if (params.prompt?.includes("Pre-compaction memory flush.")) {
          params.onAgentEvent?.({
            stream: "compaction",
            data: { phase: "end", willRetry: false },
          });
          return { payloads: [], meta: {} };
        }
        return {
          payloads: [{ text: "ok" }],
          meta: { agentMeta: { usage: { input: 1, output: 1 } } },
        };
      });

      const baseRun = createBaseRun({
        storePath,
        sessionEntry,
      });

      await runReplyAgentWithBase({
        baseRun,
        storePath,
        sessionKey,
        sessionEntry,
        commandBody: "hello",
      });

      const stored = JSON.parse(await fs.readFile(storePath, "utf-8"));
      (expect* stored[sessionKey].compactionCount).is(2);
      (expect* stored[sessionKey].memoryFlushCompactionCount).is(2);
    });
  });
});
