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
import "./test-helpers/fast-core-tools.js";
import {
  getCallGatewayMock,
  getSessionsSpawnTool,
  resetSessionsSpawnConfigOverride,
  setSessionsSpawnConfigOverride,
} from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";

const callGatewayMock = getCallGatewayMock();

(deftest-group "openclaw-tools: subagents (sessions_spawn allowlist)", () => {
  function setAllowAgents(allowAgents: string[]) {
    setSessionsSpawnConfigOverride({
      session: {
        mainKey: "main",
        scope: "per-sender",
      },
      agents: {
        list: [
          {
            id: "main",
            subagents: {
              allowAgents,
            },
          },
        ],
      },
    });
  }

  function mockAcceptedSpawn(acceptedAt: number) {
    let childSessionKey: string | undefined;
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const request = opts as { method?: string; params?: unknown };
      if (request.method === "agent") {
        const params = request.params as { sessionKey?: string } | undefined;
        childSessionKey = params?.sessionKey;
        return { runId: "run-1", status: "accepted", acceptedAt };
      }
      if (request.method === "agent.wait") {
        return { status: "timeout" };
      }
      return {};
    });
    return () => childSessionKey;
  }

  async function executeSpawn(callId: string, agentId: string, sandbox?: "inherit" | "require") {
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });
    return tool.execute(callId, { task: "do thing", agentId, sandbox });
  }

  function setResearchUnsandboxedConfig(params?: { includeSandboxedDefault?: boolean }) {
    setSessionsSpawnConfigOverride({
      session: {
        mainKey: "main",
        scope: "per-sender",
      },
      agents: {
        ...(params?.includeSandboxedDefault
          ? {
              defaults: {
                sandbox: {
                  mode: "all",
                },
              },
            }
          : {}),
        list: [
          {
            id: "main",
            subagents: {
              allowAgents: ["research"],
            },
          },
          {
            id: "research",
            sandbox: {
              mode: "off",
            },
          },
        ],
      },
    });
  }

  async function expectAllowedSpawn(params: {
    allowAgents: string[];
    agentId: string;
    callId: string;
    acceptedAt: number;
  }) {
    setAllowAgents(params.allowAgents);
    const getChildSessionKey = mockAcceptedSpawn(params.acceptedAt);

    const result = await executeSpawn(params.callId, params.agentId);

    (expect* result.details).matches-object({
      status: "accepted",
      runId: "run-1",
    });
    (expect* getChildSessionKey()?.startsWith(`agent:${params.agentId}:subagent:`)).is(true);
  }

  async function expectInvalidAgentId(callId: string, agentId: string) {
    setSessionsSpawnConfigOverride({
      session: { mainKey: "main", scope: "per-sender" },
      agents: {
        list: [{ id: "main", subagents: { allowAgents: ["*"] } }],
      },
    });
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });
    const result = await tool.execute(callId, { task: "do thing", agentId });
    const details = result.details as { status?: string; error?: string };
    (expect* details.status).is("error");
    (expect* details.error).contains("Invalid agentId");
    (expect* callGatewayMock).not.toHaveBeenCalled();
  }

  beforeEach(() => {
    resetSessionsSpawnConfigOverride();
    resetSubagentRegistryForTests();
    callGatewayMock.mockClear();
  });

  (deftest "sessions_spawn only allows same-agent by default", async () => {
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });

    const result = await tool.execute("call6", {
      task: "do thing",
      agentId: "beta",
    });
    (expect* result.details).matches-object({
      status: "forbidden",
    });
    (expect* callGatewayMock).not.toHaveBeenCalled();
  });

  (deftest "sessions_spawn forbids cross-agent spawning when not allowed", async () => {
    setSessionsSpawnConfigOverride({
      session: {
        mainKey: "main",
        scope: "per-sender",
      },
      agents: {
        list: [
          {
            id: "main",
            subagents: {
              allowAgents: ["alpha"],
            },
          },
        ],
      },
    });

    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });

    const result = await tool.execute("call9", {
      task: "do thing",
      agentId: "beta",
    });
    (expect* result.details).matches-object({
      status: "forbidden",
    });
    (expect* callGatewayMock).not.toHaveBeenCalled();
  });

  (deftest "sessions_spawn allows cross-agent spawning when configured", async () => {
    await expectAllowedSpawn({
      allowAgents: ["beta"],
      agentId: "beta",
      callId: "call7",
      acceptedAt: 5000,
    });
  });

  (deftest "sessions_spawn allows any agent when allowlist is *", async () => {
    await expectAllowedSpawn({
      allowAgents: ["*"],
      agentId: "beta",
      callId: "call8",
      acceptedAt: 5100,
    });
  });

  (deftest "sessions_spawn normalizes allowlisted agent ids", async () => {
    await expectAllowedSpawn({
      allowAgents: ["Research"],
      agentId: "research",
      callId: "call10",
      acceptedAt: 5200,
    });
  });

  (deftest "forbids sandboxed cross-agent spawns that would unsandbox the child", async () => {
    setResearchUnsandboxedConfig({ includeSandboxedDefault: true });

    const result = await executeSpawn("call11", "research");
    const details = result.details as { status?: string; error?: string };

    (expect* details.status).is("forbidden");
    (expect* details.error).contains("Sandboxed sessions cannot spawn unsandboxed subagents.");
    (expect* callGatewayMock).not.toHaveBeenCalled();
  });

  (deftest 'forbids sandbox="require" when target runtime is unsandboxed', async () => {
    setResearchUnsandboxedConfig();

    const result = await executeSpawn("call12", "research", "require");
    const details = result.details as { status?: string; error?: string };

    (expect* details.status).is("forbidden");
    (expect* details.error).contains('sandbox="require"');
    (expect* callGatewayMock).not.toHaveBeenCalled();
  });
  // ---------------------------------------------------------------------------
  // agentId format validation (#31311)
  // ---------------------------------------------------------------------------

  (deftest "rejects error-message-like strings as agentId (#31311)", async () => {
    setSessionsSpawnConfigOverride({
      session: { mainKey: "main", scope: "per-sender" },
      agents: {
        list: [{ id: "main", subagents: { allowAgents: ["*"] } }, { id: "research" }],
      },
    });
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "whatsapp",
    });
    const result = await tool.execute("call-err-msg", {
      task: "do thing",
      agentId: "Agent not found: xyz",
    });
    const details = result.details as { status?: string; error?: string };
    (expect* details.status).is("error");
    (expect* details.error).contains("Invalid agentId");
    (expect* details.error).contains("agents_list");
    (expect* callGatewayMock).not.toHaveBeenCalled();
  });

  (deftest "rejects agentId containing path separators (#31311)", async () => {
    await expectInvalidAgentId("call-path", "../../../etc/passwd");
  });

  (deftest "rejects agentId exceeding 64 characters (#31311)", async () => {
    await expectInvalidAgentId("call-long", "a".repeat(65));
  });

  (deftest "accepts well-formed agentId with hyphens and underscores (#31311)", async () => {
    setSessionsSpawnConfigOverride({
      session: { mainKey: "main", scope: "per-sender" },
      agents: {
        list: [{ id: "main", subagents: { allowAgents: ["*"] } }, { id: "my-research_agent01" }],
      },
    });
    mockAcceptedSpawn(1000);
    const result = await executeSpawn("call-valid", "my-research_agent01");
    const details = result.details as { status?: string };
    (expect* details.status).is("accepted");
  });

  (deftest "allows allowlisted-but-unconfigured agentId (#31311)", async () => {
    setSessionsSpawnConfigOverride({
      session: { mainKey: "main", scope: "per-sender" },
      agents: {
        list: [
          { id: "main", subagents: { allowAgents: ["research"] } },
          // "research" is NOT in agents.list — only in allowAgents
        ],
      },
    });
    mockAcceptedSpawn(1000);
    const result = await executeSpawn("call-unconfigured", "research");
    const details = result.details as { status?: string };
    // Must pass: "research" is in allowAgents even though not in agents.list
    (expect* details.status).is("accepted");
  });
});
