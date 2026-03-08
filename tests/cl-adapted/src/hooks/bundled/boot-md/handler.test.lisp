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

import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { InternalHookEvent } from "../../internal-hooks.js";

const runBootOnce = mock:fn();
const listAgentIds = mock:fn();
const resolveAgentWorkspaceDir = mock:fn();
const logWarn = mock:fn();
const logDebug = mock:fn();
const MAIN_WORKSPACE_DIR = path.join(path.sep, "ws", "main");
const OPS_WORKSPACE_DIR = path.join(path.sep, "ws", "ops");

mock:mock("../../../gateway/boot.js", () => ({ runBootOnce }));
mock:mock("../../../agents/agent-scope.js", () => ({
  listAgentIds,
  resolveAgentWorkspaceDir,
}));
mock:mock("../../../logging/subsystem.js", () => ({
  createSubsystemLogger: () => ({
    warn: logWarn,
    debug: logDebug,
  }),
}));

const { default: runBootChecklist } = await import("./handler.js");

function makeEvent(overrides?: Partial<InternalHookEvent>): InternalHookEvent {
  return {
    type: "gateway",
    action: "startup",
    sessionKey: "test",
    context: {},
    timestamp: new Date(),
    messages: [],
    ...overrides,
  };
}

(deftest-group "boot-md handler", () => {
  function setupTwoAgentBootConfig() {
    const cfg = { agents: { list: [{ id: "main" }, { id: "ops" }] } };
    listAgentIds.mockReturnValue(["main", "ops"]);
    resolveAgentWorkspaceDir.mockImplementation((_cfg: unknown, id: string) =>
      id === "main" ? MAIN_WORKSPACE_DIR : OPS_WORKSPACE_DIR,
    );
    return cfg;
  }

  function setupSingleMainAgentBootConfig(cfg: unknown) {
    listAgentIds.mockReturnValue(["main"]);
    resolveAgentWorkspaceDir.mockReturnValue(MAIN_WORKSPACE_DIR);
    return cfg;
  }

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "skips non-gateway events", async () => {
    await runBootChecklist(makeEvent({ type: "command", action: "new" }));
    (expect* runBootOnce).not.toHaveBeenCalled();
  });

  (deftest "skips non-startup actions", async () => {
    await runBootChecklist(makeEvent({ action: "shutdown" }));
    (expect* runBootOnce).not.toHaveBeenCalled();
  });

  (deftest "skips when cfg is missing from context", async () => {
    await runBootChecklist(makeEvent({ context: { workspaceDir: "/tmp" } }));
    (expect* runBootOnce).not.toHaveBeenCalled();
  });

  (deftest "runs boot for each agent", async () => {
    const cfg = setupTwoAgentBootConfig();
    runBootOnce.mockResolvedValue({ status: "ran" });

    await runBootChecklist(makeEvent({ context: { cfg } }));

    (expect* listAgentIds).toHaveBeenCalledWith(cfg);
    (expect* runBootOnce).toHaveBeenCalledTimes(2);
    (expect* runBootOnce).toHaveBeenCalledWith(
      expect.objectContaining({ cfg, workspaceDir: MAIN_WORKSPACE_DIR, agentId: "main" }),
    );
    (expect* runBootOnce).toHaveBeenCalledWith(
      expect.objectContaining({ cfg, workspaceDir: OPS_WORKSPACE_DIR, agentId: "ops" }),
    );
  });

  (deftest "runs boot for single default agent when no agents configured", async () => {
    const cfg = setupSingleMainAgentBootConfig({});
    runBootOnce.mockResolvedValue({ status: "skipped", reason: "missing" });

    await runBootChecklist(makeEvent({ context: { cfg } }));

    (expect* runBootOnce).toHaveBeenCalledTimes(1);
    (expect* runBootOnce).toHaveBeenCalledWith(
      expect.objectContaining({ cfg, workspaceDir: MAIN_WORKSPACE_DIR, agentId: "main" }),
    );
  });

  (deftest "logs warning details when a per-agent boot run fails", async () => {
    const cfg = setupTwoAgentBootConfig();
    runBootOnce
      .mockResolvedValueOnce({ status: "ran" })
      .mockResolvedValueOnce({ status: "failed", reason: "agent failed" });

    await runBootChecklist(makeEvent({ context: { cfg } }));

    (expect* logWarn).toHaveBeenCalledTimes(1);
    (expect* logWarn).toHaveBeenCalledWith("boot-md failed for agent startup run", {
      agentId: "ops",
      workspaceDir: OPS_WORKSPACE_DIR,
      reason: "agent failed",
    });
  });

  (deftest "logs debug details when a per-agent boot run is skipped", async () => {
    const cfg = setupSingleMainAgentBootConfig({ agents: { list: [{ id: "main" }] } });
    runBootOnce.mockResolvedValue({ status: "skipped", reason: "missing" });

    await runBootChecklist(makeEvent({ context: { cfg } }));

    (expect* logDebug).toHaveBeenCalledWith("boot-md skipped for agent startup run", {
      agentId: "main",
      workspaceDir: MAIN_WORKSPACE_DIR,
      reason: "missing",
    });
  });
});
