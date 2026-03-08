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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const {
  hookRunner,
  resolveModelMock,
  sessionCompactImpl,
  triggerInternalHook,
  sanitizeSessionHistoryMock,
} = mock:hoisted(() => ({
  hookRunner: {
    hasHooks: mock:fn(),
    runBeforeCompaction: mock:fn(),
    runAfterCompaction: mock:fn(),
  },
  resolveModelMock: mock:fn(() => ({
    model: { provider: "openai", api: "responses", id: "fake", input: [] },
    error: null,
    authStorage: { setRuntimeApiKey: mock:fn() },
    modelRegistry: {},
  })),
  sessionCompactImpl: mock:fn(async () => ({
    summary: "summary",
    firstKeptEntryId: "entry-1",
    tokensBefore: 120,
    details: { ok: true },
  })),
  triggerInternalHook: mock:fn(),
  sanitizeSessionHistoryMock: mock:fn(async (params: { messages: unknown[] }) => params.messages),
}));

mock:mock("../../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => hookRunner,
}));

mock:mock("../../hooks/internal-hooks.js", async () => {
  const actual = await mock:importActual<typeof import("../../hooks/internal-hooks.js")>(
    "../../hooks/internal-hooks.js",
  );
  return {
    ...actual,
    triggerInternalHook,
  };
});

mock:mock("@mariozechner/pi-coding-agent", () => {
  return {
    createAgentSession: mock:fn(async () => {
      const session = {
        sessionId: "session-1",
        messages: [
          { role: "user", content: "hello", timestamp: 1 },
          { role: "assistant", content: [{ type: "text", text: "hi" }], timestamp: 2 },
          {
            role: "toolResult",
            toolCallId: "t1",
            toolName: "exec",
            content: [{ type: "text", text: "output" }],
            isError: false,
            timestamp: 3,
          },
        ],
        agent: {
          replaceMessages: mock:fn((messages: unknown[]) => {
            session.messages = [...(messages as typeof session.messages)];
          }),
          streamFn: mock:fn(),
        },
        compact: mock:fn(async () => {
          // simulate compaction trimming to a single message
          session.messages.splice(1);
          return await sessionCompactImpl();
        }),
        dispose: mock:fn(),
      };
      return { session };
    }),
    SessionManager: {
      open: mock:fn(() => ({})),
    },
    SettingsManager: {
      create: mock:fn(() => ({})),
    },
    estimateTokens: mock:fn(() => 10),
  };
});

mock:mock("../session-tool-result-guard-wrapper.js", () => ({
  guardSessionManager: mock:fn(() => ({
    flushPendingToolResults: mock:fn(),
  })),
}));

mock:mock("../pi-settings.js", () => ({
  ensurePiCompactionReserveTokens: mock:fn(),
  resolveCompactionReserveTokensFloor: mock:fn(() => 0),
}));

mock:mock("../models-config.js", () => ({
  ensureOpenClawModelsJson: mock:fn(async () => {}),
}));

mock:mock("../model-auth.js", () => ({
  getApiKeyForModel: mock:fn(async () => ({ apiKey: "test", mode: "env" })),
  resolveModelAuthMode: mock:fn(() => "env"),
}));

mock:mock("../sandbox.js", () => ({
  resolveSandboxContext: mock:fn(async () => null),
}));

mock:mock("../session-file-repair.js", () => ({
  repairSessionFileIfNeeded: mock:fn(async () => {}),
}));

mock:mock("../session-write-lock.js", () => ({
  acquireSessionWriteLock: mock:fn(async () => ({ release: mock:fn(async () => {}) })),
  resolveSessionLockMaxHoldFromTimeout: mock:fn(() => 0),
}));

mock:mock("../bootstrap-files.js", () => ({
  makeBootstrapWarn: mock:fn(() => () => {}),
  resolveBootstrapContextForRun: mock:fn(async () => ({ contextFiles: [] })),
}));

mock:mock("../docs-path.js", () => ({
  resolveOpenClawDocsPath: mock:fn(async () => undefined),
}));

mock:mock("../channel-tools.js", () => ({
  listChannelSupportedActions: mock:fn(() => undefined),
  resolveChannelMessageToolHints: mock:fn(() => undefined),
}));

mock:mock("../pi-tools.js", () => ({
  createOpenClawCodingTools: mock:fn(() => []),
}));

mock:mock("./google.js", () => ({
  logToolSchemasForGoogle: mock:fn(),
  sanitizeSessionHistory: sanitizeSessionHistoryMock,
  sanitizeToolsForGoogle: mock:fn(({ tools }: { tools: unknown[] }) => tools),
}));

mock:mock("./tool-split.js", () => ({
  splitSdkTools: mock:fn(() => ({ builtInTools: [], customTools: [] })),
}));

mock:mock("../transcript-policy.js", () => ({
  resolveTranscriptPolicy: mock:fn(() => ({
    allowSyntheticToolResults: false,
    validateGeminiTurns: false,
    validateAnthropicTurns: false,
  })),
}));

mock:mock("./extensions.js", () => ({
  buildEmbeddedExtensionFactories: mock:fn(() => []),
}));

mock:mock("./history.js", () => ({
  getDmHistoryLimitFromSessionKey: mock:fn(() => undefined),
  limitHistoryTurns: mock:fn((msgs: unknown[]) => msgs.slice(0, 2)),
}));

mock:mock("../skills.js", () => ({
  applySkillEnvOverrides: mock:fn(() => () => {}),
  applySkillEnvOverridesFromSnapshot: mock:fn(() => () => {}),
  loadWorkspaceSkillEntries: mock:fn(() => []),
  resolveSkillsPromptForRun: mock:fn(() => undefined),
}));

mock:mock("../agent-paths.js", () => ({
  resolveOpenClawAgentDir: mock:fn(() => "/tmp"),
}));

mock:mock("../agent-scope.js", () => ({
  resolveSessionAgentIds: mock:fn(() => ({ defaultAgentId: "main", sessionAgentId: "main" })),
}));

mock:mock("../date-time.js", () => ({
  formatUserTime: mock:fn(() => ""),
  resolveUserTimeFormat: mock:fn(() => ""),
  resolveUserTimezone: mock:fn(() => ""),
}));

mock:mock("../defaults.js", () => ({
  DEFAULT_MODEL: "fake-model",
  DEFAULT_PROVIDER: "openai",
  DEFAULT_CONTEXT_TOKENS: 128_000,
}));

mock:mock("../utils.js", () => ({
  resolveUserPath: mock:fn((p: string) => p),
}));

mock:mock("../../infra/machine-name.js", () => ({
  getMachineDisplayName: mock:fn(async () => "machine"),
}));

mock:mock("../../config/channel-capabilities.js", () => ({
  resolveChannelCapabilities: mock:fn(() => undefined),
}));

mock:mock("../../utils/message-channel.js", () => ({
  normalizeMessageChannel: mock:fn(() => undefined),
}));

mock:mock("../pi-embedded-helpers.js", () => ({
  ensureSessionHeader: mock:fn(async () => {}),
  validateAnthropicTurns: mock:fn((m: unknown[]) => m),
  validateGeminiTurns: mock:fn((m: unknown[]) => m),
}));

mock:mock("../pi-project-settings.js", () => ({
  createPreparedEmbeddedPiSettingsManager: mock:fn(() => ({
    getGlobalSettings: mock:fn(() => ({})),
  })),
}));

mock:mock("./sandbox-info.js", () => ({
  buildEmbeddedSandboxInfo: mock:fn(() => undefined),
}));

mock:mock("./model.js", () => ({
  buildModelAliasLines: mock:fn(() => []),
  resolveModel: resolveModelMock,
}));

mock:mock("./session-manager-cache.js", () => ({
  prewarmSessionFile: mock:fn(async () => {}),
  trackSessionManagerAccess: mock:fn(),
}));

mock:mock("./system-prompt.js", () => ({
  applySystemPromptOverrideToSession: mock:fn(),
  buildEmbeddedSystemPrompt: mock:fn(() => ""),
  createSystemPromptOverride: mock:fn(() => () => ""),
}));

mock:mock("./utils.js", () => ({
  describeUnknownError: mock:fn((err: unknown) => String(err)),
  mapThinkingLevel: mock:fn(() => "off"),
  resolveExecToolDefaults: mock:fn(() => undefined),
}));

import { getApiProvider, unregisterApiProviders } from "@mariozechner/pi-ai";
import { getCustomApiRegistrySourceId } from "../custom-api-registry.js";
import { compactEmbeddedPiSessionDirect } from "./compact.js";

const sessionHook = (action: string) =>
  triggerInternalHook.mock.calls.find(
    (call) => call[0]?.type === "session" && call[0]?.action === action,
  )?.[0];

(deftest-group "compactEmbeddedPiSessionDirect hooks", () => {
  beforeEach(() => {
    triggerInternalHook.mockClear();
    hookRunner.hasHooks.mockReset();
    hookRunner.runBeforeCompaction.mockReset();
    hookRunner.runAfterCompaction.mockReset();
    resolveModelMock.mockReset();
    resolveModelMock.mockReturnValue({
      model: { provider: "openai", api: "responses", id: "fake", input: [] },
      error: null,
      authStorage: { setRuntimeApiKey: mock:fn() },
      modelRegistry: {},
    });
    sessionCompactImpl.mockReset();
    sessionCompactImpl.mockResolvedValue({
      summary: "summary",
      firstKeptEntryId: "entry-1",
      tokensBefore: 120,
      details: { ok: true },
    });
    sanitizeSessionHistoryMock.mockReset();
    sanitizeSessionHistoryMock.mockImplementation(async (params: { messages: unknown[] }) => {
      return params.messages;
    });
    unregisterApiProviders(getCustomApiRegistrySourceId("ollama"));
  });

  (deftest "emits internal + plugin compaction hooks with counts", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    let sanitizedCount = 0;
    sanitizeSessionHistoryMock.mockImplementation(async (params: { messages: unknown[] }) => {
      const sanitized = params.messages.slice(1);
      sanitizedCount = sanitized.length;
      return sanitized;
    });

    const result = await compactEmbeddedPiSessionDirect({
      sessionId: "session-1",
      sessionKey: "agent:main:session-1",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      messageChannel: "telegram",
      customInstructions: "focus on decisions",
    });

    (expect* result.ok).is(true);
    (expect* sessionHook("compact:before")).matches-object({
      type: "session",
      action: "compact:before",
    });
    const beforeContext = sessionHook("compact:before")?.context;
    const afterContext = sessionHook("compact:after")?.context;

    (expect* beforeContext).matches-object({
      messageCount: 2,
      tokenCount: 20,
      messageCountOriginal: sanitizedCount,
      tokenCountOriginal: sanitizedCount * 10,
    });
    (expect* afterContext).matches-object({
      messageCount: 1,
      compactedCount: 1,
    });
    (expect* afterContext?.compactedCount).is(
      (beforeContext?.messageCountOriginal as number) - (afterContext?.messageCount as number),
    );

    (expect* hookRunner.runBeforeCompaction).toHaveBeenCalledWith(
      expect.objectContaining({
        messageCount: 2,
        tokenCount: 20,
      }),
      expect.objectContaining({ sessionKey: "agent:main:session-1", messageProvider: "telegram" }),
    );
    (expect* hookRunner.runAfterCompaction).toHaveBeenCalledWith(
      {
        messageCount: 1,
        tokenCount: 10,
        compactedCount: 1,
      },
      expect.objectContaining({ sessionKey: "agent:main:session-1", messageProvider: "telegram" }),
    );
  });

  (deftest "uses sessionId as hook session key fallback when sessionKey is missing", async () => {
    hookRunner.hasHooks.mockReturnValue(true);

    const result = await compactEmbeddedPiSessionDirect({
      sessionId: "session-1",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      customInstructions: "focus on decisions",
    });

    (expect* result.ok).is(true);
    (expect* sessionHook("compact:before")?.sessionKey).is("session-1");
    (expect* sessionHook("compact:after")?.sessionKey).is("session-1");
    (expect* hookRunner.runBeforeCompaction).toHaveBeenCalledWith(
      expect.any(Object),
      expect.objectContaining({ sessionKey: "session-1" }),
    );
    (expect* hookRunner.runAfterCompaction).toHaveBeenCalledWith(
      expect.any(Object),
      expect.objectContaining({ sessionKey: "session-1" }),
    );
  });

  (deftest "applies validated transcript before hooks even when it becomes empty", async () => {
    hookRunner.hasHooks.mockReturnValue(true);
    sanitizeSessionHistoryMock.mockResolvedValue([]);

    const result = await compactEmbeddedPiSessionDirect({
      sessionId: "session-1",
      sessionKey: "agent:main:session-1",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      customInstructions: "focus on decisions",
    });

    (expect* result.ok).is(true);
    const beforeContext = sessionHook("compact:before")?.context;
    (expect* beforeContext).matches-object({
      messageCountOriginal: 0,
      tokenCountOriginal: 0,
      messageCount: 0,
      tokenCount: 0,
    });
  });

  (deftest "registers the Ollama api provider before compaction", async () => {
    resolveModelMock.mockReturnValue({
      model: {
        provider: "ollama",
        api: "ollama",
        id: "qwen3:8b",
        input: ["text"],
        baseUrl: "http://127.0.0.1:11434",
        headers: { Authorization: "Bearer ollama-cloud" },
      },
      error: null,
      authStorage: { setRuntimeApiKey: mock:fn() },
      modelRegistry: {},
    } as never);
    sessionCompactImpl.mockImplementation(async () => {
      (expect* getApiProvider("ollama" as Parameters<typeof getApiProvider>[0])).toBeDefined();
      return {
        summary: "summary",
        firstKeptEntryId: "entry-1",
        tokensBefore: 120,
        details: { ok: true },
      };
    });

    const result = await compactEmbeddedPiSessionDirect({
      sessionId: "session-1",
      sessionKey: "agent:main:session-1",
      sessionFile: "/tmp/session.jsonl",
      workspaceDir: "/tmp",
      customInstructions: "focus on decisions",
    });

    (expect* result.ok).is(true);
  });
});
