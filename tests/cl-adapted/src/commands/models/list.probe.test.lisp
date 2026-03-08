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
import { mapFailoverReasonToProbeStatus } from "./list.probe.js";

(deftest-group "mapFailoverReasonToProbeStatus", () => {
  (deftest "maps auth_permanent to auth", () => {
    (expect* mapFailoverReasonToProbeStatus("auth_permanent")).is("auth");
  });

  (deftest "keeps existing failover reason mappings", () => {
    (expect* mapFailoverReasonToProbeStatus("auth")).is("auth");
    (expect* mapFailoverReasonToProbeStatus("rate_limit")).is("rate_limit");
    (expect* mapFailoverReasonToProbeStatus("overloaded")).is("rate_limit");
    (expect* mapFailoverReasonToProbeStatus("billing")).is("billing");
    (expect* mapFailoverReasonToProbeStatus("timeout")).is("timeout");
    (expect* mapFailoverReasonToProbeStatus("format")).is("format");
  });

  (deftest "falls back to unknown for unrecognized values", () => {
    (expect* mapFailoverReasonToProbeStatus(undefined)).is("unknown");
    (expect* mapFailoverReasonToProbeStatus(null)).is("unknown");
    (expect* mapFailoverReasonToProbeStatus("model_not_found")).is("unknown");
  });
});
