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
import { resetSubagentRegistryForTests } from "../../agents/subagent-registry.js";
import type { SpawnSubagentResult } from "../../agents/subagent-spawn.js";
import type { OpenClawConfig } from "../../config/config.js";
import { installSubagentsCommandCoreMocks } from "./commands-subagents.test-mocks.js";

const hoisted = mock:hoisted(() => {
  const spawnSubagentDirectMock = mock:fn();
  const callGatewayMock = mock:fn();
  return { spawnSubagentDirectMock, callGatewayMock };
});

mock:mock("../../agents/subagent-spawn.js", () => ({
  spawnSubagentDirect: (...args: unknown[]) => hoisted.spawnSubagentDirectMock(...args),
  SUBAGENT_SPAWN_MODES: ["run", "session"],
}));

mock:mock("../../gateway/call.js", () => ({
  callGateway: (opts: unknown) => hoisted.callGatewayMock(opts),
}));

installSubagentsCommandCoreMocks();

// Dynamic import to ensure mocks are installed first.
const { handleSubagentsCommand } = await import("./commands-subagents.js");
const { buildCommandTestParams } = await import("./commands-spawn.test-harness.js");

const { spawnSubagentDirectMock } = hoisted;

function acceptedResult(overrides?: Partial<SpawnSubagentResult>): SpawnSubagentResult {
  return {
    status: "accepted",
    childSessionKey: "agent:beta:subagent:test-uuid",
    runId: "run-spawn-1",
    ...overrides,
  };
}

function forbiddenResult(error: string): SpawnSubagentResult {
  return {
    status: "forbidden",
    error,
  };
}

const baseCfg = {
  session: { mainKey: "main", scope: "per-sender" },
} satisfies OpenClawConfig;

(deftest-group "/subagents spawn command", () => {
  beforeEach(() => {
    resetSubagentRegistryForTests();
    spawnSubagentDirectMock.mockClear();
    hoisted.callGatewayMock.mockClear();
  });

  async function runSpawnWithFlag(
    flagSegment: string,
    result: SpawnSubagentResult = acceptedResult(),
  ) {
    spawnSubagentDirectMock.mockResolvedValue(result);
    const params = buildCommandTestParams(
      `/subagents spawn beta do the thing ${flagSegment}`,
      baseCfg,
    );
    const commandResult = await handleSubagentsCommand(params, true);
    (expect* commandResult).not.toBeNull();
    (expect* commandResult?.reply?.text).contains("Spawned subagent beta");
    const [spawnParams] = spawnSubagentDirectMock.mock.calls[0];
    return spawnParams as { model?: string; thinking?: string; task?: string };
  }

  async function runSuccessfulSpawn(params?: {
    commandText?: string;
    context?: Record<string, unknown>;
    mutateParams?: (commandParams: ReturnType<typeof buildCommandTestParams>) => void;
  }) {
    spawnSubagentDirectMock.mockResolvedValue(acceptedResult());
    const commandParams = buildCommandTestParams(
      params?.commandText ?? "/subagents spawn beta do the thing",
      baseCfg,
      params?.context,
    );
    params?.mutateParams?.(commandParams);
    const result = await handleSubagentsCommand(commandParams, true);
    (expect* result).not.toBeNull();
    (expect* result?.reply?.text).contains("Spawned subagent beta");
    const [spawnParams, spawnCtx] = spawnSubagentDirectMock.mock.calls[0];
    return { spawnParams, spawnCtx, commandParams, commandResult: result };
  }

  (deftest "shows usage when agentId is missing", async () => {
    const params = buildCommandTestParams("/subagents spawn", baseCfg);
    const result = await handleSubagentsCommand(params, true);
    (expect* result).not.toBeNull();
    (expect* result?.reply?.text).contains("Usage:");
    (expect* result?.reply?.text).contains("/subagents spawn");
    (expect* spawnSubagentDirectMock).not.toHaveBeenCalled();
  });

  (deftest "shows usage when task is missing", async () => {
    const params = buildCommandTestParams("/subagents spawn beta", baseCfg);
    const result = await handleSubagentsCommand(params, true);
    (expect* result).not.toBeNull();
    (expect* result?.reply?.text).contains("Usage:");
    (expect* spawnSubagentDirectMock).not.toHaveBeenCalled();
  });

  (deftest "spawns subagent and confirms reply text and child session key", async () => {
    const { spawnParams, spawnCtx, commandResult } = await runSuccessfulSpawn();
    (expect* commandResult?.reply?.text).contains("agent:beta:subagent:test-uuid");
    (expect* commandResult?.reply?.text).contains("run-spaw");
    (expect* spawnSubagentDirectMock).toHaveBeenCalledOnce();
    (expect* spawnParams.task).is("do the thing");
    (expect* spawnParams.agentId).is("beta");
    (expect* spawnParams.mode).is("run");
    (expect* spawnParams.cleanup).is("keep");
    (expect* spawnParams.expectsCompletionMessage).is(true);
    (expect* spawnCtx.agentSessionKey).toBeDefined();
  });

  (deftest "spawns with --model flag and passes model to spawnSubagentDirect", async () => {
    const spawnParams = await runSpawnWithFlag(
      "--model openai/gpt-4o",
      acceptedResult({ modelApplied: true }),
    );
    (expect* spawnParams.model).is("openai/gpt-4o");
    (expect* spawnParams.task).is("do the thing");
  });

  (deftest "spawns with --thinking flag and passes thinking to spawnSubagentDirect", async () => {
    const spawnParams = await runSpawnWithFlag("--thinking high");
    (expect* spawnParams.thinking).is("high");
    (expect* spawnParams.task).is("do the thing");
  });

  (deftest "passes group context from session entry to spawnSubagentDirect", async () => {
    const { spawnCtx } = await runSuccessfulSpawn({
      mutateParams: (commandParams) => {
        commandParams.sessionEntry = {
          sessionId: "session-main",
          updatedAt: Date.now(),
          groupId: "group-1",
          groupChannel: "#group-channel",
          space: "workspace-1",
        };
      },
    });
    (expect* spawnCtx).matches-object({
      agentGroupId: "group-1",
      agentGroupChannel: "#group-channel",
      agentGroupSpace: "workspace-1",
    });
  });

  (deftest "prefers CommandTargetSessionKey for native /subagents spawn", async () => {
    const { spawnCtx } = await runSuccessfulSpawn({
      context: {
        CommandSource: "native",
        CommandTargetSessionKey: "agent:main:main",
        OriginatingChannel: "discord",
        OriginatingTo: "channel:12345",
      },
      mutateParams: (commandParams) => {
        commandParams.sessionKey = "agent:main:slack:slash:u1";
      },
    });
    (expect* spawnCtx.agentSessionKey).is("agent:main:main");
    (expect* spawnCtx.agentChannel).is("discord");
    (expect* spawnCtx.agentTo).is("channel:12345");
  });

  (deftest "falls back to OriginatingTo for agentTo when command.to is missing", async () => {
    const { spawnCtx } = await runSuccessfulSpawn({
      context: {
        OriginatingTo: "channel:manual",
        To: "channel:fallback-from-to",
      },
      mutateParams: (commandParams) => {
        commandParams.command.to = undefined;
      },
    });
    (expect* spawnCtx).matches-object({ agentTo: "channel:manual" });
  });
  (deftest "returns forbidden for unauthorized cross-agent spawn", async () => {
    spawnSubagentDirectMock.mockResolvedValue(
      forbiddenResult("agentId is not allowed for sessions_spawn (allowed: alpha)"),
    );
    const params = buildCommandTestParams("/subagents spawn beta do the thing", baseCfg);
    const result = await handleSubagentsCommand(params, true);
    (expect* result).not.toBeNull();
    (expect* result?.reply?.text).contains("Spawn failed");
    (expect* result?.reply?.text).contains("not allowed");
  });

  (deftest "allows cross-agent spawn when in allowlist", async () => {
    await runSuccessfulSpawn();
    (expect* spawnSubagentDirectMock).toHaveBeenCalledOnce();
  });

  (deftest "ignores unauthorized sender (silent, no reply)", async () => {
    const params = buildCommandTestParams("/subagents spawn beta do the thing", baseCfg, {
      CommandAuthorized: false,
    });
    params.command.isAuthorizedSender = false;
    const result = await handleSubagentsCommand(params, true);
    (expect* result).not.toBeNull();
    (expect* result?.reply).toBeUndefined();
    (expect* result?.shouldContinue).is(false);
    (expect* spawnSubagentDirectMock).not.toHaveBeenCalled();
  });

  (deftest "returns null when text commands disabled", async () => {
    const params = buildCommandTestParams("/subagents spawn beta do the thing", baseCfg);
    const result = await handleSubagentsCommand(params, false);
    (expect* result).toBeNull();
    (expect* spawnSubagentDirectMock).not.toHaveBeenCalled();
  });
});
