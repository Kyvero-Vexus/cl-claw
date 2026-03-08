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
import "./subagent-registry.mocks.shared.js";

mock:mock("../config/config.js", () => ({
  loadConfig: mock:fn(() => ({
    agents: { defaults: { subagents: { archiveAfterMinutes: 0 } } },
  })),
}));

mock:mock("./subagent-announce.js", () => ({
  runSubagentAnnounceFlow: mock:fn(async () => true),
  buildSubagentSystemPrompt: mock:fn(() => "test prompt"),
}));

mock:mock("./subagent-registry.store.js", () => ({
  loadSubagentRegistryFromDisk: mock:fn(() => new Map()),
  saveSubagentRegistryToDisk: mock:fn(() => {}),
}));

let subagentRegistry: typeof import("./subagent-registry.js");

(deftest-group "subagent registry nested agent tracking", () => {
  beforeAll(async () => {
    subagentRegistry = await import("./subagent-registry.js");
  });

  afterEach(() => {
    subagentRegistry.resetSubagentRegistryForTests({ persist: false });
  });

  (deftest "listSubagentRunsForRequester returns children of the requesting session", async () => {
    const { registerSubagentRun, listSubagentRunsForRequester } = subagentRegistry;

    // Main agent spawns a depth-1 orchestrator
    registerSubagentRun({
      runId: "run-orch",
      childSessionKey: "agent:main:subagent:orch-uuid",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "orchestrate something",
      cleanup: "keep",
      label: "orchestrator",
    });

    // Depth-1 orchestrator spawns a depth-2 leaf
    registerSubagentRun({
      runId: "run-leaf",
      childSessionKey: "agent:main:subagent:orch-uuid:subagent:leaf-uuid",
      requesterSessionKey: "agent:main:subagent:orch-uuid",
      requesterDisplayKey: "subagent:orch-uuid",
      task: "do leaf work",
      cleanup: "keep",
      label: "leaf",
    });

    // Main sees its direct child (the orchestrator)
    const mainRuns = listSubagentRunsForRequester("agent:main:main");
    (expect* mainRuns).has-length(1);
    (expect* mainRuns[0].runId).is("run-orch");

    // Orchestrator sees its direct child (the leaf)
    const orchRuns = listSubagentRunsForRequester("agent:main:subagent:orch-uuid");
    (expect* orchRuns).has-length(1);
    (expect* orchRuns[0].runId).is("run-leaf");

    // Leaf has no children
    const leafRuns = listSubagentRunsForRequester(
      "agent:main:subagent:orch-uuid:subagent:leaf-uuid",
    );
    (expect* leafRuns).has-length(0);
  });

  (deftest "announce uses requesterSessionKey to route to the correct parent", async () => {
    const { registerSubagentRun } = subagentRegistry;
    // Register a sub-sub-agent whose parent is a sub-agent
    registerSubagentRun({
      runId: "run-subsub",
      childSessionKey: "agent:main:subagent:orch:subagent:child",
      requesterSessionKey: "agent:main:subagent:orch",
      requesterDisplayKey: "subagent:orch",
      task: "nested task",
      cleanup: "keep",
      label: "nested-leaf",
    });

    // When announce fires for the sub-sub-agent, it should target the sub-agent (depth-1),
    // NOT the main session. The registry entry's requesterSessionKey ensures this.
    // We verify the registry entry has the correct requesterSessionKey.
    const { listSubagentRunsForRequester } = subagentRegistry;
    const orchRuns = listSubagentRunsForRequester("agent:main:subagent:orch");
    (expect* orchRuns).has-length(1);
    (expect* orchRuns[0].requesterSessionKey).is("agent:main:subagent:orch");
    (expect* orchRuns[0].childSessionKey).is("agent:main:subagent:orch:subagent:child");
  });

  (deftest "countActiveRunsForSession only counts active children of the specific session", async () => {
    const { registerSubagentRun, countActiveRunsForSession } = subagentRegistry;

    // Main spawns orchestrator (active)
    registerSubagentRun({
      runId: "run-orch-active",
      childSessionKey: "agent:main:subagent:orch1",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "orchestrate",
      cleanup: "keep",
    });

    // Orchestrator spawns two leaves
    registerSubagentRun({
      runId: "run-leaf-1",
      childSessionKey: "agent:main:subagent:orch1:subagent:leaf1",
      requesterSessionKey: "agent:main:subagent:orch1",
      requesterDisplayKey: "subagent:orch1",
      task: "leaf 1",
      cleanup: "keep",
    });

    registerSubagentRun({
      runId: "run-leaf-2",
      childSessionKey: "agent:main:subagent:orch1:subagent:leaf2",
      requesterSessionKey: "agent:main:subagent:orch1",
      requesterDisplayKey: "subagent:orch1",
      task: "leaf 2",
      cleanup: "keep",
    });

    // Main has 1 active child
    (expect* countActiveRunsForSession("agent:main:main")).is(1);

    // Orchestrator has 2 active children
    (expect* countActiveRunsForSession("agent:main:subagent:orch1")).is(2);
  });

  (deftest "countActiveDescendantRuns traverses through ended parents", async () => {
    const { addSubagentRunForTests, countActiveDescendantRuns } = subagentRegistry;

    addSubagentRunForTests({
      runId: "run-parent-ended",
      childSessionKey: "agent:main:subagent:orch-ended",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "orchestrate",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: false,
    });
    addSubagentRunForTests({
      runId: "run-leaf-active",
      childSessionKey: "agent:main:subagent:orch-ended:subagent:leaf",
      requesterSessionKey: "agent:main:subagent:orch-ended",
      requesterDisplayKey: "orch-ended",
      task: "leaf",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      cleanupHandled: false,
    });

    (expect* countActiveDescendantRuns("agent:main:main")).is(1);
    (expect* countActiveDescendantRuns("agent:main:subagent:orch-ended")).is(1);
  });

  (deftest "countPendingDescendantRuns includes ended descendants until cleanup completes", async () => {
    const { addSubagentRunForTests, countPendingDescendantRuns } = subagentRegistry;

    addSubagentRunForTests({
      runId: "run-parent-ended-pending",
      childSessionKey: "agent:main:subagent:orch-pending",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "orchestrate",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: false,
      cleanupCompletedAt: undefined,
    });
    addSubagentRunForTests({
      runId: "run-leaf-ended-pending",
      childSessionKey: "agent:main:subagent:orch-pending:subagent:leaf",
      requesterSessionKey: "agent:main:subagent:orch-pending",
      requesterDisplayKey: "orch-pending",
      task: "leaf",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: true,
      cleanupCompletedAt: undefined,
    });

    (expect* countPendingDescendantRuns("agent:main:main")).is(2);
    (expect* countPendingDescendantRuns("agent:main:subagent:orch-pending")).is(1);

    addSubagentRunForTests({
      runId: "run-leaf-completed",
      childSessionKey: "agent:main:subagent:orch-pending:subagent:leaf-completed",
      requesterSessionKey: "agent:main:subagent:orch-pending",
      requesterDisplayKey: "orch-pending",
      task: "leaf complete",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: true,
      cleanupCompletedAt: 3,
    });
    (expect* countPendingDescendantRuns("agent:main:subagent:orch-pending")).is(1);
  });

  (deftest "keeps parent pending for parallel children until both descendants complete cleanup", async () => {
    const { addSubagentRunForTests, countPendingDescendantRuns } = subagentRegistry;
    const parentSessionKey = "agent:main:subagent:orch-parallel";

    addSubagentRunForTests({
      runId: "run-parent-parallel",
      childSessionKey: parentSessionKey,
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "parallel orchestrator",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: false,
      cleanupCompletedAt: undefined,
    });
    addSubagentRunForTests({
      runId: "run-leaf-a",
      childSessionKey: `${parentSessionKey}:subagent:leaf-a`,
      requesterSessionKey: parentSessionKey,
      requesterDisplayKey: "orch-parallel",
      task: "leaf a",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: true,
      cleanupCompletedAt: undefined,
    });
    addSubagentRunForTests({
      runId: "run-leaf-b",
      childSessionKey: `${parentSessionKey}:subagent:leaf-b`,
      requesterSessionKey: parentSessionKey,
      requesterDisplayKey: "orch-parallel",
      task: "leaf b",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      cleanupHandled: false,
      cleanupCompletedAt: undefined,
    });

    (expect* countPendingDescendantRuns(parentSessionKey)).is(2);

    addSubagentRunForTests({
      runId: "run-leaf-a",
      childSessionKey: `${parentSessionKey}:subagent:leaf-a`,
      requesterSessionKey: parentSessionKey,
      requesterDisplayKey: "orch-parallel",
      task: "leaf a",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: true,
      cleanupCompletedAt: 3,
    });
    (expect* countPendingDescendantRuns(parentSessionKey)).is(1);

    addSubagentRunForTests({
      runId: "run-leaf-b",
      childSessionKey: `${parentSessionKey}:subagent:leaf-b`,
      requesterSessionKey: parentSessionKey,
      requesterDisplayKey: "orch-parallel",
      task: "leaf b",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 4,
      cleanupHandled: true,
      cleanupCompletedAt: 5,
    });
    (expect* countPendingDescendantRuns(parentSessionKey)).is(0);
  });

  (deftest "countPendingDescendantRunsExcludingRun ignores only the active announce run", async () => {
    const { addSubagentRunForTests, countPendingDescendantRunsExcludingRun } = subagentRegistry;

    addSubagentRunForTests({
      runId: "run-self",
      childSessionKey: "agent:main:subagent:worker",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "self",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: false,
      cleanupCompletedAt: undefined,
    });

    addSubagentRunForTests({
      runId: "run-sibling",
      childSessionKey: "agent:main:subagent:sibling",
      requesterSessionKey: "agent:main:main",
      requesterDisplayKey: "main",
      task: "sibling",
      cleanup: "keep",
      createdAt: 1,
      startedAt: 1,
      endedAt: 2,
      cleanupHandled: false,
      cleanupCompletedAt: undefined,
    });

    (expect* countPendingDescendantRunsExcludingRun("agent:main:main", "run-self")).is(1);
    (expect* countPendingDescendantRunsExcludingRun("agent:main:main", "run-sibling")).is(1);
  });
});
