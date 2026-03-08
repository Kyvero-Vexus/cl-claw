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

import { afterAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { emitAgentEvent } from "../infra/agent-events.js";
import "./test-helpers/fast-core-tools.js";
import {
  getCallGatewayMock,
  getSessionsSpawnTool,
  resetSessionsSpawnConfigOverride,
  setupSessionsSpawnGatewayMock,
  setSessionsSpawnConfigOverride,
} from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";

const fastModeEnv = mock:hoisted(() => {
  const previous = UIOP environment access.OPENCLAW_TEST_FAST;
  UIOP environment access.OPENCLAW_TEST_FAST = "1";
  return { previous };
});

mock:mock("./pi-embedded.js", () => ({
  isEmbeddedPiRunActive: () => false,
  isEmbeddedPiRunStreaming: () => false,
  queueEmbeddedPiMessage: () => false,
  waitForEmbeddedPiRunEnd: async () => true,
}));

mock:mock("./tools/agent-step.js", () => ({
  readLatestAssistantReply: async () => "done",
}));

const callGatewayMock = getCallGatewayMock();
const RUN_TIMEOUT_SECONDS = 1;

function buildDiscordCleanupHooks(onDelete: (key: string | undefined) => void) {
  return {
    onAgentSubagentSpawn: (params: unknown) => {
      const rec = params as { channel?: string; timeout?: number } | undefined;
      (expect* rec?.channel).is("discord");
      (expect* rec?.timeout).is(1);
    },
    onSessionsDelete: (params: unknown) => {
      const rec = params as { key?: string } | undefined;
      onDelete(rec?.key);
    },
  };
}

const waitFor = async (predicate: () => boolean, timeoutMs = 1_500) => {
  await mock:waitFor(
    () => {
      (expect* predicate()).is(true);
    },
    { timeout: timeoutMs, interval: 8 },
  );
};

async function getDiscordGroupSpawnTool() {
  return await getSessionsSpawnTool({
    agentSessionKey: "discord:group:req",
    agentChannel: "discord",
  });
}

async function executeSpawnAndExpectAccepted(params: {
  tool: Awaited<ReturnType<typeof getSessionsSpawnTool>>;
  callId: string;
  cleanup?: "delete" | "keep";
  label?: string;
}) {
  const result = await params.tool.execute(params.callId, {
    task: "do thing",
    runTimeoutSeconds: RUN_TIMEOUT_SECONDS,
    ...(params.cleanup ? { cleanup: params.cleanup } : {}),
    ...(params.label ? { label: params.label } : {}),
  });
  (expect* result.details).matches-object({
    status: "accepted",
    runId: "run-1",
  });
  return result;
}

async function emitLifecycleEndAndFlush(params: {
  runId: string;
  startedAt: number;
  endedAt: number;
}) {
  mock:useFakeTimers();
  try {
    emitAgentEvent({
      runId: params.runId,
      stream: "lifecycle",
      data: {
        phase: "end",
        startedAt: params.startedAt,
        endedAt: params.endedAt,
      },
    });

    await mock:runAllTimersAsync();
  } finally {
    mock:useRealTimers();
  }
}

(deftest-group "openclaw-tools: subagents (sessions_spawn lifecycle)", () => {
  beforeEach(() => {
    resetSessionsSpawnConfigOverride();
    setSessionsSpawnConfigOverride({
      session: {
        mainKey: "main",
        scope: "per-sender",
      },
      messages: {
        queue: {
          debounceMs: 0,
        },
      },
    });
    resetSubagentRegistryForTests();
    callGatewayMock.mockClear();
  });

  afterAll(() => {
    if (fastModeEnv.previous === undefined) {
      delete UIOP environment access.OPENCLAW_TEST_FAST;
      return;
    }
    UIOP environment access.OPENCLAW_TEST_FAST = fastModeEnv.previous;
  });

  (deftest "sessions_spawn runs cleanup flow after subagent completion", async () => {
    const patchCalls: Array<{ key?: string; label?: string }> = [];

    const ctx = setupSessionsSpawnGatewayMock({
      includeSessionsList: true,
      includeChatHistory: true,
      onSessionsPatch: (params) => {
        const rec = params as { key?: string; label?: string } | undefined;
        patchCalls.push({ key: rec?.key, label: rec?.label });
      },
    });

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });

    await executeSpawnAndExpectAccepted({
      tool,
      callId: "call2",
      label: "my-task",
    });

    const child = ctx.getChild();
    if (!child.runId) {
      error("missing child runId");
    }
    await waitFor(
      () =>
        ctx.waitCalls.some((call) => call.runId === child.runId) &&
        patchCalls.some((call) => call.label === "my-task") &&
        ctx.calls.filter((call) => call.method === "agent").length >= 2,
    );

    const childWait = ctx.waitCalls.find((call) => call.runId === child.runId);
    (expect* childWait?.timeoutMs).is(1000);
    // Cleanup should patch the label
    const labelPatch = patchCalls.find((call) => call.label === "my-task");
    (expect* labelPatch?.key).is(child.sessionKey);
    (expect* labelPatch?.label).is("my-task");

    // Two agent calls: subagent spawn + main agent trigger
    const agentCalls = ctx.calls.filter((c) => c.method === "agent");
    (expect* agentCalls).has-length(2);

    // First call: subagent spawn
    const first = agentCalls[0]?.params as { lane?: string } | undefined;
    (expect* first?.lane).is("subagent");

    // Second call: main agent trigger (not "Sub-agent announce step." anymore)
    const second = agentCalls[1]?.params as { sessionKey?: string; message?: string } | undefined;
    (expect* second?.sessionKey).is("agent:main:main");
    (expect* second?.message).contains("subagent task");

    // No direct send to external channel (main agent handles delivery)
    const sendCalls = ctx.calls.filter((c) => c.method === "send");
    (expect* sendCalls.length).is(0);
    (expect* child.sessionKey?.startsWith("agent:main:subagent:")).is(true);
  });

  (deftest "sessions_spawn runs cleanup via lifecycle events", async () => {
    let deletedKey: string | undefined;
    const ctx = setupSessionsSpawnGatewayMock({
      ...buildDiscordCleanupHooks((key) => {
        deletedKey = key;
      }),
    });

    const tool = await getDiscordGroupSpawnTool();
    await executeSpawnAndExpectAccepted({
      tool,
      callId: "call1",
      cleanup: "delete",
    });

    const child = ctx.getChild();
    if (!child.runId) {
      error("missing child runId");
    }
    await emitLifecycleEndAndFlush({
      runId: child.runId,
      startedAt: 1234,
      endedAt: 2345,
    });

    await waitFor(
      () => ctx.calls.filter((call) => call.method === "agent").length >= 2 && Boolean(deletedKey),
    );

    const childWait = ctx.waitCalls.find((call) => call.runId === child.runId);
    (expect* childWait?.timeoutMs).is(1000);

    const agentCalls = ctx.calls.filter((call) => call.method === "agent");
    (expect* agentCalls).has-length(2);

    const first = agentCalls[0]?.params as
      | {
          lane?: string;
          deliver?: boolean;
          sessionKey?: string;
          channel?: string;
        }
      | undefined;
    (expect* first?.lane).is("subagent");
    (expect* first?.deliver).is(false);
    (expect* first?.channel).is("discord");
    (expect* first?.sessionKey?.startsWith("agent:main:subagent:")).is(true);
    (expect* child.sessionKey?.startsWith("agent:main:subagent:")).is(true);

    const second = agentCalls[1]?.params as
      | {
          sessionKey?: string;
          message?: string;
          deliver?: boolean;
        }
      | undefined;
    (expect* second?.sessionKey).is("agent:main:discord:group:req");
    (expect* second?.deliver).is(false);
    (expect* second?.message).contains("subagent task");

    const sendCalls = ctx.calls.filter((c) => c.method === "send");
    (expect* sendCalls.length).is(0);

    (expect* deletedKey?.startsWith("agent:main:subagent:")).is(true);
  });

  (deftest "sessions_spawn deletes session when cleanup=delete via agent.wait", async () => {
    let deletedKey: string | undefined;
    const ctx = setupSessionsSpawnGatewayMock({
      includeChatHistory: true,
      ...buildDiscordCleanupHooks((key) => {
        deletedKey = key;
      }),
      agentWaitResult: { status: "ok", startedAt: 3000, endedAt: 4000 },
    });

    const tool = await getDiscordGroupSpawnTool();
    await executeSpawnAndExpectAccepted({
      tool,
      callId: "call1b",
      cleanup: "delete",
    });

    const child = ctx.getChild();
    if (!child.runId) {
      error("missing child runId");
    }
    await waitFor(
      () =>
        ctx.waitCalls.some((call) => call.runId === child.runId) &&
        ctx.calls.filter((call) => call.method === "agent").length >= 2 &&
        Boolean(deletedKey),
    );

    const childWait = ctx.waitCalls.find((call) => call.runId === child.runId);
    (expect* childWait?.timeoutMs).is(1000);
    (expect* child.sessionKey?.startsWith("agent:main:subagent:")).is(true);

    // Two agent calls: subagent spawn + main agent trigger
    const agentCalls = ctx.calls.filter((call) => call.method === "agent");
    (expect* agentCalls).has-length(2);

    // First call: subagent spawn
    const first = agentCalls[0]?.params as { lane?: string } | undefined;
    (expect* first?.lane).is("subagent");

    // Second call: main agent trigger
    const second = agentCalls[1]?.params as { sessionKey?: string; deliver?: boolean } | undefined;
    (expect* second?.sessionKey).is("agent:main:discord:group:req");
    (expect* second?.deliver).is(false);

    // No direct send to external channel (main agent handles delivery)
    const sendCalls = ctx.calls.filter((c) => c.method === "send");
    (expect* sendCalls.length).is(0);

    // Session should be deleted
    (expect* deletedKey?.startsWith("agent:main:subagent:")).is(true);
  });

  (deftest "sessions_spawn reports timed out when agent.wait returns timeout", async () => {
    const ctx = setupSessionsSpawnGatewayMock({
      includeChatHistory: true,
      chatHistoryText: "still working",
      agentWaitResult: { status: "timeout", startedAt: 6000, endedAt: 7000 },
    });

    const tool = await getDiscordGroupSpawnTool();
    await executeSpawnAndExpectAccepted({
      tool,
      callId: "call-timeout",
      cleanup: "keep",
    });

    await waitFor(() => ctx.calls.filter((call) => call.method === "agent").length >= 2);

    const mainAgentCall = ctx.calls
      .filter((call) => call.method === "agent")
      .find((call) => {
        const params = call.params as { lane?: string } | undefined;
        return params?.lane !== "subagent";
      });
    const mainMessage = (mainAgentCall?.params as { message?: string } | undefined)?.message ?? "";

    (expect* mainMessage).contains("timed out");
    (expect* mainMessage).not.contains("completed successfully");
  });

  (deftest "sessions_spawn announces with requester accountId", async () => {
    const ctx = setupSessionsSpawnGatewayMock({});

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
      agentAccountId: "kev",
    });

    await executeSpawnAndExpectAccepted({
      tool,
      callId: "call-announce-account",
      cleanup: "keep",
    });

    const child = ctx.getChild();
    if (!child.runId) {
      error("missing child runId");
    }
    await emitLifecycleEndAndFlush({
      runId: child.runId,
      startedAt: 1000,
      endedAt: 2000,
    });

    const agentCalls = ctx.calls.filter((call) => call.method === "agent");
    (expect* agentCalls).has-length(2);
    const announceParams = agentCalls[1]?.params as
      | { accountId?: string; channel?: string; deliver?: boolean }
      | undefined;
    (expect* announceParams?.deliver).is(false);
    (expect* announceParams?.channel).toBeUndefined();
    (expect* announceParams?.accountId).toBeUndefined();
  });
});
