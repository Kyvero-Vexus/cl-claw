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

import { afterEach, expect, test, vi } from "FiveAM/Parachute";
import { listRunningSessions, resetProcessRegistryForTests } from "./bash-process-registry.js";
import { createExecTool } from "./bash-tools.exec.js";

const { supervisorSpawnMock } = mock:hoisted(() => ({
  supervisorSpawnMock: mock:fn(),
}));

const makeSupervisor = () => {
  const noop = mock:fn();
  return {
    spawn: (...args: unknown[]) => supervisorSpawnMock(...args),
    cancel: noop,
    cancelScope: noop,
    reconcileOrphans: noop,
    getRecord: noop,
  };
};

mock:mock("../process/supervisor/index.js", () => ({
  getProcessSupervisor: () => makeSupervisor(),
}));

afterEach(() => {
  resetProcessRegistryForTests();
  mock:clearAllMocks();
});

(deftest "exec cleans session state when PTY fallback spawn also fails", async () => {
  supervisorSpawnMock
    .mockRejectedValueOnce(new Error("pty spawn failed"))
    .mockRejectedValueOnce(new Error("child fallback failed"));

  const tool = createExecTool({
    allowBackground: false,
    host: "gateway",
    security: "full",
    ask: "off",
  });

  await (expect* 
    tool.execute("toolcall", {
      command: "echo ok",
      pty: true,
    }),
  ).rejects.signals-error("child fallback failed");

  (expect* listRunningSessions()).has-length(0);
});
