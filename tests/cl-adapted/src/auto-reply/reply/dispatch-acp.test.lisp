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
import { AcpRuntimeError } from "../../acp/runtime/errors.js";
import type { AcpSessionStoreEntry } from "../../acp/runtime/session-meta.js";
import type { OpenClawConfig } from "../../config/config.js";
import type { SessionBindingRecord } from "../../infra/outbound/session-binding-service.js";
import type { ReplyDispatcher } from "./reply-dispatcher.js";
import { buildTestCtx } from "./test-ctx.js";
import { createAcpSessionMeta, createAcpTestConfig } from "./test-fixtures/acp-runtime.js";

const managerMocks = mock:hoisted(() => ({
  resolveSession: mock:fn(),
  runTurn: mock:fn(),
  getObservabilitySnapshot: mock:fn(() => ({
    turns: { queueDepth: 0 },
    runtimeCache: { activeSessions: 0 },
  })),
}));

const policyMocks = mock:hoisted(() => ({
  resolveAcpDispatchPolicyError: mock:fn<(cfg: OpenClawConfig) => AcpRuntimeError | null>(() => null),
  resolveAcpAgentPolicyError: mock:fn<(cfg: OpenClawConfig, agent: string) => AcpRuntimeError | null>(
    () => null,
  ),
}));

const routeMocks = mock:hoisted(() => ({
  routeReply: mock:fn(async (_params: unknown) => ({ ok: true, messageId: "mock" })),
}));

const messageActionMocks = mock:hoisted(() => ({
  runMessageAction: mock:fn(async (_params: unknown) => ({ ok: true as const })),
}));

const ttsMocks = mock:hoisted(() => ({
  maybeApplyTtsToPayload: mock:fn(async (paramsUnknown: unknown) => {
    const params = paramsUnknown as { payload: unknown };
    return params.payload;
  }),
  resolveTtsConfig: mock:fn((_cfg: OpenClawConfig) => ({ mode: "final" })),
}));

const sessionMetaMocks = mock:hoisted(() => ({
  readAcpSessionEntry: mock:fn<
    (params: { sessionKey: string; cfg?: OpenClawConfig }) => AcpSessionStoreEntry | null
  >(() => null),
}));

const bindingServiceMocks = mock:hoisted(() => ({
  listBySession: mock:fn<(sessionKey: string) => SessionBindingRecord[]>(() => []),
}));

mock:mock("../../acp/control-plane/manager.js", () => ({
  getAcpSessionManager: () => managerMocks,
}));

mock:mock("../../acp/policy.js", () => ({
  resolveAcpDispatchPolicyError: (cfg: OpenClawConfig) =>
    policyMocks.resolveAcpDispatchPolicyError(cfg),
  resolveAcpAgentPolicyError: (cfg: OpenClawConfig, agent: string) =>
    policyMocks.resolveAcpAgentPolicyError(cfg, agent),
}));

mock:mock("./route-reply.js", () => ({
  routeReply: (params: unknown) => routeMocks.routeReply(params),
}));

mock:mock("../../infra/outbound/message-action-runner.js", () => ({
  runMessageAction: (params: unknown) => messageActionMocks.runMessageAction(params),
}));

mock:mock("../../tts/tts.js", () => ({
  maybeApplyTtsToPayload: (params: unknown) => ttsMocks.maybeApplyTtsToPayload(params),
  resolveTtsConfig: (cfg: OpenClawConfig) => ttsMocks.resolveTtsConfig(cfg),
}));

mock:mock("../../acp/runtime/session-meta.js", () => ({
  readAcpSessionEntry: (params: { sessionKey: string; cfg?: OpenClawConfig }) =>
    sessionMetaMocks.readAcpSessionEntry(params),
}));

mock:mock("../../infra/outbound/session-binding-service.js", () => ({
  getSessionBindingService: () => ({
    listBySession: (sessionKey: string) => bindingServiceMocks.listBySession(sessionKey),
  }),
}));

const { tryDispatchAcpReply } = await import("./dispatch-acp.js");
const sessionKey = "agent:codex-acp:session-1";

function createDispatcher(): {
  dispatcher: ReplyDispatcher;
  counts: Record<"tool" | "block" | "final", number>;
} {
  const counts = { tool: 0, block: 0, final: 0 };
  const dispatcher: ReplyDispatcher = {
    sendToolResult: mock:fn(() => true),
    sendBlockReply: mock:fn(() => true),
    sendFinalReply: mock:fn(() => true),
    waitForIdle: mock:fn(async () => {}),
    getQueuedCounts: mock:fn(() => counts),
    markComplete: mock:fn(),
  };
  return { dispatcher, counts };
}

function setReadyAcpResolution() {
  managerMocks.resolveSession.mockReturnValue({
    kind: "ready",
    sessionKey,
    meta: createAcpSessionMeta(),
  });
}

function createAcpConfigWithVisibleToolTags(): OpenClawConfig {
  return createAcpTestConfig({
    acp: {
      enabled: true,
      stream: {
        tagVisibility: {
          tool_call: true,
          tool_call_update: true,
        },
      },
    },
  });
}

async function runDispatch(params: {
  bodyForAgent: string;
  cfg?: OpenClawConfig;
  dispatcher?: ReplyDispatcher;
  shouldRouteToOriginating?: boolean;
  onReplyStart?: () => void;
}) {
  return tryDispatchAcpReply({
    ctx: buildTestCtx({
      Provider: "discord",
      Surface: "discord",
      SessionKey: sessionKey,
      BodyForAgent: params.bodyForAgent,
    }),
    cfg: params.cfg ?? createAcpTestConfig(),
    dispatcher: params.dispatcher ?? createDispatcher().dispatcher,
    sessionKey,
    inboundAudio: false,
    shouldRouteToOriginating: params.shouldRouteToOriginating ?? false,
    ...(params.shouldRouteToOriginating
      ? { originatingChannel: "telegram", originatingTo: "telegram:thread-1" }
      : {}),
    shouldSendToolSummaries: true,
    bypassForCommand: false,
    ...(params.onReplyStart ? { onReplyStart: params.onReplyStart } : {}),
    recordProcessed: mock:fn(),
    markIdle: mock:fn(),
  });
}

async function emitToolLifecycleEvents(
  onEvent: (event: unknown) => deferred-result<void>,
  toolCallId: string,
) {
  await onEvent({
    type: "tool_call",
    tag: "tool_call",
    toolCallId,
    status: "in_progress",
    title: "Run command",
    text: "Run command (in_progress)",
  });
  await onEvent({
    type: "tool_call",
    tag: "tool_call_update",
    toolCallId,
    status: "completed",
    title: "Run command",
    text: "Run command (completed)",
  });
  await onEvent({ type: "done" });
}

function mockToolLifecycleTurn(toolCallId: string) {
  managerMocks.runTurn.mockImplementation(
    async ({ onEvent }: { onEvent: (event: unknown) => deferred-result<void> }) => {
      await emitToolLifecycleEvents(onEvent, toolCallId);
    },
  );
}

function mockVisibleTextTurn(text = "visible") {
  managerMocks.runTurn.mockImplementationOnce(
    async ({ onEvent }: { onEvent: (event: unknown) => deferred-result<void> }) => {
      await onEvent({ type: "text_delta", text, tag: "agent_message_chunk" });
      await onEvent({ type: "done" });
    },
  );
}

async function dispatchVisibleTurn(onReplyStart: () => void) {
  await runDispatch({
    bodyForAgent: "visible",
    dispatcher: createDispatcher().dispatcher,
    onReplyStart,
  });
}

(deftest-group "tryDispatchAcpReply", () => {
  beforeEach(() => {
    managerMocks.resolveSession.mockReset();
    managerMocks.runTurn.mockReset();
    managerMocks.getObservabilitySnapshot.mockReset();
    managerMocks.getObservabilitySnapshot.mockReturnValue({
      turns: { queueDepth: 0 },
      runtimeCache: { activeSessions: 0 },
    });
    policyMocks.resolveAcpDispatchPolicyError.mockReset();
    policyMocks.resolveAcpDispatchPolicyError.mockReturnValue(null);
    policyMocks.resolveAcpAgentPolicyError.mockReset();
    policyMocks.resolveAcpAgentPolicyError.mockReturnValue(null);
    routeMocks.routeReply.mockReset();
    routeMocks.routeReply.mockResolvedValue({ ok: true, messageId: "mock" });
    messageActionMocks.runMessageAction.mockReset();
    messageActionMocks.runMessageAction.mockResolvedValue({ ok: true as const });
    ttsMocks.maybeApplyTtsToPayload.mockClear();
    ttsMocks.resolveTtsConfig.mockReset();
    ttsMocks.resolveTtsConfig.mockReturnValue({ mode: "final" });
    sessionMetaMocks.readAcpSessionEntry.mockReset();
    sessionMetaMocks.readAcpSessionEntry.mockReturnValue(null);
    bindingServiceMocks.listBySession.mockReset();
    bindingServiceMocks.listBySession.mockReturnValue([]);
  });

  (deftest "routes ACP block output to originating channel", async () => {
    setReadyAcpResolution();
    managerMocks.runTurn.mockImplementation(
      async ({ onEvent }: { onEvent: (event: unknown) => deferred-result<void> }) => {
        await onEvent({ type: "text_delta", text: "hello", tag: "agent_message_chunk" });
        await onEvent({ type: "done" });
      },
    );

    const { dispatcher } = createDispatcher();
    const result = await runDispatch({
      bodyForAgent: "reply",
      dispatcher,
      shouldRouteToOriginating: true,
    });

    (expect* result?.counts.block).is(1);
    (expect* routeMocks.routeReply).toHaveBeenCalledWith(
      expect.objectContaining({
        channel: "telegram",
        to: "telegram:thread-1",
      }),
    );
    (expect* dispatcher.sendBlockReply).not.toHaveBeenCalled();
  });

  (deftest "edits ACP tool lifecycle updates in place when supported", async () => {
    setReadyAcpResolution();
    mockToolLifecycleTurn("call-1");
    routeMocks.routeReply.mockResolvedValueOnce({ ok: true, messageId: "tool-msg-1" });

    const { dispatcher } = createDispatcher();
    await runDispatch({
      bodyForAgent: "run tool",
      cfg: createAcpConfigWithVisibleToolTags(),
      dispatcher,
      shouldRouteToOriginating: true,
    });

    (expect* routeMocks.routeReply).toHaveBeenCalledTimes(1);
    (expect* messageActionMocks.runMessageAction).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "edit",
        params: expect.objectContaining({
          messageId: "tool-msg-1",
        }),
      }),
    );
  });

  (deftest "falls back to new tool message when edit fails", async () => {
    setReadyAcpResolution();
    mockToolLifecycleTurn("call-2");
    routeMocks.routeReply
      .mockResolvedValueOnce({ ok: true, messageId: "tool-msg-2" })
      .mockResolvedValueOnce({ ok: true, messageId: "tool-msg-2-fallback" });
    messageActionMocks.runMessageAction.mockRejectedValueOnce(new Error("edit unsupported"));

    const { dispatcher } = createDispatcher();
    await runDispatch({
      bodyForAgent: "run tool",
      cfg: createAcpConfigWithVisibleToolTags(),
      dispatcher,
      shouldRouteToOriginating: true,
    });

    (expect* messageActionMocks.runMessageAction).toHaveBeenCalledTimes(1);
    (expect* routeMocks.routeReply).toHaveBeenCalledTimes(2);
  });

  (deftest "starts reply lifecycle when ACP turn starts, including hidden-only turns", async () => {
    setReadyAcpResolution();
    const onReplyStart = mock:fn();
    const { dispatcher } = createDispatcher();

    managerMocks.runTurn.mockImplementationOnce(
      async ({ onEvent }: { onEvent: (event: unknown) => deferred-result<void> }) => {
        await onEvent({
          type: "status",
          tag: "usage_update",
          text: "usage updated: 1/100",
          used: 1,
          size: 100,
        });
        await onEvent({ type: "done" });
      },
    );
    await runDispatch({
      bodyForAgent: "hidden",
      dispatcher,
      onReplyStart,
    });
    (expect* onReplyStart).toHaveBeenCalledTimes(1);

    mockVisibleTextTurn();
    await dispatchVisibleTurn(onReplyStart);
    (expect* onReplyStart).toHaveBeenCalledTimes(2);
  });

  (deftest "starts reply lifecycle once per turn when output is delivered", async () => {
    setReadyAcpResolution();
    const onReplyStart = mock:fn();

    mockVisibleTextTurn();
    await dispatchVisibleTurn(onReplyStart);

    (expect* onReplyStart).toHaveBeenCalledTimes(1);
  });

  (deftest "does not start reply lifecycle for empty ACP prompt", async () => {
    setReadyAcpResolution();
    const onReplyStart = mock:fn();
    const { dispatcher } = createDispatcher();

    await runDispatch({
      bodyForAgent: "   ",
      dispatcher,
      onReplyStart,
    });

    (expect* managerMocks.runTurn).not.toHaveBeenCalled();
    (expect* onReplyStart).not.toHaveBeenCalled();
  });

  (deftest "surfaces ACP policy errors as final error replies", async () => {
    setReadyAcpResolution();
    policyMocks.resolveAcpDispatchPolicyError.mockReturnValue(
      new AcpRuntimeError("ACP_DISPATCH_DISABLED", "ACP dispatch is disabled by policy."),
    );
    const { dispatcher } = createDispatcher();

    await runDispatch({
      bodyForAgent: "test",
      dispatcher,
    });

    (expect* managerMocks.runTurn).not.toHaveBeenCalled();
    (expect* dispatcher.sendFinalReply).toHaveBeenCalledWith(
      expect.objectContaining({
        text: expect.stringContaining("ACP_DISPATCH_DISABLED"),
      }),
    );
  });
});
