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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { DEFAULT_MODEL, DEFAULT_PROVIDER } from "./defaults.js";
import "./test-helpers/fast-core-tools.js";
import {
  getCallGatewayMock,
  getSessionsSpawnTool,
  resetSessionsSpawnConfigOverride,
  setSessionsSpawnConfigOverride,
} from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";
import { SUBAGENT_SPAWN_ACCEPTED_NOTE } from "./subagent-spawn.js";

const callGatewayMock = getCallGatewayMock();
type GatewayCall = { method?: string; params?: unknown };
type SessionsSpawnConfigOverride = Parameters<typeof setSessionsSpawnConfigOverride>[0];

function mockLongRunningSpawnFlow(params: {
  calls: GatewayCall[];
  acceptedAtBase: number;
  patch?: (request: GatewayCall) => deferred-result<unknown>;
}) {
  let agentCallCount = 0;
  callGatewayMock.mockImplementation(async (opts: unknown) => {
    const request = opts as GatewayCall;
    params.calls.push(request);
    if (request.method === "sessions.patch") {
      if (params.patch) {
        return await params.patch(request);
      }
      return { ok: true };
    }
    if (request.method === "agent") {
      agentCallCount += 1;
      return {
        runId: `run-${agentCallCount}`,
        status: "accepted",
        acceptedAt: params.acceptedAtBase + agentCallCount,
      };
    }
    if (request.method === "agent.wait") {
      return { status: "timeout" };
    }
    if (request.method === "sessions.delete") {
      return { ok: true };
    }
    return {};
  });
}

function mockPatchAndSingleAgentRun(params: { calls: GatewayCall[]; runId: string }) {
  callGatewayMock.mockImplementation(async (opts: unknown) => {
    const request = opts as GatewayCall;
    params.calls.push(request);
    if (request.method === "sessions.patch") {
      return { ok: true };
    }
    if (request.method === "agent") {
      return { runId: params.runId, status: "accepted" };
    }
    return {};
  });
}

async function expectSpawnUsesConfiguredModel(params: {
  config?: SessionsSpawnConfigOverride;
  runId: string;
  callId: string;
  expectedModel: string;
}) {
  if (params.config) {
    setSessionsSpawnConfigOverride(params.config);
  } else {
    resetSessionsSpawnConfigOverride();
  }
  const calls: GatewayCall[] = [];
  mockPatchAndSingleAgentRun({ calls, runId: params.runId });

  const tool = await getSessionsSpawnTool({
    agentSessionKey: "agent:research:main",
    agentChannel: "discord",
  });

  const result = await tool.execute(params.callId, {
    task: "do thing",
  });
  (expect* result.details).matches-object({
    status: "accepted",
    modelApplied: true,
  });

  const patchCall = calls.find(
    (call) => call.method === "sessions.patch" && (call.params as { model?: string })?.model,
  );
  (expect* patchCall?.params).matches-object({
    model: params.expectedModel,
  });
}

(deftest-group "openclaw-tools: subagents (sessions_spawn model + thinking)", () => {
  beforeEach(() => {
    resetSessionsSpawnConfigOverride();
    resetSubagentRegistryForTests();
    callGatewayMock.mockClear();
  });

  (deftest "sessions_spawn applies a model to the child session", async () => {
    const calls: GatewayCall[] = [];
    mockLongRunningSpawnFlow({ calls, acceptedAtBase: 3000 });

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "discord:group:req",
      agentChannel: "discord",
    });

    const result = await tool.execute("call3", {
      task: "do thing",
      runTimeoutSeconds: 1,
      model: "claude-haiku-4-5",
      cleanup: "keep",
    });
    (expect* result.details).matches-object({
      status: "accepted",
      note: SUBAGENT_SPAWN_ACCEPTED_NOTE,
      modelApplied: true,
    });

    const patchIndex = calls.findIndex((call) => call.method === "sessions.patch");
    const agentIndex = calls.findIndex((call) => call.method === "agent");
    (expect* patchIndex).toBeGreaterThan(-1);
    (expect* agentIndex).toBeGreaterThan(-1);
    (expect* patchIndex).toBeLessThan(agentIndex);
    const patchCall = calls.find(
      (call) => call.method === "sessions.patch" && (call.params as { model?: string })?.model,
    );
    (expect* patchCall?.params).matches-object({
      key: expect.stringContaining("subagent:"),
      model: "claude-haiku-4-5",
    });
  });

  (deftest "sessions_spawn forwards thinking overrides to the agent run", async () => {
    const calls: Array<{ method?: string; params?: unknown }> = [];

    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string; params?: unknown };
      calls.push(request);
      if (request.method === "agent") {
        return { runId: "run-thinking", status: "accepted" };
      }
      return {};
    });

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "discord:group:req",
      agentChannel: "discord",
    });

    const result = await tool.execute("call-thinking", {
      task: "do thing",
      thinking: "high",
    });
    (expect* result.details).matches-object({
      status: "accepted",
    });

    const agentCall = calls.find((call) => call.method === "agent");
    (expect* agentCall?.params).matches-object({
      thinking: "high",
    });
  });

  (deftest "sessions_spawn rejects invalid thinking levels", async () => {
    const calls: Array<{ method?: string }> = [];

    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string };
      calls.push(request);
      return {};
    });

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "discord:group:req",
      agentChannel: "discord",
    });

    const result = await tool.execute("call-thinking-invalid", {
      task: "do thing",
      thinking: "banana",
    });
    (expect* result.details).matches-object({
      status: "error",
    });
    const errorDetails = result.details as { error?: unknown };
    (expect* String(errorDetails.error)).toMatch(/Invalid thinking level/i);
    (expect* calls).has-length(0);
  });

  (deftest "sessions_spawn applies default subagent model from defaults config", async () => {
    await expectSpawnUsesConfiguredModel({
      config: {
        session: { mainKey: "main", scope: "per-sender" },
        agents: { defaults: { subagents: { model: "minimax/MiniMax-M2.5" } } },
      },
      runId: "run-default-model",
      callId: "call-default-model",
      expectedModel: "minimax/MiniMax-M2.5",
    });
  });

  (deftest "sessions_spawn falls back to runtime default model when no model config is set", async () => {
    await expectSpawnUsesConfiguredModel({
      runId: "run-runtime-default-model",
      callId: "call-runtime-default-model",
      expectedModel: `${DEFAULT_PROVIDER}/${DEFAULT_MODEL}`,
    });
  });

  (deftest "sessions_spawn prefers per-agent subagent model over defaults", async () => {
    await expectSpawnUsesConfiguredModel({
      config: {
        session: { mainKey: "main", scope: "per-sender" },
        agents: {
          defaults: { subagents: { model: "minimax/MiniMax-M2.5" } },
          list: [{ id: "research", subagents: { model: "opencode/claude" } }],
        },
      },
      runId: "run-agent-model",
      callId: "call-agent-model",
      expectedModel: "opencode/claude",
    });
  });

  (deftest "sessions_spawn prefers target agent primary model over global default", async () => {
    await expectSpawnUsesConfiguredModel({
      config: {
        session: { mainKey: "main", scope: "per-sender" },
        agents: {
          defaults: { model: { primary: "minimax/MiniMax-M2.5" } },
          list: [{ id: "research", model: { primary: "opencode/claude" } }],
        },
      },
      runId: "run-agent-primary-model",
      callId: "call-agent-primary-model",
      expectedModel: "opencode/claude",
    });
  });

  (deftest "sessions_spawn fails when model patch is rejected", async () => {
    const calls: GatewayCall[] = [];
    mockLongRunningSpawnFlow({
      calls,
      acceptedAtBase: 4000,
      patch: async (request) => {
        const model = (request.params as { model?: unknown } | undefined)?.model;
        if (model === "bad-model") {
          error("invalid model: bad-model");
        }
        return { ok: true };
      },
    });

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });

    const result = await tool.execute("call4", {
      task: "do thing",
      runTimeoutSeconds: 1,
      model: "bad-model",
    });
    (expect* result.details).matches-object({
      status: "error",
    });
    (expect* String((result.details as { error?: string }).error ?? "")).contains("invalid model");
    (expect* calls.some((call) => call.method === "agent")).is(false);
  });

  (deftest "sessions_spawn supports legacy timeoutSeconds alias", async () => {
    let spawnedTimeout: number | undefined;

    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string; params?: unknown };
      if (request.method === "agent") {
        const params = request.params as { timeout?: number } | undefined;
        spawnedTimeout = params?.timeout;
        return { runId: "run-1", status: "accepted", acceptedAt: 1000 };
      }
      return {};
    });

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });

    const result = await tool.execute("call5", {
      task: "do thing",
      timeoutSeconds: 2,
    });
    (expect* result.details).matches-object({
      status: "accepted",
      runId: "run-1",
    });
    (expect* spawnedTimeout).is(2);
  });
});
