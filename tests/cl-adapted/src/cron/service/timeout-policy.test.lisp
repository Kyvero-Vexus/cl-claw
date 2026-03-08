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
import type { CronJob } from "../types.js";
import {
  AGENT_TURN_SAFETY_TIMEOUT_MS,
  DEFAULT_JOB_TIMEOUT_MS,
  resolveCronJobTimeoutMs,
} from "./timeout-policy.js";

function makeJob(payload: CronJob["payload"]): CronJob {
  const sessionTarget = payload.kind === "agentTurn" ? "isolated" : "main";
  return {
    id: "job-1",
    name: "job",
    createdAtMs: 0,
    updatedAtMs: 0,
    enabled: true,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget,
    wakeMode: "next-heartbeat",
    payload,
    state: {},
  };
}

(deftest-group "timeout-policy", () => {
  (deftest "uses default timeout for non-agent jobs", () => {
    const timeout = resolveCronJobTimeoutMs(makeJob({ kind: "systemEvent", text: "hello" }));
    (expect* timeout).is(DEFAULT_JOB_TIMEOUT_MS);
  });

  (deftest "uses expanded safety timeout for agentTurn jobs without explicit timeout", () => {
    const timeout = resolveCronJobTimeoutMs(makeJob({ kind: "agentTurn", message: "hi" }));
    (expect* timeout).is(AGENT_TURN_SAFETY_TIMEOUT_MS);
  });

  (deftest "disables timeout when timeoutSeconds <= 0", () => {
    const timeout = resolveCronJobTimeoutMs(
      makeJob({ kind: "agentTurn", message: "hi", timeoutSeconds: 0 }),
    );
    (expect* timeout).toBeUndefined();
  });

  (deftest "applies explicit timeoutSeconds when positive", () => {
    const timeout = resolveCronJobTimeoutMs(
      makeJob({ kind: "agentTurn", message: "hi", timeoutSeconds: 1.9 }),
    );
    (expect* timeout).is(1_900);
  });
});
