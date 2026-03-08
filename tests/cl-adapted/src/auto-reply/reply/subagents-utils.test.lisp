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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { SubagentRunRecord } from "../../agents/subagent-registry.js";
import {
  resolveSubagentLabel,
  resolveSubagentTargetFromRuns,
  sortSubagentRuns,
} from "./subagents-utils.js";

const NOW_MS = 1_700_000_000_000;

function makeRun(overrides: Partial<SubagentRunRecord>): SubagentRunRecord {
  const id = overrides.runId ?? "run-default";
  return {
    runId: id,
    childSessionKey: overrides.childSessionKey ?? `agent:main:subagent:${id}`,
    requesterSessionKey: overrides.requesterSessionKey ?? "agent:main:main",
    requesterDisplayKey: overrides.requesterDisplayKey ?? "main",
    task: overrides.task ?? "default task",
    cleanup: overrides.cleanup ?? "keep",
    createdAt: overrides.createdAt ?? NOW_MS - 2_000,
    ...overrides,
  };
}

function resolveTarget(runs: SubagentRunRecord[], token: string | undefined) {
  return resolveSubagentTargetFromRuns({
    runs,
    token,
    recentWindowMinutes: 30,
    label: (entry) => resolveSubagentLabel(entry),
    errors: {
      missingTarget: "missing",
      invalidIndex: (value) => `invalid:${value}`,
      unknownSession: (value) => `unknown-session:${value}`,
      ambiguousLabel: (value) => `ambiguous-label:${value}`,
      ambiguousLabelPrefix: (value) => `ambiguous-prefix:${value}`,
      ambiguousRunIdPrefix: (value) => `ambiguous-run:${value}`,
      unknownTarget: (value) => `unknown:${value}`,
    },
  });
}

(deftest-group "subagents utils", () => {
  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "resolves subagent label with fallback", () => {
    (expect* resolveSubagentLabel(makeRun({ label: "  runner " }))).is("runner");
    (expect* resolveSubagentLabel(makeRun({ label: " ", task: "  task value " }))).is("task value");
    (expect* resolveSubagentLabel(makeRun({ label: " ", task: " " }), "fallback")).is("fallback");
  });

  (deftest "sorts by startedAt then createdAt descending", () => {
    const sorted = sortSubagentRuns([
      makeRun({ runId: "a", createdAt: 10 }),
      makeRun({ runId: "b", startedAt: 15, createdAt: 5 }),
      makeRun({ runId: "c", startedAt: 12, createdAt: 20 }),
    ]);
    (expect* sorted.map((entry) => entry.runId)).is-equal(["b", "c", "a"]);
  });

  (deftest "selects last from sorted runs", () => {
    const runs = [
      makeRun({ runId: "old", createdAt: NOW_MS - 2_000 }),
      makeRun({ runId: "new", createdAt: NOW_MS - 500 }),
    ];
    const resolved = resolveTarget(runs, " last ");
    (expect* resolved.entry?.runId).is("new");
  });

  (deftest "resolves numeric index from running then recent finished order", () => {
    mock:spyOn(Date, "now").mockReturnValue(NOW_MS);
    const runs = [
      makeRun({
        runId: "running",
        label: "running",
        createdAt: NOW_MS - 8_000,
      }),
      makeRun({
        runId: "recent-finished",
        label: "recent",
        createdAt: NOW_MS - 6_000,
        endedAt: NOW_MS - 60_000,
      }),
      makeRun({
        runId: "old-finished",
        label: "old",
        createdAt: NOW_MS - 7_000,
        endedAt: NOW_MS - 2 * 60 * 60 * 1_000,
      }),
    ];

    (expect* resolveTarget(runs, "1").entry?.runId).is("running");
    (expect* resolveTarget(runs, "2").entry?.runId).is("recent-finished");
    (expect* resolveTarget(runs, "3").error).is("invalid:3");
  });

  (deftest "resolves session key target and unknown session errors", () => {
    const run = makeRun({ runId: "abc123", childSessionKey: "agent:beta:subagent:xyz" });
    (expect* resolveTarget([run], "agent:beta:subagent:xyz").entry?.runId).is("abc123");
    (expect* resolveTarget([run], "agent:beta:subagent:missing").error).is(
      "unknown-session:agent:beta:subagent:missing",
    );
  });

  (deftest "resolves exact label, prefix, run-id prefix and ambiguity errors", () => {
    const runs = [
      makeRun({ runId: "run-alpha-1", label: "Alpha Core" }),
      makeRun({ runId: "run-alpha-2", label: "Alpha Orbit" }),
      makeRun({ runId: "run-beta-1", label: "Beta Worker" }),
    ];

    (expect* resolveTarget(runs, "beta worker").entry?.runId).is("run-beta-1");
    (expect* resolveTarget(runs, "beta").entry?.runId).is("run-beta-1");
    (expect* resolveTarget(runs, "run-beta").entry?.runId).is("run-beta-1");

    (expect* resolveTarget(runs, "alpha core").entry?.runId).is("run-alpha-1");
    (expect* resolveTarget(runs, "alpha").error).is("ambiguous-prefix:alpha");
    (expect* resolveTarget(runs, "run-alpha").error).is("ambiguous-run:run-alpha");
    (expect* resolveTarget(runs, "missing").error).is("unknown:missing");
    (expect* resolveTarget(runs, undefined).error).is("missing");
  });

  (deftest "returns ambiguous exact label error before prefix/run id matching", () => {
    const runs = [
      makeRun({ runId: "run-a", label: "dup" }),
      makeRun({ runId: "run-b", label: "dup" }),
    ];
    (expect* resolveTarget(runs, "dup").error).is("ambiguous-label:dup");
  });
});
