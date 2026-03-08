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

import { afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

const noop = () => {};

mock:mock("../gateway/call.js", () => ({
  callGateway: mock:fn(async (request: unknown) => {
    const method = (request as { method?: string }).method;
    if (method === "agent.wait") {
      // Keep lifecycle unsettled so register/replace assertions can inspect stored state.
      return { status: "pending" };
    }
    return {};
  }),
}));

mock:mock("../infra/agent-events.js", () => ({
  onAgentEvent: mock:fn((_handler: unknown) => noop),
}));

mock:mock("../config/config.js", () => ({
  loadConfig: mock:fn(() => ({
    agents: { defaults: { subagents: { archiveAfterMinutes: 60 } } },
  })),
}));

mock:mock("./subagent-announce.js", () => ({
  runSubagentAnnounceFlow: mock:fn(async () => true),
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: mock:fn(() => null),
}));

mock:mock("./subagent-registry.store.js", () => ({
  loadSubagentRegistryFromDisk: mock:fn(() => new Map()),
  saveSubagentRegistryToDisk: mock:fn(() => {}),
}));

(deftest-group "subagent registry archive behavior", () => {
  let mod: typeof import("./subagent-registry.js");

  beforeAll(async () => {
    mod = await import("./subagent-registry.js");
  });

  afterEach(() => {
    mod.resetSubagentRegistryForTests({ persist: false });
  });

  (deftest "does not set archiveAtMs for persistent session-mode runs", () => {
    mod.registerSubagentRun({
      runId: "run-session-1",
      childSessionKey: "agent:main:subagent:session-1",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "persistent-session",
      cleanup: "keep",
      spawnMode: "session",
    });

    const run = mod.listSubagentRunsForRequester("agent:main:main")[0];
    (expect* run?.runId).is("run-session-1");
    (expect* run?.spawnMode).is("session");
    (expect* run?.archiveAtMs).toBeUndefined();
  });

  (deftest "keeps archiveAtMs unset when replacing a session-mode run after steer restart", () => {
    mod.registerSubagentRun({
      runId: "run-old",
      childSessionKey: "agent:main:subagent:session-1",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "persistent-session",
      cleanup: "keep",
      spawnMode: "session",
    });

    const replaced = mod.replaceSubagentRunAfterSteer({
      previousRunId: "run-old",
      nextRunId: "run-new",
    });

    (expect* replaced).is(true);
    const run = mod
      .listSubagentRunsForRequester("agent:main:main")
      .find((entry) => entry.runId === "run-new");
    (expect* run?.spawnMode).is("session");
    (expect* run?.archiveAtMs).toBeUndefined();
  });
});
