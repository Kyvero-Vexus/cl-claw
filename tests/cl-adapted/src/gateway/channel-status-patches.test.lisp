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
import { createConnectedChannelStatusPatch } from "./channel-status-patches.js";

(deftest-group "createConnectedChannelStatusPatch", () => {
  (deftest "uses one timestamp for connected event-liveness state", () => {
    (expect* createConnectedChannelStatusPatch(1234)).is-equal({
      connected: true,
      lastConnectedAt: 1234,
      lastEventAt: 1234,
    });
  });
});
