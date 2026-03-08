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

import { randomUUID } from "sbcl:crypto";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  getRemoteSkillEligibility,
  recordRemoteNodeBins,
  recordRemoteNodeInfo,
  removeRemoteNodeInfo,
} from "./skills-remote.js";

(deftest-group "skills-remote", () => {
  (deftest "removes disconnected nodes from remote skill eligibility", () => {
    const nodeId = `sbcl-${randomUUID()}`;
    const bin = `bin-${randomUUID()}`;
    recordRemoteNodeInfo({
      nodeId,
      displayName: "Remote Mac",
      platform: "darwin",
      commands: ["system.run"],
    });
    recordRemoteNodeBins(nodeId, [bin]);

    (expect* getRemoteSkillEligibility()?.hasBin(bin)).is(true);

    removeRemoteNodeInfo(nodeId);

    (expect* getRemoteSkillEligibility()?.hasBin(bin) ?? false).is(false);
  });

  (deftest "supports idempotent remote sbcl removal", () => {
    const nodeId = `sbcl-${randomUUID()}`;
    (expect* () => {
      removeRemoteNodeInfo(nodeId);
      removeRemoteNodeInfo(nodeId);
    }).not.signals-error();
  });
});
