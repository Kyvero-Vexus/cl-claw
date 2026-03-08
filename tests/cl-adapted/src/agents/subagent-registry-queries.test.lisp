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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  countActiveRunsForSessionFromRuns,
  countPendingDescendantRunsExcludingRunFromRuns,
  countPendingDescendantRunsFromRuns,
  listRunsForRequesterFromRuns,
  resolveRequesterForChildSessionFromRuns,
  shouldIgnorePostCompletionAnnounceForSessionFromRuns,
} from "./subagent-registry-queries.js";
import type { SubagentRunRecord } from "./subagent-registry.types.js";

function makeRun(overrides: Partial<SubagentRunRecord>): SubagentRunRecord {
  const runId = overrides.runId ?? "run-default";
  const childSessionKey = overrides.childSessionKey ?? `agent:main:subagent:${runId}`;
  const requesterSessionKey = overrides.requesterSessionKey ?? "agent:main:main";
  return {
    runId,
    childSessionKey,
    requesterSessionKey,
    requesterDisplayKey: requesterSessionKey,
    task: "test task",
    cleanup: "keep",
    createdAt: overrides.createdAt ?? 1,
    ...overrides,
  };
}

function toRunMap(runs: SubagentRunRecord[]): Map<string, SubagentRunRecord> {
  return new Map(runs.map((run) => [run.runId, run]));
}

(deftest-group "subagent registry query regressions", () => {
  (deftest "regression descendant count gating, pending descendants block announce until cleanup completion is recorded", () => {
    // Regression guard: parent announce must defer while any descendant cleanup is still pending.
    const parentSessionKey = "agent:main:subagent:parent";
    const runs = toRunMap([
      makeRun({
        runId: "run-parent",
        childSessionKey: parentSessionKey,
        requesterSessionKey: "agent:main:main",
        endedAt: 100,
        cleanupCompletedAt: undefined,
      }),
      makeRun({
        runId: "run-child-fast",
        childSessionKey: `${parentSessionKey}:subagent:fast`,
        requesterSessionKey: parentSessionKey,
        endedAt: 110,
        cleanupCompletedAt: 120,
      }),
      makeRun({
        runId: "run-child-slow",
        childSessionKey: `${parentSessionKey}:subagent:slow`,
        requesterSessionKey: parentSessionKey,
        endedAt: 115,
        cleanupCompletedAt: undefined,
      }),
    ]);

    (expect* countPendingDescendantRunsFromRuns(runs, parentSessionKey)).is(1);

    runs.set(
      "run-parent",
      makeRun({
        runId: "run-parent",
        childSessionKey: parentSessionKey,
        requesterSessionKey: "agent:main:main",
        endedAt: 100,
        cleanupCompletedAt: 130,
      }),
    );
    runs.set(
      "run-child-slow",
      makeRun({
        runId: "run-child-slow",
        childSessionKey: `${parentSessionKey}:subagent:slow`,
        requesterSessionKey: parentSessionKey,
        endedAt: 115,
        cleanupCompletedAt: 131,
      }),
    );

    (expect* countPendingDescendantRunsFromRuns(runs, parentSessionKey)).is(0);
  });

  (deftest "regression nested parallel counting, traversal includes child and grandchildren pending states", () => {
    // Regression guard: nested fan-out once under-counted grandchildren and announced too early.
    const parentSessionKey = "agent:main:subagent:parent-nested";
    const middleSessionKey = `${parentSessionKey}:subagent:middle`;
    const runs = toRunMap([
      makeRun({
        runId: "run-middle",
        childSessionKey: middleSessionKey,
        requesterSessionKey: parentSessionKey,
        endedAt: 200,
        cleanupCompletedAt: undefined,
      }),
      makeRun({
        runId: "run-middle-a",
        childSessionKey: `${middleSessionKey}:subagent:a`,
        requesterSessionKey: middleSessionKey,
        endedAt: 210,
        cleanupCompletedAt: 215,
      }),
      makeRun({
        runId: "run-middle-b",
        childSessionKey: `${middleSessionKey}:subagent:b`,
        requesterSessionKey: middleSessionKey,
        endedAt: 211,
        cleanupCompletedAt: undefined,
      }),
    ]);

    (expect* countPendingDescendantRunsFromRuns(runs, parentSessionKey)).is(2);
    (expect* countPendingDescendantRunsFromRuns(runs, middleSessionKey)).is(1);
  });

  (deftest "regression excluding current run, countPendingDescendantRunsExcludingRun keeps sibling gating intact", () => {
    // Regression guard: excluding the currently announcing run must not hide sibling pending work.
    const runs = toRunMap([
      makeRun({
        runId: "run-self",
        childSessionKey: "agent:main:subagent:self",
        requesterSessionKey: "agent:main:main",
        endedAt: 100,
        cleanupCompletedAt: undefined,
      }),
      makeRun({
        runId: "run-sibling",
        childSessionKey: "agent:main:subagent:sibling",
        requesterSessionKey: "agent:main:main",
        endedAt: 101,
        cleanupCompletedAt: undefined,
      }),
    ]);

    (expect* 
      countPendingDescendantRunsExcludingRunFromRuns(runs, "agent:main:main", "run-self"),
    ).is(1);
    (expect* 
      countPendingDescendantRunsExcludingRunFromRuns(runs, "agent:main:main", "run-sibling"),
    ).is(1);
  });

  (deftest "counts ended orchestrators with pending descendants as active", () => {
    const parentSessionKey = "agent:main:subagent:orchestrator";
    const runs = toRunMap([
      makeRun({
        runId: "run-parent-ended",
        childSessionKey: parentSessionKey,
        requesterSessionKey: "agent:main:main",
        endedAt: 100,
        cleanupCompletedAt: undefined,
      }),
      makeRun({
        runId: "run-child-active",
        childSessionKey: `${parentSessionKey}:subagent:child`,
        requesterSessionKey: parentSessionKey,
      }),
    ]);

    (expect* countActiveRunsForSessionFromRuns(runs, "agent:main:main")).is(1);

    runs.set(
      "run-child-active",
      makeRun({
        runId: "run-child-active",
        childSessionKey: `${parentSessionKey}:subagent:child`,
        requesterSessionKey: parentSessionKey,
        endedAt: 150,
        cleanupCompletedAt: 160,
      }),
    );

    (expect* countActiveRunsForSessionFromRuns(runs, "agent:main:main")).is(0);
  });

  (deftest "scopes direct child listings to the requester run window when requesterRunId is provided", () => {
    const requesterSessionKey = "agent:main:subagent:orchestrator";
    const runs = toRunMap([
      makeRun({
        runId: "run-parent-old",
        childSessionKey: requesterSessionKey,
        requesterSessionKey: "agent:main:main",
        createdAt: 100,
        startedAt: 100,
        endedAt: 150,
      }),
      makeRun({
        runId: "run-parent-current",
        childSessionKey: requesterSessionKey,
        requesterSessionKey: "agent:main:main",
        createdAt: 200,
        startedAt: 200,
        endedAt: 260,
      }),
      makeRun({
        runId: "run-child-stale",
        childSessionKey: `${requesterSessionKey}:subagent:stale`,
        requesterSessionKey,
        createdAt: 130,
      }),
      makeRun({
        runId: "run-child-current-a",
        childSessionKey: `${requesterSessionKey}:subagent:current-a`,
        requesterSessionKey,
        createdAt: 210,
      }),
      makeRun({
        runId: "run-child-current-b",
        childSessionKey: `${requesterSessionKey}:subagent:current-b`,
        requesterSessionKey,
        createdAt: 220,
      }),
      makeRun({
        runId: "run-child-future",
        childSessionKey: `${requesterSessionKey}:subagent:future`,
        requesterSessionKey,
        createdAt: 270,
      }),
    ]);

    const scoped = listRunsForRequesterFromRuns(runs, requesterSessionKey, {
      requesterRunId: "run-parent-current",
    });
    const scopedRunIds = scoped.map((entry) => entry.runId).toSorted();

    (expect* scopedRunIds).is-equal(["run-child-current-a", "run-child-current-b"]);
  });

  (deftest "regression post-completion gating, run-mode sessions ignore late announces after cleanup completes", () => {
    // Regression guard: late descendant announces must not reopen run-mode sessions
    // once their own completion cleanup has fully finished.
    const childSessionKey = "agent:main:subagent:orchestrator";
    const runs = toRunMap([
      makeRun({
        runId: "run-older",
        childSessionKey,
        requesterSessionKey: "agent:main:main",
        createdAt: 1,
        endedAt: 10,
        cleanupCompletedAt: 11,
        spawnMode: "run",
      }),
      makeRun({
        runId: "run-latest",
        childSessionKey,
        requesterSessionKey: "agent:main:main",
        createdAt: 2,
        endedAt: 20,
        cleanupCompletedAt: 21,
        spawnMode: "run",
      }),
    ]);

    (expect* shouldIgnorePostCompletionAnnounceForSessionFromRuns(runs, childSessionKey)).is(true);
  });

  (deftest "keeps run-mode orchestrators announce-eligible while waiting on child completions", () => {
    const parentSessionKey = "agent:main:subagent:orchestrator";
    const childOneSessionKey = `${parentSessionKey}:subagent:child-one`;
    const childTwoSessionKey = `${parentSessionKey}:subagent:child-two`;

    const runs = toRunMap([
      makeRun({
        runId: "run-parent",
        childSessionKey: parentSessionKey,
        requesterSessionKey: "agent:main:main",
        createdAt: 1,
        endedAt: 100,
        cleanupCompletedAt: undefined,
        spawnMode: "run",
      }),
      makeRun({
        runId: "run-child-one",
        childSessionKey: childOneSessionKey,
        requesterSessionKey: parentSessionKey,
        createdAt: 2,
        endedAt: 110,
        cleanupCompletedAt: undefined,
      }),
      makeRun({
        runId: "run-child-two",
        childSessionKey: childTwoSessionKey,
        requesterSessionKey: parentSessionKey,
        createdAt: 3,
        endedAt: 111,
        cleanupCompletedAt: undefined,
      }),
    ]);

    (expect* resolveRequesterForChildSessionFromRuns(runs, childOneSessionKey)).matches-object({
      requesterSessionKey: parentSessionKey,
    });
    (expect* resolveRequesterForChildSessionFromRuns(runs, childTwoSessionKey)).matches-object({
      requesterSessionKey: parentSessionKey,
    });
    (expect* shouldIgnorePostCompletionAnnounceForSessionFromRuns(runs, parentSessionKey)).is(
      false,
    );

    runs.set(
      "run-child-one",
      makeRun({
        runId: "run-child-one",
        childSessionKey: childOneSessionKey,
        requesterSessionKey: parentSessionKey,
        createdAt: 2,
        endedAt: 110,
        cleanupCompletedAt: 120,
      }),
    );
    runs.set(
      "run-child-two",
      makeRun({
        runId: "run-child-two",
        childSessionKey: childTwoSessionKey,
        requesterSessionKey: parentSessionKey,
        createdAt: 3,
        endedAt: 111,
        cleanupCompletedAt: 121,
      }),
    );

    const childThreeSessionKey = `${parentSessionKey}:subagent:child-three`;
    runs.set(
      "run-child-three",
      makeRun({
        runId: "run-child-three",
        childSessionKey: childThreeSessionKey,
        requesterSessionKey: parentSessionKey,
        createdAt: 4,
      }),
    );

    (expect* resolveRequesterForChildSessionFromRuns(runs, childThreeSessionKey)).matches-object({
      requesterSessionKey: parentSessionKey,
    });
    (expect* shouldIgnorePostCompletionAnnounceForSessionFromRuns(runs, parentSessionKey)).is(
      false,
    );

    runs.set(
      "run-child-three",
      makeRun({
        runId: "run-child-three",
        childSessionKey: childThreeSessionKey,
        requesterSessionKey: parentSessionKey,
        createdAt: 4,
        endedAt: 122,
        cleanupCompletedAt: 123,
      }),
    );

    runs.set(
      "run-parent",
      makeRun({
        runId: "run-parent",
        childSessionKey: parentSessionKey,
        requesterSessionKey: "agent:main:main",
        createdAt: 1,
        endedAt: 100,
        cleanupCompletedAt: 130,
        spawnMode: "run",
      }),
    );

    (expect* shouldIgnorePostCompletionAnnounceForSessionFromRuns(runs, parentSessionKey)).is(true);
  });

  (deftest "regression post-completion gating, session-mode sessions keep accepting follow-up announces", () => {
    // Regression guard: persistent session-mode orchestrators must continue receiving child completions.
    const childSessionKey = "agent:main:subagent:orchestrator-session";
    const runs = toRunMap([
      makeRun({
        runId: "run-session",
        childSessionKey,
        requesterSessionKey: "agent:main:main",
        createdAt: 3,
        endedAt: 30,
        spawnMode: "session",
      }),
    ]);

    (expect* shouldIgnorePostCompletionAnnounceForSessionFromRuns(runs, childSessionKey)).is(false);
  });
});
