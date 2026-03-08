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
  setupSessionsSpawnGatewayMock,
} from "./openclaw-tools.subagents.sessions-spawn.test-harness.js";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";
import { SUBAGENT_SPAWN_ACCEPTED_NOTE } from "./subagent-spawn.js";

const callGatewayMock = getCallGatewayMock();

type SpawnResult = { status?: string; note?: string };

(deftest-group "sessions_spawn: cron isolated session note suppression", () => {
  beforeEach(() => {
    callGatewayMock.mockReset();
    resetSubagentRegistryForTests();
    resetSessionsSpawnConfigOverride();
  });

  (deftest "suppresses ACCEPTED_NOTE for cron isolated sessions (mode=run)", async () => {
    setupSessionsSpawnGatewayMock({});
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "agent:main:cron:dd871818:run:cf959c9f",
    });
    const result = await tool.execute("call-cron-run", { task: "test task", mode: "run" });
    const details = result.details as SpawnResult;
    (expect* details.note).toBeUndefined();
    (expect* details.status).is("accepted");
  });

  (deftest "preserves ACCEPTED_NOTE for regular sessions (mode=run)", async () => {
    setupSessionsSpawnGatewayMock({});
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "agent:main:telegram:63448508",
    });
    const result = await tool.execute("call-regular-run", { task: "test task", mode: "run" });
    const details = result.details as SpawnResult;
    (expect* details.note).is(SUBAGENT_SPAWN_ACCEPTED_NOTE);
    (expect* details.status).is("accepted");
  });

  (deftest "does not suppress ACCEPTED_NOTE for non-canonical cron-like keys", async () => {
    setupSessionsSpawnGatewayMock({});
    const tool = await getSessionsSpawnTool({
      agentSessionKey: "agent:main:slack:cron:job:run:uuid",
    });
    const result = await tool.execute("call-cron-like-noncanonical", {
      task: "test task",
      mode: "run",
    });
    (expect* (result.details as SpawnResult).note).is(SUBAGENT_SPAWN_ACCEPTED_NOTE);
  });

  (deftest "does not suppress note when agentSessionKey is undefined", async () => {
    setupSessionsSpawnGatewayMock({});
    const tool = await getSessionsSpawnTool({
      agentSessionKey: undefined,
    });
    const result = await tool.execute("call-no-key", { task: "test task", mode: "run" });
    (expect* (result.details as SpawnResult).note).is(SUBAGENT_SPAWN_ACCEPTED_NOTE);
  });
});
