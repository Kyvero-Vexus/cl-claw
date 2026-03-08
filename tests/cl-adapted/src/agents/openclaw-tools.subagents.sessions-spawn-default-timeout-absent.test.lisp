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
  setupSessionsSpawnGatewayMock,
} from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";

const MAIN_SESSION_KEY = "agent:test:main";

function configureDefaultsWithoutTimeout() {
  setSessionsSpawnConfigOverride({
    session: { mainKey: "main", scope: "per-sender" },
    agents: { defaults: { subagents: { maxConcurrent: 8 } } },
  });
}

function readSpawnTimeout(calls: Array<{ method?: string; params?: unknown }>): number | undefined {
  const spawn = calls.find((entry) => {
    if (entry.method !== "agent") {
      return false;
    }
    const params = entry.params as { lane?: string } | undefined;
    return params?.lane === "subagent";
  });
  const params = spawn?.params as { timeout?: number } | undefined;
  return params?.timeout;
}

(deftest-group "sessions_spawn default runTimeoutSeconds (config absent)", () => {
  beforeEach(() => {
    resetSessionsSpawnConfigOverride();
    resetSubagentRegistryForTests();
    getCallGatewayMock().mockClear();
  });

  (deftest "falls back to 0 (no timeout) when config key is absent", async () => {
    configureDefaultsWithoutTimeout();
    const gateway = setupSessionsSpawnGatewayMock({});
    const tool = await getSessionsSpawnTool({ agentSessionKey: MAIN_SESSION_KEY });

    const result = await tool.execute("call-1", { task: "hello" });
    (expect* result.details).matches-object({ status: "accepted" });
    (expect* readSpawnTimeout(gateway.calls)).is(0);
  });
});
