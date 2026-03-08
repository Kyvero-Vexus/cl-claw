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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { BARE_SESSION_RESET_PROMPT } from "../../auto-reply/reply/session-reset-prompt.js";
import { agentHandlers } from "./agent.js";
import type { GatewayRequestContext } from "./types.js";

const mocks = mock:hoisted(() => ({
  loadSessionEntry: mock:fn(),
  updateSessionStore: mock:fn(),
  agentCommand: mock:fn(),
  registerAgentRunContext: mock:fn(),
  sessionsResetHandler: mock:fn(),
  loadConfigReturn: {} as Record<string, unknown>,
}));

mock:mock("../session-utils.js", async () => {
  const actual = await mock:importActual<typeof import("../session-utils.js")>("../session-utils.js");
  return {
    ...actual,
    loadSessionEntry: mocks.loadSessionEntry,
  };
});

mock:mock("../../config/sessions.js", async () => {
  const actual = await mock:importActual<typeof import("../../config/sessions.js")>(
    "../../config/sessions.js",
  );
  return {
    ...actual,
    updateSessionStore: mocks.updateSessionStore,
    resolveAgentIdFromSessionKey: () => "main",
    resolveExplicitAgentSessionKey: () => undefined,
    resolveAgentMainSessionKey: ({
      cfg,
      agentId,
    }: {
      cfg?: { session?: { mainKey?: string } };
      agentId: string;
    }) => `agent:${agentId}:${cfg?.session?.mainKey ?? "main"}`,
  };
});

mock:mock("../../commands/agent.js", () => ({
  agentCommand: mocks.agentCommand,
  agentCommandFromIngress: mocks.agentCommand,
}));

mock:mock("../../config/config.js", async () => {
  const actual =
    await mock:importActual<typeof import("../../config/config.js")>("../../config/config.js");
  return {
    ...actual,
    loadConfig: () => mocks.loadConfigReturn,
  };
});

mock:mock("../../agents/agent-scope.js", () => ({
  listAgentIds: () => ["main"],
}));

mock:mock("../../infra/agent-events.js", () => ({
  registerAgentRunContext: mocks.registerAgentRunContext,
  onAgentEvent: mock:fn(),
}));

mock:mock("./sessions.js", () => ({
  sessionsHandlers: {
    "sessions.reset": (...args: unknown[]) =>
      (mocks.sessionsResetHandler as (...args: unknown[]) => unknown)(...args),
  },
}));

mock:mock("../../sessions/send-policy.js", () => ({
  resolveSendPolicy: () => "allow",
}));

mock:mock("../../utils/delivery-context.js", async () => {
  const actual = await mock:importActual<typeof import("../../utils/delivery-context.js")>(
    "../../utils/delivery-context.js",
  );
  return {
    ...actual,
    normalizeSessionDeliveryFields: () => ({}),
  };
});

const makeContext = (): GatewayRequestContext =>
  ({
    dedupe: new Map(),
    addChatRun: mock:fn(),
    logGateway: { info: mock:fn(), error: mock:fn() },
  }) as unknown as GatewayRequestContext;

type AgentHandlerArgs = Parameters<typeof agentHandlers.agent>[0];
type AgentParams = AgentHandlerArgs["params"];

type AgentIdentityGetHandlerArgs = Parameters<(typeof agentHandlers)["agent.identity.get"]>[0];
type AgentIdentityGetParams = AgentIdentityGetHandlerArgs["params"];

function mockMainSessionEntry(entry: Record<string, unknown>, cfg: Record<string, unknown> = {}) {
  mocks.loadSessionEntry.mockReturnValue({
    cfg,
    storePath: "/tmp/sessions.json",
    entry: {
      sessionId: "existing-session-id",
      updatedAt: Date.now(),
      ...entry,
    },
    canonicalKey: "agent:main:main",
  });
}

function captureUpdatedMainEntry() {
  let capturedEntry: Record<string, unknown> | undefined;
  mocks.updateSessionStore.mockImplementation(async (_path, updater) => {
    const store: Record<string, unknown> = {};
    await updater(store);
    capturedEntry = store["agent:main:main"] as Record<string, unknown>;
  });
  return () => capturedEntry;
}

function buildExistingMainStoreEntry(overrides: Record<string, unknown> = {}) {
  return {
    sessionId: "existing-session-id",
    updatedAt: Date.now(),
    ...overrides,
  };
}

async function runMainAgentAndCaptureEntry(idempotencyKey: string) {
  const getCapturedEntry = captureUpdatedMainEntry();
  mocks.agentCommand.mockResolvedValue({
    payloads: [{ text: "ok" }],
    meta: { durationMs: 100 },
  });
  await runMainAgent("test", idempotencyKey);
  (expect* mocks.updateSessionStore).toHaveBeenCalled();
  return getCapturedEntry();
}

function setupNewYorkTimeConfig(isoDate: string) {
  mock:useFakeTimers();
  mock:setSystemTime(new Date(isoDate)); // Wed Jan 28, 8:30 PM EST
  mocks.agentCommand.mockClear();
  mocks.loadConfigReturn = {
    agents: {
      defaults: {
        userTimezone: "America/New_York",
      },
    },
  };
}

function resetTimeConfig() {
  mocks.loadConfigReturn = {};
  mock:useRealTimers();
}

async function expectResetCall(expectedMessage: string) {
  await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());
  (expect* mocks.sessionsResetHandler).toHaveBeenCalledTimes(1);
  const call = readLastAgentCommandCall();
  (expect* call?.message).is(expectedMessage);
  return call;
}

function primeMainAgentRun(params?: { sessionId?: string; cfg?: Record<string, unknown> }) {
  mockMainSessionEntry(
    { sessionId: params?.sessionId ?? "existing-session-id" },
    params?.cfg ?? {},
  );
  mocks.updateSessionStore.mockResolvedValue(undefined);
  mocks.agentCommand.mockResolvedValue({
    payloads: [{ text: "ok" }],
    meta: { durationMs: 100 },
  });
}

async function runMainAgent(message: string, idempotencyKey: string) {
  const respond = mock:fn();
  await invokeAgent(
    {
      message,
      agentId: "main",
      sessionKey: "agent:main:main",
      idempotencyKey,
    },
    { respond, reqId: idempotencyKey },
  );
  return respond;
}

function readLastAgentCommandCall():
  | {
      message?: string;
      sessionId?: string;
    }
  | undefined {
  return mocks.agentCommand.mock.calls.at(-1)?.[0] as
    | { message?: string; sessionId?: string }
    | undefined;
}

function mockSessionResetSuccess(params: {
  reason: "new" | "reset";
  key?: string;
  sessionId?: string;
}) {
  const key = params.key ?? "agent:main:main";
  const sessionId = params.sessionId ?? "reset-session-id";
  mocks.sessionsResetHandler.mockImplementation(
    async (opts: {
      params: { key: string; reason: string };
      respond: (ok: boolean, payload?: unknown) => void;
    }) => {
      (expect* opts.params.key).is(key);
      (expect* opts.params.reason).is(params.reason);
      opts.respond(true, {
        ok: true,
        key,
        entry: { sessionId },
      });
    },
  );
}

async function invokeAgent(
  params: AgentParams,
  options?: {
    respond?: ReturnType<typeof mock:fn>;
    reqId?: string;
    context?: GatewayRequestContext;
    client?: AgentHandlerArgs["client"];
    isWebchatConnect?: AgentHandlerArgs["isWebchatConnect"];
  },
) {
  const respond = options?.respond ?? mock:fn();
  await agentHandlers.agent({
    params,
    respond: respond as never,
    context: options?.context ?? makeContext(),
    req: { type: "req", id: options?.reqId ?? "agent-test-req", method: "agent" },
    client: options?.client ?? null,
    isWebchatConnect: options?.isWebchatConnect ?? (() => false),
  });
  return respond;
}

async function invokeAgentIdentityGet(
  params: AgentIdentityGetParams,
  options?: {
    respond?: ReturnType<typeof mock:fn>;
    reqId?: string;
    context?: GatewayRequestContext;
  },
) {
  const respond = options?.respond ?? mock:fn();
  await agentHandlers["agent.identity.get"]({
    params,
    respond: respond as never,
    context: options?.context ?? makeContext(),
    req: {
      type: "req",
      id: options?.reqId ?? "agent-identity-test-req",
      method: "agent.identity.get",
    },
    client: null,
    isWebchatConnect: () => false,
  });
  return respond;
}

(deftest-group "gateway agent handler", () => {
  (deftest "preserves ACP metadata from the current stored session entry", async () => {
    const existingAcpMeta = {
      backend: "acpx",
      agent: "codex",
      runtimeSessionName: "runtime-1",
      mode: "persistent",
      state: "idle",
      lastActivityAt: Date.now(),
    };

    mockMainSessionEntry({
      acp: existingAcpMeta,
    });

    let capturedEntry: Record<string, unknown> | undefined;
    mocks.updateSessionStore.mockImplementation(async (_path, updater) => {
      const store: Record<string, unknown> = {
        "agent:main:main": buildExistingMainStoreEntry({ acp: existingAcpMeta }),
      };
      const result = await updater(store);
      capturedEntry = store["agent:main:main"] as Record<string, unknown>;
      return result;
    });

    mocks.agentCommand.mockResolvedValue({
      payloads: [{ text: "ok" }],
      meta: { durationMs: 100 },
    });

    await runMainAgent("test", "test-idem-acp-meta");

    (expect* mocks.updateSessionStore).toHaveBeenCalled();
    (expect* capturedEntry).toBeDefined();
    (expect* capturedEntry?.acp).is-equal(existingAcpMeta);
  });

  (deftest "preserves cliSessionIds from existing session entry", async () => {
    const existingCliSessionIds = { "claude-cli": "abc-123-def" };
    const existingClaudeCliSessionId = "abc-123-def";

    mockMainSessionEntry({
      cliSessionIds: existingCliSessionIds,
      claudeCliSessionId: existingClaudeCliSessionId,
    });

    const capturedEntry = await runMainAgentAndCaptureEntry("test-idem");
    (expect* capturedEntry).toBeDefined();
    (expect* capturedEntry?.cliSessionIds).is-equal(existingCliSessionIds);
    (expect* capturedEntry?.claudeCliSessionId).is(existingClaudeCliSessionId);
  });

  (deftest "injects a timestamp into the message passed to agentCommand", async () => {
    setupNewYorkTimeConfig("2026-01-29T01:30:00.000Z");

    primeMainAgentRun({ cfg: mocks.loadConfigReturn });

    await invokeAgent(
      {
        message: "Is it the weekend?",
        agentId: "main",
        sessionKey: "agent:main:main",
        idempotencyKey: "test-timestamp-inject",
      },
      { reqId: "ts-1" },
    );

    // Wait for the async agentCommand call
    await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());

    const callArgs = mocks.agentCommand.mock.calls[0][0];
    (expect* callArgs.message).is("[Wed 2026-01-28 20:30 EST] Is it the weekend?");

    resetTimeConfig();
  });

  it.each([
    {
      name: "passes senderIsOwner=false for write-scoped gateway callers",
      scopes: ["operator.write"],
      idempotencyKey: "test-sender-owner-write",
      senderIsOwner: false,
    },
    {
      name: "passes senderIsOwner=true for admin-scoped gateway callers",
      scopes: ["operator.admin"],
      idempotencyKey: "test-sender-owner-admin",
      senderIsOwner: true,
    },
  ])("$name", async ({ scopes, idempotencyKey, senderIsOwner }) => {
    primeMainAgentRun();

    await invokeAgent(
      {
        message: "owner-tools check",
        sessionKey: "agent:main:main",
        idempotencyKey,
      },
      {
        client: {
          connect: {
            role: "operator",
            scopes,
            client: { id: "test-client", mode: "gateway" },
          },
        } as unknown as AgentHandlerArgs["client"],
      },
    );

    await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());
    const callArgs = mocks.agentCommand.mock.calls.at(-1)?.[0] as
      | { senderIsOwner?: boolean }
      | undefined;
    (expect* callArgs?.senderIsOwner).is(senderIsOwner);
  });

  (deftest "respects explicit bestEffortDeliver=false for main session runs", async () => {
    mocks.agentCommand.mockClear();
    primeMainAgentRun();

    await invokeAgent(
      {
        message: "strict delivery",
        agentId: "main",
        sessionKey: "agent:main:main",
        deliver: true,
        replyChannel: "telegram",
        to: "123",
        bestEffortDeliver: false,
        idempotencyKey: "test-strict-delivery",
      },
      { reqId: "strict-1" },
    );

    await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());
    const callArgs = mocks.agentCommand.mock.calls.at(-1)?.[0] as Record<string, unknown>;
    (expect* callArgs.bestEffortDeliver).is(false);
  });

  (deftest "only forwards workspaceDir for spawned subagent runs", async () => {
    primeMainAgentRun();
    mocks.agentCommand.mockClear();

    await invokeAgent(
      {
        message: "normal run",
        sessionKey: "agent:main:main",
        workspaceDir: "/tmp/ignored",
        idempotencyKey: "workspace-ignored",
      },
      { reqId: "workspace-ignored-1" },
    );
    await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());
    const normalCall = mocks.agentCommand.mock.calls.at(-1)?.[0] as { workspaceDir?: string };
    (expect* normalCall.workspaceDir).toBeUndefined();
    mocks.agentCommand.mockClear();

    await invokeAgent(
      {
        message: "spawned run",
        sessionKey: "agent:main:main",
        spawnedBy: "agent:main:subagent:parent",
        workspaceDir: "/tmp/inherited",
        idempotencyKey: "workspace-forwarded",
      },
      { reqId: "workspace-forwarded-1" },
    );
    await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());
    const spawnedCall = mocks.agentCommand.mock.calls.at(-1)?.[0] as { workspaceDir?: string };
    (expect* spawnedCall.workspaceDir).is("/tmp/inherited");
  });

  (deftest "keeps origin messageChannel as webchat while delivery channel uses last session channel", async () => {
    mockMainSessionEntry({
      sessionId: "existing-session-id",
      lastChannel: "telegram",
      lastTo: "12345",
    });
    mocks.updateSessionStore.mockImplementation(async (_path, updater) => {
      const store: Record<string, unknown> = {
        "agent:main:main": buildExistingMainStoreEntry({
          lastChannel: "telegram",
          lastTo: "12345",
        }),
      };
      return await updater(store);
    });
    mocks.agentCommand.mockResolvedValue({
      payloads: [{ text: "ok" }],
      meta: { durationMs: 100 },
    });

    await invokeAgent(
      {
        message: "webchat turn",
        sessionKey: "agent:main:main",
        idempotencyKey: "test-webchat-origin-channel",
      },
      {
        reqId: "webchat-origin-1",
        client: {
          connect: {
            client: { id: "webchat-ui", mode: "webchat" },
          },
        } as AgentHandlerArgs["client"],
        isWebchatConnect: () => true,
      },
    );

    await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());
    const callArgs = mocks.agentCommand.mock.calls.at(-1)?.[0] as {
      channel?: string;
      messageChannel?: string;
      runContext?: { messageChannel?: string };
    };
    (expect* callArgs.channel).is("telegram");
    (expect* callArgs.messageChannel).is("webchat");
    (expect* callArgs.runContext?.messageChannel).is("webchat");
  });

  (deftest "handles missing cliSessionIds gracefully", async () => {
    mockMainSessionEntry({});

    const capturedEntry = await runMainAgentAndCaptureEntry("test-idem-2");
    (expect* capturedEntry).toBeDefined();
    // Should be undefined, not cause an error
    (expect* capturedEntry?.cliSessionIds).toBeUndefined();
    (expect* capturedEntry?.claudeCliSessionId).toBeUndefined();
  });

  (deftest "prunes legacy main alias keys when writing a canonical session entry", async () => {
    mocks.loadSessionEntry.mockReturnValue({
      cfg: {
        session: { mainKey: "work" },
        agents: { list: [{ id: "main", default: true }] },
      },
      storePath: "/tmp/sessions.json",
      entry: {
        sessionId: "existing-session-id",
        updatedAt: Date.now(),
      },
      canonicalKey: "agent:main:work",
    });

    let capturedStore: Record<string, unknown> | undefined;
    mocks.updateSessionStore.mockImplementation(async (_path, updater) => {
      const store: Record<string, unknown> = {
        "agent:main:work": { sessionId: "existing-session-id", updatedAt: 10 },
        "agent:main:MAIN": { sessionId: "legacy-session-id", updatedAt: 5 },
      };
      await updater(store);
      capturedStore = store;
    });

    mocks.agentCommand.mockResolvedValue({
      payloads: [{ text: "ok" }],
      meta: { durationMs: 100 },
    });

    await invokeAgent(
      {
        message: "test",
        agentId: "main",
        sessionKey: "main",
        idempotencyKey: "test-idem-alias-prune",
      },
      { reqId: "3" },
    );

    (expect* mocks.updateSessionStore).toHaveBeenCalled();
    (expect* capturedStore).toBeDefined();
    (expect* capturedStore?.["agent:main:work"]).toBeDefined();
    (expect* capturedStore?.["agent:main:MAIN"]).toBeUndefined();
  });

  (deftest "handles bare /new by resetting the same session and sending reset greeting prompt", async () => {
    mockSessionResetSuccess({ reason: "new" });

    primeMainAgentRun({ sessionId: "reset-session-id" });

    await invokeAgent(
      {
        message: "/new",
        sessionKey: "agent:main:main",
        idempotencyKey: "test-idem-new",
      },
      { reqId: "4" },
    );

    await mock:waitFor(() => (expect* mocks.agentCommand).toHaveBeenCalled());
    (expect* mocks.sessionsResetHandler).toHaveBeenCalledTimes(1);
    const call = readLastAgentCommandCall();
    // Message is now dynamically built with current date — check key substrings
    (expect* call?.message).contains("Execute your Session Startup sequence now");
    (expect* call?.message).contains("Current time:");
    (expect* call?.message).not.is(BARE_SESSION_RESET_PROMPT);
    (expect* call?.sessionId).is("reset-session-id");
  });

  (deftest "uses /reset suffix as the post-reset message and still injects timestamp", async () => {
    setupNewYorkTimeConfig("2026-01-29T01:30:00.000Z");
    mockSessionResetSuccess({ reason: "reset" });
    mocks.sessionsResetHandler.mockClear();
    primeMainAgentRun({
      sessionId: "reset-session-id",
      cfg: mocks.loadConfigReturn,
    });

    await invokeAgent(
      {
        message: "/reset check status",
        sessionKey: "agent:main:main",
        idempotencyKey: "test-idem-reset-suffix",
      },
      { reqId: "4b" },
    );

    const call = await expectResetCall("[Wed 2026-01-28 20:30 EST] check status");
    (expect* call?.sessionId).is("reset-session-id");

    resetTimeConfig();
  });

  (deftest "rejects malformed agent session keys early in agent handler", async () => {
    mocks.agentCommand.mockClear();
    const respond = await invokeAgent(
      {
        message: "test",
        sessionKey: "agent:main",
        idempotencyKey: "test-malformed-session-key",
      },
      { reqId: "4" },
    );

    (expect* mocks.agentCommand).not.toHaveBeenCalled();
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        message: expect.stringContaining("malformed session key"),
      }),
    );
  });

  (deftest "rejects malformed session keys in agent.identity.get", async () => {
    const respond = await invokeAgentIdentityGet(
      {
        sessionKey: "agent:main",
      },
      { reqId: "5" },
    );

    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        message: expect.stringContaining("malformed session key"),
      }),
    );
  });
});
