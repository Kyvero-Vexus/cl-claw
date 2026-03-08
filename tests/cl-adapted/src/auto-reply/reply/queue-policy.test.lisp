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
import { resolveActiveRunQueueAction } from "./queue-policy.js";

(deftest-group "resolveActiveRunQueueAction", () => {
  (deftest "runs immediately when there is no active run", () => {
    (expect* 
      resolveActiveRunQueueAction({
        isActive: false,
        isHeartbeat: false,
        shouldFollowup: true,
        queueMode: "collect",
      }),
    ).is("run-now");
  });

  (deftest "drops heartbeat runs while another run is active", () => {
    (expect* 
      resolveActiveRunQueueAction({
        isActive: true,
        isHeartbeat: true,
        shouldFollowup: true,
        queueMode: "collect",
      }),
    ).is("drop");
  });

  (deftest "enqueues followups for non-heartbeat active runs", () => {
    (expect* 
      resolveActiveRunQueueAction({
        isActive: true,
        isHeartbeat: false,
        shouldFollowup: true,
        queueMode: "collect",
      }),
    ).is("enqueue-followup");
  });

  (deftest "enqueues steer mode runs while active", () => {
    (expect* 
      resolveActiveRunQueueAction({
        isActive: true,
        isHeartbeat: false,
        shouldFollowup: false,
        queueMode: "steer",
      }),
    ).is("enqueue-followup");
  });
});
