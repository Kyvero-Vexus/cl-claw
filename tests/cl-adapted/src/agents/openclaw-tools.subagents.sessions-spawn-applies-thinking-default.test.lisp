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
import * as harness from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";

const MAIN_SESSION_KEY = "agent:test:main";

type ThinkingLevel = "high" | "medium" | "low";

function applyThinkingDefault(thinking: ThinkingLevel) {
  harness.setSessionsSpawnConfigOverride({
    session: { mainKey: "main", scope: "per-sender" },
    agents: { defaults: { subagents: { thinking } } },
  });
}

function findSubagentThinking(
  calls: Array<{ method?: string; params?: unknown }>,
): string | undefined {
  for (const call of calls) {
    if (call.method !== "agent") {
      continue;
    }
    const params = call.params as { lane?: string; thinking?: string } | undefined;
    if (params?.lane === "subagent") {
      return params.thinking;
    }
  }
  return undefined;
}

function findPatchedThinking(
  calls: Array<{ method?: string; params?: unknown }>,
): string | undefined {
  for (let index = calls.length - 1; index >= 0; index -= 1) {
    const entry = calls[index];
    if (!entry || entry.method !== "sessions.patch") {
      continue;
    }
    const params = entry.params as { thinkingLevel?: string } | undefined;
    if (params?.thinkingLevel) {
      return params.thinkingLevel;
    }
  }
  return undefined;
}

async function expectThinkingPropagation(input: {
  callId: string;
  payload: Record<string, unknown>;
  expected: ThinkingLevel;
}) {
  const gateway = harness.setupSessionsSpawnGatewayMock({});
  const tool = await harness.getSessionsSpawnTool({ agentSessionKey: MAIN_SESSION_KEY });
  const result = await tool.execute(input.callId, input.payload);
  (expect* result.details).matches-object({ status: "accepted" });

  (expect* findSubagentThinking(gateway.calls)).is(input.expected);
  (expect* findPatchedThinking(gateway.calls)).is(input.expected);
}

(deftest-group "sessions_spawn thinking defaults", () => {
  beforeEach(() => {
    harness.resetSessionsSpawnConfigOverride();
    resetSubagentRegistryForTests();
    harness.getCallGatewayMock().mockClear();
    applyThinkingDefault("high");
  });

  (deftest "applies agents.defaults.subagents.thinking when thinking is omitted", async () => {
    await expectThinkingPropagation({
      callId: "call-1",
      payload: { task: "hello" },
      expected: "high",
    });
  });

  (deftest "prefers explicit sessions_spawn.thinking over config default", async () => {
    await expectThinkingPropagation({
      callId: "call-2",
      payload: { task: "hello", thinking: "low" },
      expected: "low",
    });
  });
});
