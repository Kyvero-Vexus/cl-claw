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
import * as sessionsHarness from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";

const MAIN_SESSION_KEY = "agent:test:main";

function applySubagentTimeoutDefault(seconds: number) {
  sessionsHarness.setSessionsSpawnConfigOverride({
    session: { mainKey: "main", scope: "per-sender" },
    agents: { defaults: { subagents: { runTimeoutSeconds: seconds } } },
  });
}

function getSubagentTimeout(
  calls: Array<{ method?: string; params?: unknown }>,
): number | undefined {
  for (const call of calls) {
    if (call.method !== "agent") {
      continue;
    }
    const params = call.params as { lane?: string; timeout?: number } | undefined;
    if (params?.lane === "subagent") {
      return params.timeout;
    }
  }
  return undefined;
}

async function spawnSubagent(callId: string, payload: Record<string, unknown>) {
  const tool = await sessionsHarness.getSessionsSpawnTool({ agentSessionKey: MAIN_SESSION_KEY });
  const result = await tool.execute(callId, payload);
  (expect* result.details).matches-object({ status: "accepted" });
}

(deftest-group "sessions_spawn default runTimeoutSeconds", () => {
  beforeEach(() => {
    sessionsHarness.resetSessionsSpawnConfigOverride();
    resetSubagentRegistryForTests();
    sessionsHarness.getCallGatewayMock().mockClear();
  });

  (deftest "uses config default when agent omits runTimeoutSeconds", async () => {
    applySubagentTimeoutDefault(900);
    const gateway = sessionsHarness.setupSessionsSpawnGatewayMock({});

    await spawnSubagent("call-1", { task: "hello" });

    (expect* getSubagentTimeout(gateway.calls)).is(900);
  });

  (deftest "explicit runTimeoutSeconds wins over config default", async () => {
    applySubagentTimeoutDefault(900);
    const gateway = sessionsHarness.setupSessionsSpawnGatewayMock({});

    await spawnSubagent("call-2", { task: "hello", runTimeoutSeconds: 300 });

    (expect* getSubagentTimeout(gateway.calls)).is(300);
  });
});
