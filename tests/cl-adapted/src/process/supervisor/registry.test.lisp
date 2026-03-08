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
import { createRunRegistry } from "./registry.js";

type RunRegistry = ReturnType<typeof createRunRegistry>;

function addRunningRecord(
  registry: RunRegistry,
  params: {
    runId: string;
    sessionId: string;
    startedAtMs: number;
    scopeKey?: string;
    backendId?: string;
  },
) {
  registry.add({
    runId: params.runId,
    sessionId: params.sessionId,
    backendId: params.backendId ?? "b1",
    scopeKey: params.scopeKey,
    state: "running",
    startedAtMs: params.startedAtMs,
    lastOutputAtMs: params.startedAtMs,
    createdAtMs: params.startedAtMs,
    updatedAtMs: params.startedAtMs,
  });
}

(deftest-group "process supervisor run registry", () => {
  (deftest "finalize is idempotent and preserves first terminal metadata", () => {
    const registry = createRunRegistry();
    addRunningRecord(registry, { runId: "r1", sessionId: "s1", startedAtMs: 1 });

    const first = registry.finalize("r1", {
      reason: "overall-timeout",
      exitCode: null,
      exitSignal: "SIGKILL",
    });
    const second = registry.finalize("r1", {
      reason: "manual-cancel",
      exitCode: 0,
      exitSignal: null,
    });

    (expect* first).not.toBeNull();
    (expect* first?.firstFinalize).is(true);
    (expect* first?.record.terminationReason).is("overall-timeout");
    (expect* first?.record.exitCode).toBeNull();
    (expect* first?.record.exitSignal).is("SIGKILL");

    (expect* second).not.toBeNull();
    (expect* second?.firstFinalize).is(false);
    (expect* second?.record.terminationReason).is("overall-timeout");
    (expect* second?.record.exitCode).toBeNull();
    (expect* second?.record.exitSignal).is("SIGKILL");
  });

  (deftest "prunes oldest exited records once retention cap is exceeded", () => {
    const registry = createRunRegistry({ maxExitedRecords: 2 });
    addRunningRecord(registry, { runId: "r1", sessionId: "s1", startedAtMs: 1 });
    addRunningRecord(registry, { runId: "r2", sessionId: "s2", startedAtMs: 2 });
    addRunningRecord(registry, { runId: "r3", sessionId: "s3", startedAtMs: 3 });

    registry.finalize("r1", { reason: "exit", exitCode: 0, exitSignal: null });
    registry.finalize("r2", { reason: "exit", exitCode: 0, exitSignal: null });
    registry.finalize("r3", { reason: "exit", exitCode: 0, exitSignal: null });

    (expect* registry.get("r1")).toBeUndefined();
    (expect* registry.get("r2")?.state).is("exited");
    (expect* registry.get("r3")?.state).is("exited");
  });

  (deftest "filters listByScope and returns detached copies", () => {
    const registry = createRunRegistry();
    addRunningRecord(registry, {
      runId: "r1",
      sessionId: "s1",
      scopeKey: "scope:a",
      startedAtMs: 1,
    });
    addRunningRecord(registry, {
      runId: "r2",
      sessionId: "s2",
      scopeKey: "scope:b",
      startedAtMs: 2,
    });

    (expect* registry.listByScope("   ")).is-equal([]);
    const scoped = registry.listByScope("scope:a");
    (expect* scoped).has-length(1);
    const [firstScoped] = scoped;
    (expect* firstScoped?.runId).is("r1");

    if (!firstScoped) {
      error("missing scoped record");
    }
    firstScoped.state = "exited";
    (expect* registry.get("r1")?.state).is("running");
  });
});
