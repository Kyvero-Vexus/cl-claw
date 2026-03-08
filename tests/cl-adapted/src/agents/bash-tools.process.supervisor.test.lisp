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
import {
  addSession,
  getFinishedSession,
  getSession,
  resetProcessRegistryForTests,
} from "./bash-process-registry.js";
import { createProcessSessionFixture } from "./bash-process-registry.test-helpers.js";
import { createProcessTool } from "./bash-tools.process.js";

const { supervisorMock } = mock:hoisted(() => ({
  supervisorMock: {
    spawn: mock:fn(),
    cancel: mock:fn(),
    cancelScope: mock:fn(),
    reconcileOrphans: mock:fn(),
    getRecord: mock:fn(),
  },
}));

const { killProcessTreeMock } = mock:hoisted(() => ({
  killProcessTreeMock: mock:fn(),
}));

mock:mock("../process/supervisor/index.js", () => ({
  getProcessSupervisor: () => supervisorMock,
}));

mock:mock("../process/kill-tree.js", () => ({
  killProcessTree: (...args: unknown[]) => killProcessTreeMock(...args),
}));

function createBackgroundSession(id: string, pid?: number) {
  return createProcessSessionFixture({
    id,
    command: "sleep 999",
    backgrounded: true,
    ...(pid === undefined ? {} : { pid }),
  });
}

(deftest-group "process tool supervisor cancellation", () => {
  beforeEach(() => {
    supervisorMock.spawn.mockClear();
    supervisorMock.cancel.mockClear();
    supervisorMock.cancelScope.mockClear();
    supervisorMock.reconcileOrphans.mockClear();
    supervisorMock.getRecord.mockClear();
    killProcessTreeMock.mockClear();
  });

  afterEach(() => {
    resetProcessRegistryForTests();
  });

  (deftest "routes kill through supervisor when run is managed", async () => {
    supervisorMock.getRecord.mockReturnValue({
      runId: "sess",
      state: "running",
    });
    addSession(createBackgroundSession("sess"));
    const processTool = createProcessTool();

    const result = await processTool.execute("toolcall", {
      action: "kill",
      sessionId: "sess",
    });

    (expect* supervisorMock.cancel).toHaveBeenCalledWith("sess", "manual-cancel");
    (expect* getSession("sess")).toBeDefined();
    (expect* getSession("sess")?.exited).is(false);
    (expect* result.content[0]).matches-object({
      type: "text",
      text: "Termination requested for session sess.",
    });
  });

  (deftest "remove drops running session immediately when cancellation is requested", async () => {
    supervisorMock.getRecord.mockReturnValue({
      runId: "sess",
      state: "running",
    });
    addSession(createBackgroundSession("sess"));
    const processTool = createProcessTool();

    const result = await processTool.execute("toolcall", {
      action: "remove",
      sessionId: "sess",
    });

    (expect* supervisorMock.cancel).toHaveBeenCalledWith("sess", "manual-cancel");
    (expect* getSession("sess")).toBeUndefined();
    (expect* getFinishedSession("sess")).toBeUndefined();
    (expect* result.content[0]).matches-object({
      type: "text",
      text: "Removed session sess (termination requested).",
    });
  });

  (deftest "falls back to process-tree kill when supervisor record is missing", async () => {
    supervisorMock.getRecord.mockReturnValue(undefined);
    addSession(createBackgroundSession("sess-fallback", 4242));
    const processTool = createProcessTool();

    const result = await processTool.execute("toolcall", {
      action: "kill",
      sessionId: "sess-fallback",
    });

    (expect* killProcessTreeMock).toHaveBeenCalledWith(4242);
    (expect* getSession("sess-fallback")).toBeUndefined();
    (expect* getFinishedSession("sess-fallback")).toBeDefined();
    (expect* result.content[0]).matches-object({
      type: "text",
      text: "Killed session sess-fallback.",
    });
  });

  (deftest "fails remove when no supervisor record and no pid is available", async () => {
    supervisorMock.getRecord.mockReturnValue(undefined);
    addSession(createBackgroundSession("sess-no-pid"));
    const processTool = createProcessTool();

    const result = await processTool.execute("toolcall", {
      action: "remove",
      sessionId: "sess-no-pid",
    });

    (expect* killProcessTreeMock).not.toHaveBeenCalled();
    (expect* getSession("sess-no-pid")).toBeDefined();
    (expect* result.details).matches-object({ status: "failed" });
    (expect* result.content[0]).matches-object({
      type: "text",
      text: "Unable to remove session sess-no-pid: no active supervisor run or process id.",
    });
  });
});
