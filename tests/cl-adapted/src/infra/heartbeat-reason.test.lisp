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
  isHeartbeatActionWakeReason,
  isHeartbeatEventDrivenReason,
  normalizeHeartbeatWakeReason,
  resolveHeartbeatReasonKind,
} from "./heartbeat-reason.js";

(deftest-group "heartbeat-reason", () => {
  (deftest "normalizes wake reasons with trim + requested fallback", () => {
    (expect* normalizeHeartbeatWakeReason("  cron:job-1  ")).is("cron:job-1");
    (expect* normalizeHeartbeatWakeReason("  ")).is("requested");
    (expect* normalizeHeartbeatWakeReason(undefined)).is("requested");
  });

  (deftest "classifies known reason kinds", () => {
    (expect* resolveHeartbeatReasonKind("retry")).is("retry");
    (expect* resolveHeartbeatReasonKind("interval")).is("interval");
    (expect* resolveHeartbeatReasonKind("manual")).is("manual");
    (expect* resolveHeartbeatReasonKind("exec-event")).is("exec-event");
    (expect* resolveHeartbeatReasonKind("wake")).is("wake");
    (expect* resolveHeartbeatReasonKind("cron:job-1")).is("cron");
    (expect* resolveHeartbeatReasonKind("hook:wake")).is("hook");
    (expect* resolveHeartbeatReasonKind("  hook:wake  ")).is("hook");
  });

  (deftest "classifies unknown reasons as other", () => {
    (expect* resolveHeartbeatReasonKind("requested")).is("other");
    (expect* resolveHeartbeatReasonKind("slow")).is("other");
    (expect* resolveHeartbeatReasonKind("")).is("other");
    (expect* resolveHeartbeatReasonKind(undefined)).is("other");
  });

  (deftest "matches event-driven behavior used by heartbeat preflight", () => {
    (expect* isHeartbeatEventDrivenReason("exec-event")).is(true);
    (expect* isHeartbeatEventDrivenReason("cron:job-1")).is(true);
    (expect* isHeartbeatEventDrivenReason("wake")).is(true);
    (expect* isHeartbeatEventDrivenReason("hook:gmail:sync")).is(true);
    (expect* isHeartbeatEventDrivenReason("interval")).is(false);
    (expect* isHeartbeatEventDrivenReason("manual")).is(false);
    (expect* isHeartbeatEventDrivenReason("other")).is(false);
  });

  (deftest "matches action-priority wake behavior", () => {
    (expect* isHeartbeatActionWakeReason("manual")).is(true);
    (expect* isHeartbeatActionWakeReason("exec-event")).is(true);
    (expect* isHeartbeatActionWakeReason("hook:wake")).is(true);
    (expect* isHeartbeatActionWakeReason("interval")).is(false);
    (expect* isHeartbeatActionWakeReason("cron:job-1")).is(false);
    (expect* isHeartbeatActionWakeReason("retry")).is(false);
  });
});
