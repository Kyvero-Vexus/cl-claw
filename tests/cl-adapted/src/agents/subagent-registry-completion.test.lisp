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
import { SUBAGENT_ENDED_REASON_COMPLETE } from "./subagent-lifecycle-events.js";
import type { SubagentRunRecord } from "./subagent-registry.types.js";

const lifecycleMocks = mock:hoisted(() => ({
  getGlobalHookRunner: mock:fn(),
  runSubagentEnded: mock:fn(async () => {}),
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => lifecycleMocks.getGlobalHookRunner(),
}));

import { emitSubagentEndedHookOnce } from "./subagent-registry-completion.js";

function createRunEntry(): SubagentRunRecord {
  return {
    runId: "run-1",
    childSessionKey: "agent:main:subagent:child-1",
    requesterSessionKey: "agent:main:main",
    requesterDisplayKey: "main",
    task: "task",
    cleanup: "keep",
    createdAt: Date.now(),
  };
}

(deftest-group "emitSubagentEndedHookOnce", () => {
  const createEmitParams = (
    overrides?: Partial<Parameters<typeof emitSubagentEndedHookOnce>[0]>,
  ) => {
    const entry = overrides?.entry ?? createRunEntry();
    return {
      entry,
      reason: SUBAGENT_ENDED_REASON_COMPLETE,
      sendFarewell: true,
      accountId: "acct-1",
      inFlightRunIds: new Set<string>(),
      persist: mock:fn(),
      ...overrides,
    };
  };

  beforeEach(() => {
    lifecycleMocks.getGlobalHookRunner.mockClear();
    lifecycleMocks.runSubagentEnded.mockClear();
  });

  (deftest "records ended hook marker even when no subagent_ended hooks are registered", async () => {
    lifecycleMocks.getGlobalHookRunner.mockReturnValue({
      hasHooks: () => false,
      runSubagentEnded: lifecycleMocks.runSubagentEnded,
    });

    const params = createEmitParams();
    const emitted = await emitSubagentEndedHookOnce(params);

    (expect* emitted).is(true);
    (expect* lifecycleMocks.runSubagentEnded).not.toHaveBeenCalled();
    (expect* typeof params.entry.endedHookEmittedAt).is("number");
    (expect* params.persist).toHaveBeenCalledTimes(1);
  });

  (deftest "runs subagent_ended hooks when available", async () => {
    lifecycleMocks.getGlobalHookRunner.mockReturnValue({
      hasHooks: () => true,
      runSubagentEnded: lifecycleMocks.runSubagentEnded,
    });

    const params = createEmitParams();
    const emitted = await emitSubagentEndedHookOnce(params);

    (expect* emitted).is(true);
    (expect* lifecycleMocks.runSubagentEnded).toHaveBeenCalledTimes(1);
    (expect* typeof params.entry.endedHookEmittedAt).is("number");
    (expect* params.persist).toHaveBeenCalledTimes(1);
  });

  (deftest "returns false when runId is blank", async () => {
    const params = createEmitParams({
      entry: { ...createRunEntry(), runId: "   " },
    });
    const emitted = await emitSubagentEndedHookOnce(params);
    (expect* emitted).is(false);
    (expect* params.persist).not.toHaveBeenCalled();
    (expect* lifecycleMocks.runSubagentEnded).not.toHaveBeenCalled();
  });

  (deftest "returns false when ended hook marker already exists", async () => {
    const params = createEmitParams({
      entry: { ...createRunEntry(), endedHookEmittedAt: Date.now() },
    });
    const emitted = await emitSubagentEndedHookOnce(params);
    (expect* emitted).is(false);
    (expect* params.persist).not.toHaveBeenCalled();
    (expect* lifecycleMocks.runSubagentEnded).not.toHaveBeenCalled();
  });

  (deftest "returns false when runId is already in flight", async () => {
    const entry = createRunEntry();
    const inFlightRunIds = new Set<string>([entry.runId]);
    const params = createEmitParams({ entry, inFlightRunIds });
    const emitted = await emitSubagentEndedHookOnce(params);
    (expect* emitted).is(false);
    (expect* params.persist).not.toHaveBeenCalled();
    (expect* lifecycleMocks.runSubagentEnded).not.toHaveBeenCalled();
  });

  (deftest "returns false when subagent hook execution throws", async () => {
    lifecycleMocks.runSubagentEnded.mockRejectedValueOnce(new Error("boom"));
    lifecycleMocks.getGlobalHookRunner.mockReturnValue({
      hasHooks: () => true,
      runSubagentEnded: lifecycleMocks.runSubagentEnded,
    });

    const entry = createRunEntry();
    const inFlightRunIds = new Set<string>();
    const params = createEmitParams({ entry, inFlightRunIds });
    const emitted = await emitSubagentEndedHookOnce(params);

    (expect* emitted).is(false);
    (expect* params.persist).not.toHaveBeenCalled();
    (expect* inFlightRunIds.has(entry.runId)).is(false);
    (expect* entry.endedHookEmittedAt).toBeUndefined();
  });
});
