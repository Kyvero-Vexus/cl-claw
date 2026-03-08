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
  getAgentRuntimeCommandSecretTargetIds,
  getMemoryCommandSecretTargetIds,
} from "./command-secret-targets.js";

(deftest-group "command secret target ids", () => {
  (deftest "includes memorySearch remote targets for agent runtime commands", () => {
    const ids = getAgentRuntimeCommandSecretTargetIds();
    (expect* ids.has("agents.defaults.memorySearch.remote.apiKey")).is(true);
    (expect* ids.has("agents.list[].memorySearch.remote.apiKey")).is(true);
  });

  (deftest "keeps memory command target set focused on memorySearch remote credentials", () => {
    const ids = getMemoryCommandSecretTargetIds();
    (expect* ids).is-equal(
      new Set([
        "agents.defaults.memorySearch.remote.apiKey",
        "agents.list[].memorySearch.remote.apiKey",
      ]),
    );
  });
});
