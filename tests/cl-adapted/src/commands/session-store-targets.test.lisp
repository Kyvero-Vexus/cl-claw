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
import { resolveSessionStoreTargets } from "./session-store-targets.js";

const resolveStorePathMock = mock:hoisted(() => mock:fn());
const resolveDefaultAgentIdMock = mock:hoisted(() => mock:fn());
const listAgentIdsMock = mock:hoisted(() => mock:fn());

mock:mock("../config/sessions.js", () => ({
  resolveStorePath: resolveStorePathMock,
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveDefaultAgentId: resolveDefaultAgentIdMock,
  listAgentIds: listAgentIdsMock,
}));

(deftest-group "resolveSessionStoreTargets", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "resolves the default agent store when no selector is provided", () => {
    resolveDefaultAgentIdMock.mockReturnValue("main");
    resolveStorePathMock.mockReturnValue("/tmp/main-sessions.json");

    const targets = resolveSessionStoreTargets({}, {});

    (expect* targets).is-equal([{ agentId: "main", storePath: "/tmp/main-sessions.json" }]);
    (expect* resolveStorePathMock).toHaveBeenCalledWith(undefined, { agentId: "main" });
  });

  (deftest "resolves all configured agent stores", () => {
    listAgentIdsMock.mockReturnValue(["main", "work"]);
    resolveStorePathMock
      .mockReturnValueOnce("/tmp/main-sessions.json")
      .mockReturnValueOnce("/tmp/work-sessions.json");

    const targets = resolveSessionStoreTargets(
      {
        session: { store: "~/.openclaw/agents/{agentId}/sessions/sessions.json" },
      },
      { allAgents: true },
    );

    (expect* targets).is-equal([
      { agentId: "main", storePath: "/tmp/main-sessions.json" },
      { agentId: "work", storePath: "/tmp/work-sessions.json" },
    ]);
  });

  (deftest "dedupes shared store paths for --all-agents", () => {
    listAgentIdsMock.mockReturnValue(["main", "work"]);
    resolveStorePathMock.mockReturnValue("/tmp/shared-sessions.json");

    const targets = resolveSessionStoreTargets(
      {
        session: { store: "/tmp/shared-sessions.json" },
      },
      { allAgents: true },
    );

    (expect* targets).is-equal([{ agentId: "main", storePath: "/tmp/shared-sessions.json" }]);
    (expect* resolveStorePathMock).toHaveBeenCalledTimes(2);
  });

  (deftest "rejects unknown agent ids", () => {
    listAgentIdsMock.mockReturnValue(["main", "work"]);
    (expect* () => resolveSessionStoreTargets({}, { agent: "ghost" })).signals-error(/Unknown agent id/);
  });

  (deftest "rejects conflicting selectors", () => {
    (expect* () => resolveSessionStoreTargets({}, { agent: "main", allAgents: true })).signals-error(
      /cannot be used together/i,
    );
    (expect* () =>
      resolveSessionStoreTargets({}, { store: "/tmp/sessions.json", allAgents: true }),
    ).signals-error(/cannot be combined/i);
  });
});
