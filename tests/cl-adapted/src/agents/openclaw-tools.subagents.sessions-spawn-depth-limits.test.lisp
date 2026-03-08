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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { addSubagentRunForTests, resetSubagentRegistryForTests } from "./subagent-registry.js";
import { createPerSenderSessionConfig } from "./test-helpers/session-config.js";
import { createSessionsSpawnTool } from "./tools/sessions-spawn-tool.js";

const callGatewayMock = mock:fn();

mock:mock("../gateway/call.js", () => ({
  callGateway: (opts: unknown) => callGatewayMock(opts),
}));

let storeTemplatePath = "";
let configOverride: Record<string, unknown> = {
  session: createPerSenderSessionConfig(),
};

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => configOverride,
  };
});

function writeStore(agentId: string, store: Record<string, unknown>) {
  const storePath = storeTemplatePath.replaceAll("{agentId}", agentId);
  fs.mkdirSync(path.dirname(storePath), { recursive: true });
  fs.writeFileSync(storePath, JSON.stringify(store, null, 2), "utf-8");
}

function setSubagentLimits(subagents: Record<string, unknown>) {
  configOverride = {
    session: createPerSenderSessionConfig({ store: storeTemplatePath }),
    agents: {
      defaults: {
        subagents,
      },
    },
  };
}

function seedDepthTwoAncestryStore(params?: { sessionIds?: boolean }) {
  const depth1 = "agent:main:subagent:depth-1";
  const callerKey = "agent:main:subagent:depth-2";
  writeStore("main", {
    [depth1]: {
      sessionId: params?.sessionIds ? "depth-1-session" : "depth-1",
      updatedAt: Date.now(),
      spawnedBy: "agent:main:main",
    },
    [callerKey]: {
      sessionId: params?.sessionIds ? "depth-2-session" : "depth-2",
      updatedAt: Date.now(),
      spawnedBy: depth1,
    },
  });
  return { depth1, callerKey };
}

(deftest-group "sessions_spawn depth + child limits", () => {
  beforeEach(() => {
    resetSubagentRegistryForTests();
    callGatewayMock.mockClear();
    storeTemplatePath = path.join(
      os.tmpdir(),
      `openclaw-subagent-depth-${Date.now()}-${Math.random().toString(16).slice(2)}-{agentId}.json`,
    );
    configOverride = {
      session: createPerSenderSessionConfig({ store: storeTemplatePath }),
    };

    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const req = opts as { method?: string };
      if (req.method === "agent") {
        return { runId: "run-depth" };
      }
      if (req.method === "agent.wait") {
        return { status: "running" };
      }
      return {};
    });
  });

  (deftest "rejects spawning when caller depth reaches maxSpawnDepth", async () => {
    const tool = createSessionsSpawnTool({ agentSessionKey: "agent:main:subagent:parent" });
    const result = await tool.execute("call-depth-reject", { task: "hello" });

    (expect* result.details).matches-object({
      status: "forbidden",
      error: "sessions_spawn is not allowed at this depth (current depth: 1, max: 1)",
    });
  });

  (deftest "allows depth-1 callers when maxSpawnDepth is 2", async () => {
    setSubagentLimits({ maxSpawnDepth: 2 });

    const tool = createSessionsSpawnTool({ agentSessionKey: "agent:main:subagent:parent" });
    const result = await tool.execute("call-depth-allow", { task: "hello" });

    (expect* result.details).matches-object({
      status: "accepted",
      childSessionKey: expect.stringMatching(/^agent:main:subagent:/),
      runId: "run-depth",
    });

    const calls = callGatewayMock.mock.calls.map(
      (call) => call[0] as { method?: string; params?: Record<string, unknown> },
    );
    const agentCall = calls.find((entry) => entry.method === "agent");
    (expect* agentCall?.params?.spawnedBy).is("agent:main:subagent:parent");

    const spawnDepthPatch = calls.find(
      (entry) => entry.method === "sessions.patch" && entry.params?.spawnDepth === 2,
    );
    (expect* spawnDepthPatch?.params?.key).toMatch(/^agent:main:subagent:/);
  });

  (deftest "rejects depth-2 callers when maxSpawnDepth is 2 (using stored spawnDepth on flat keys)", async () => {
    setSubagentLimits({ maxSpawnDepth: 2 });

    const callerKey = "agent:main:subagent:flat-depth-2";
    writeStore("main", {
      [callerKey]: {
        sessionId: "flat-depth-2",
        updatedAt: Date.now(),
        spawnDepth: 2,
      },
    });

    const tool = createSessionsSpawnTool({ agentSessionKey: callerKey });
    const result = await tool.execute("call-depth-2-reject", { task: "hello" });

    (expect* result.details).matches-object({
      status: "forbidden",
      error: "sessions_spawn is not allowed at this depth (current depth: 2, max: 2)",
    });
  });

  (deftest "rejects depth-2 callers when spawnDepth is missing but spawnedBy ancestry implies depth 2", async () => {
    setSubagentLimits({ maxSpawnDepth: 2 });
    const { callerKey } = seedDepthTwoAncestryStore();

    const tool = createSessionsSpawnTool({ agentSessionKey: callerKey });
    const result = await tool.execute("call-depth-ancestry-reject", { task: "hello" });

    (expect* result.details).matches-object({
      status: "forbidden",
      error: "sessions_spawn is not allowed at this depth (current depth: 2, max: 2)",
    });
  });

  (deftest "rejects depth-2 callers when the requester key is a sessionId", async () => {
    setSubagentLimits({ maxSpawnDepth: 2 });
    seedDepthTwoAncestryStore({ sessionIds: true });

    const tool = createSessionsSpawnTool({ agentSessionKey: "depth-2-session" });
    const result = await tool.execute("call-depth-sessionid-reject", { task: "hello" });

    (expect* result.details).matches-object({
      status: "forbidden",
      error: "sessions_spawn is not allowed at this depth (current depth: 2, max: 2)",
    });
  });

  (deftest "rejects when active children for requester session reached maxChildrenPerAgent", async () => {
    configOverride = {
      session: createPerSenderSessionConfig({ store: storeTemplatePath }),
      agents: {
        defaults: {
          subagents: {
            maxSpawnDepth: 2,
            maxChildrenPerAgent: 1,
          },
        },
      },
    };

    addSubagentRunForTests({
      runId: "existing-run",
      childSessionKey: "agent:main:subagent:existing",
      requesterSessionKey: "agent:main:subagent:parent",
      requesterDisplayKey: "agent:main:subagent:parent",
      task: "existing",
      cleanup: "keep",
      createdAt: Date.now(),
      startedAt: Date.now(),
    });

    const tool = createSessionsSpawnTool({ agentSessionKey: "agent:main:subagent:parent" });
    const result = await tool.execute("call-max-children", { task: "hello" });

    (expect* result.details).matches-object({
      status: "forbidden",
      error: "sessions_spawn has reached max active children for this session (1/1)",
    });
  });

  (deftest "does not use subagent maxConcurrent as a per-parent spawn gate", async () => {
    configOverride = {
      session: createPerSenderSessionConfig({ store: storeTemplatePath }),
      agents: {
        defaults: {
          subagents: {
            maxSpawnDepth: 2,
            maxChildrenPerAgent: 5,
            maxConcurrent: 1,
          },
        },
      },
    };

    const tool = createSessionsSpawnTool({ agentSessionKey: "agent:main:subagent:parent" });
    const result = await tool.execute("call-max-concurrent-independent", { task: "hello" });

    (expect* result.details).matches-object({
      status: "accepted",
      runId: "run-depth",
    });
  });

  (deftest "fails spawn when sessions.patch rejects the model", async () => {
    setSubagentLimits({ maxSpawnDepth: 2 });
    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const req = opts as { method?: string; params?: { model?: string } };
      if (req.method === "sessions.patch" && req.params?.model === "bad-model") {
        error("invalid model: bad-model");
      }
      if (req.method === "agent") {
        return { runId: "run-depth" };
      }
      if (req.method === "agent.wait") {
        return { status: "running" };
      }
      return {};
    });

    const tool = createSessionsSpawnTool({ agentSessionKey: "main" });
    const result = await tool.execute("call-model-reject", {
      task: "hello",
      model: "bad-model",
    });

    (expect* result.details).matches-object({
      status: "error",
    });
    (expect* String((result.details as { error?: string }).error ?? "")).contains("invalid model");
    (expect* 
      callGatewayMock.mock.calls.some(
        (call) => (call[0] as { method?: string }).method === "agent",
      ),
    ).is(false);
  });
});
