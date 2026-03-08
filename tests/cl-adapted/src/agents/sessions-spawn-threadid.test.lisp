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
  setSessionsSpawnConfigOverride,
} from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import {
  listSubagentRunsForRequester,
  resetSubagentRegistryForTests,
} from "./subagent-registry.js";

(deftest-group "sessions_spawn requesterOrigin threading", () => {
  const spawnAndReadRequesterRun = async (opts?: { agentThreadId?: number }) => {
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "main",
      agentChannel: "telegram",
      agentTo: "telegram:123",
      ...(opts?.agentThreadId === undefined ? {} : { agentThreadId: opts.agentThreadId }),
    });
    const result = await tool.execute("call", {
      task: "do thing",
      runTimeoutSeconds: 1,
    });
    (expect* result.details).matches-object({ status: "accepted", runId: "run-1" });

    const runs = listSubagentRunsForRequester("main");
    (expect* runs).has-length(1);
    return runs[0];
  };

  beforeEach(() => {
    const callGatewayMock = getCallGatewayMock();
    resetSubagentRegistryForTests();
    callGatewayMock.mockClear();
    setSessionsSpawnConfigOverride({
      session: {
        mainKey: "main",
        scope: "per-sender",
      },
    });

    callGatewayMock.mockImplementation(async (opts: unknown) => {
      const req = opts as { method?: string };
      if (req.method === "agent") {
        return { runId: "run-1", status: "accepted", acceptedAt: 1 };
      }
      // Prevent background announce flow by returning a non-terminal status.
      if (req.method === "agent.wait") {
        return { runId: "run-1", status: "running" };
      }
      return {};
    });
  });

  (deftest "captures threadId in requesterOrigin", async () => {
    const run = await spawnAndReadRequesterRun({ agentThreadId: 42 });
    (expect* run?.requesterOrigin).matches-object({
      channel: "telegram",
      to: "telegram:123",
      threadId: 42,
    });
  });

  (deftest "stores requesterOrigin without threadId when none is provided", async () => {
    const run = await spawnAndReadRequesterRun();
    (expect* run?.requesterOrigin?.threadId).toBeUndefined();
  });
});
