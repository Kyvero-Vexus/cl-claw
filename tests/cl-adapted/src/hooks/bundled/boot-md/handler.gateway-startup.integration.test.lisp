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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveAgentWorkspaceDir } from "../../../agents/agent-scope.js";
import type { CliDeps } from "../../../cli/deps.js";
import type { OpenClawConfig } from "../../../config/config.js";

const runBootOnce = mock:fn();

mock:mock("../../../gateway/boot.js", () => ({ runBootOnce }));
mock:mock("../../../logging/subsystem.js", () => ({
  createSubsystemLogger: () => ({
    warn: mock:fn(),
    debug: mock:fn(),
  }),
}));

const { default: runBootChecklist } = await import("./handler.js");
const { clearInternalHooks, createInternalHookEvent, registerInternalHook, triggerInternalHook } =
  await import("../../internal-hooks.js");

(deftest-group "boot-md startup hook integration", () => {
  beforeEach(() => {
    runBootOnce.mockClear();
    clearInternalHooks();
  });

  afterEach(() => {
    clearInternalHooks();
  });

  (deftest "dispatches gateway:startup through internal hooks and runs BOOT for each configured agent scope", async () => {
    const cfg = {
      hooks: { internal: { enabled: true } },
      agents: {
        list: [
          { id: "main", default: true, workspace: "/ws/main" },
          { id: "ops", workspace: "/ws/ops" },
        ],
      },
    } as OpenClawConfig;
    const deps = {} as CliDeps;
    runBootOnce.mockResolvedValue({ status: "ran" });

    registerInternalHook("gateway:startup", runBootChecklist);
    const event = createInternalHookEvent("gateway", "startup", "gateway:startup", { cfg, deps });
    await triggerInternalHook(event);

    const mainWorkspaceDir = resolveAgentWorkspaceDir(cfg, "main");
    const opsWorkspaceDir = resolveAgentWorkspaceDir(cfg, "ops");

    (expect* runBootOnce).toHaveBeenCalledTimes(2);
    (expect* runBootOnce).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ cfg, deps, workspaceDir: mainWorkspaceDir, agentId: "main" }),
    );
    (expect* runBootOnce).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ cfg, deps, workspaceDir: opsWorkspaceDir, agentId: "ops" }),
    );
  });
});
