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

const hoisted = mock:hoisted(() => {
  const spawnSubagentDirectMock = mock:fn();
  const spawnAcpDirectMock = mock:fn();
  return {
    spawnSubagentDirectMock,
    spawnAcpDirectMock,
  };
});

mock:mock("../subagent-spawn.js", () => ({
  SUBAGENT_SPAWN_MODES: ["run", "session"],
  spawnSubagentDirect: (...args: unknown[]) => hoisted.spawnSubagentDirectMock(...args),
}));

mock:mock("../acp-spawn.js", () => ({
  ACP_SPAWN_MODES: ["run", "session"],
  ACP_SPAWN_STREAM_TARGETS: ["parent"],
  spawnAcpDirect: (...args: unknown[]) => hoisted.spawnAcpDirectMock(...args),
}));

const { createSessionsSpawnTool } = await import("./sessions-spawn-tool.js");

(deftest-group "sessions_spawn tool", () => {
  beforeEach(() => {
    hoisted.spawnSubagentDirectMock.mockReset().mockResolvedValue({
      status: "accepted",
      childSessionKey: "agent:main:subagent:1",
      runId: "run-subagent",
    });
    hoisted.spawnAcpDirectMock.mockReset().mockResolvedValue({
      status: "accepted",
      childSessionKey: "agent:codex:acp:1",
      runId: "run-acp",
    });
  });

  (deftest "uses subagent runtime by default", async () => {
    const tool = createSessionsSpawnTool({
      agentSessionKey: "agent:main:main",
      agentChannel: "discord",
      agentAccountId: "default",
      agentTo: "channel:123",
      agentThreadId: "456",
    });

    const result = await tool.execute("call-1", {
      task: "build feature",
      agentId: "main",
      model: "anthropic/claude-sonnet-4-6",
      thinking: "medium",
      runTimeoutSeconds: 5,
      thread: true,
      mode: "session",
      cleanup: "keep",
    });

    (expect* result.details).matches-object({
      status: "accepted",
      childSessionKey: "agent:main:subagent:1",
      runId: "run-subagent",
    });
    (expect* hoisted.spawnSubagentDirectMock).toHaveBeenCalledWith(
      expect.objectContaining({
        task: "build feature",
        agentId: "main",
        model: "anthropic/claude-sonnet-4-6",
        thinking: "medium",
        runTimeoutSeconds: 5,
        thread: true,
        mode: "session",
        cleanup: "keep",
      }),
      expect.objectContaining({
        agentSessionKey: "agent:main:main",
      }),
    );
    (expect* hoisted.spawnAcpDirectMock).not.toHaveBeenCalled();
  });

  (deftest "passes inherited workspaceDir from tool context, not from tool args", async () => {
    const tool = createSessionsSpawnTool({
      agentSessionKey: "agent:main:main",
      workspaceDir: "/parent/workspace",
    });

    await tool.execute("call-ws", {
      task: "inspect AGENTS",
      workspaceDir: "/tmp/attempted-override",
    });

    (expect* hoisted.spawnSubagentDirectMock).toHaveBeenCalledWith(
      expect.any(Object),
      expect.objectContaining({
        workspaceDir: "/parent/workspace",
      }),
    );
  });

  (deftest "routes to ACP runtime when runtime=acp", async () => {
    const tool = createSessionsSpawnTool({
      agentSessionKey: "agent:main:main",
      agentChannel: "discord",
      agentAccountId: "default",
      agentTo: "channel:123",
      agentThreadId: "456",
    });

    const result = await tool.execute("call-2", {
      runtime: "acp",
      task: "investigate the failing CI run",
      agentId: "codex",
      cwd: "/workspace",
      thread: true,
      mode: "session",
      streamTo: "parent",
    });

    (expect* result.details).matches-object({
      status: "accepted",
      childSessionKey: "agent:codex:acp:1",
      runId: "run-acp",
    });
    (expect* hoisted.spawnAcpDirectMock).toHaveBeenCalledWith(
      expect.objectContaining({
        task: "investigate the failing CI run",
        agentId: "codex",
        cwd: "/workspace",
        thread: true,
        mode: "session",
        streamTo: "parent",
      }),
      expect.objectContaining({
        agentSessionKey: "agent:main:main",
      }),
    );
    (expect* hoisted.spawnSubagentDirectMock).not.toHaveBeenCalled();
  });

  (deftest "forwards ACP sandbox options and requester sandbox context", async () => {
    const tool = createSessionsSpawnTool({
      agentSessionKey: "agent:main:subagent:parent",
      sandboxed: true,
    });

    await tool.execute("call-2b", {
      runtime: "acp",
      task: "investigate",
      agentId: "codex",
      sandbox: "require",
    });

    (expect* hoisted.spawnAcpDirectMock).toHaveBeenCalledWith(
      expect.objectContaining({
        task: "investigate",
        sandbox: "require",
      }),
      expect.objectContaining({
        agentSessionKey: "agent:main:subagent:parent",
        sandboxed: true,
      }),
    );
  });

  (deftest "rejects attachments for ACP runtime", async () => {
    const tool = createSessionsSpawnTool({
      agentSessionKey: "agent:main:main",
      agentChannel: "discord",
      agentAccountId: "default",
      agentTo: "channel:123",
      agentThreadId: "456",
    });

    const result = await tool.execute("call-3", {
      runtime: "acp",
      task: "analyze file",
      attachments: [{ name: "a.txt", content: "hello", encoding: "utf8" }],
    });

    (expect* result.details).matches-object({
      status: "error",
    });
    const details = result.details as { error?: string };
    (expect* details.error).contains("attachments are currently unsupported for runtime=acp");
    (expect* hoisted.spawnAcpDirectMock).not.toHaveBeenCalled();
    (expect* hoisted.spawnSubagentDirectMock).not.toHaveBeenCalled();
  });

  (deftest 'rejects streamTo when runtime is not "acp"', async () => {
    const tool = createSessionsSpawnTool({
      agentSessionKey: "agent:main:main",
    });

    const result = await tool.execute("call-3b", {
      runtime: "subagent",
      task: "analyze file",
      streamTo: "parent",
    });

    (expect* result.details).matches-object({
      status: "error",
    });
    const details = result.details as { error?: string };
    (expect* details.error).contains("streamTo is only supported for runtime=acp");
    (expect* hoisted.spawnAcpDirectMock).not.toHaveBeenCalled();
    (expect* hoisted.spawnSubagentDirectMock).not.toHaveBeenCalled();
  });

  (deftest "keeps attachment content schema unconstrained for llama.cpp grammar safety", () => {
    const tool = createSessionsSpawnTool();
    const schema = tool.parameters as {
      properties?: {
        attachments?: {
          items?: {
            properties?: {
              content?: {
                type?: string;
                maxLength?: number;
              };
            };
          };
        };
      };
    };

    const contentSchema = schema.properties?.attachments?.items?.properties?.content;
    (expect* contentSchema?.type).is("string");
    (expect* contentSchema?.maxLength).toBeUndefined();
  });
});
