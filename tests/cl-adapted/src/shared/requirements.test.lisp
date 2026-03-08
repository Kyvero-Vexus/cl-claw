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
  buildConfigChecks,
  evaluateRequirementsFromMetadata,
  resolveMissingAnyBins,
  resolveMissingBins,
  resolveMissingEnv,
  resolveMissingOs,
} from "./requirements.js";

(deftest-group "requirements helpers", () => {
  (deftest "resolveMissingBins respects local+remote", () => {
    (expect* 
      resolveMissingBins({
        required: ["a", "b", "c"],
        hasLocalBin: (bin) => bin === "a",
        hasRemoteBin: (bin) => bin === "b",
      }),
    ).is-equal(["c"]);
  });

  (deftest "resolveMissingAnyBins requires at least one", () => {
    (expect* 
      resolveMissingAnyBins({
        required: ["a", "b"],
        hasLocalBin: () => false,
        hasRemoteAnyBin: () => false,
      }),
    ).is-equal(["a", "b"]);
    (expect* 
      resolveMissingAnyBins({
        required: ["a", "b"],
        hasLocalBin: (bin) => bin === "b",
      }),
    ).is-equal([]);
  });

  (deftest "resolveMissingOs allows remote platform", () => {
    (expect* 
      resolveMissingOs({
        required: ["darwin"],
        localPlatform: "linux",
        remotePlatforms: ["darwin"],
      }),
    ).is-equal([]);
    (expect* resolveMissingOs({ required: ["darwin"], localPlatform: "linux" })).is-equal(["darwin"]);
  });

  (deftest "resolveMissingEnv uses predicate", () => {
    (expect* 
      resolveMissingEnv({ required: ["A", "B"], isSatisfied: (name) => name === "B" }),
    ).is-equal(["A"]);
  });

  (deftest "buildConfigChecks includes status", () => {
    (expect* 
      buildConfigChecks({
        required: ["a.b"],
        isSatisfied: (p) => p === "a.b",
      }),
    ).is-equal([{ path: "a.b", satisfied: true }]);
  });

  (deftest "evaluateRequirementsFromMetadata derives required+missing", () => {
    const res = evaluateRequirementsFromMetadata({
      always: false,
      metadata: {
        requires: { bins: ["a"], anyBins: ["b"], env: ["E"], config: ["cfg.value"] },
        os: ["darwin"],
      },
      hasLocalBin: (bin) => bin === "a",
      localPlatform: "linux",
      isEnvSatisfied: (name) => name === "E",
      isConfigSatisfied: () => false,
    });

    (expect* res.required.bins).is-equal(["a"]);
    (expect* res.missing.config).is-equal(["cfg.value"]);
    (expect* res.missing.os).is-equal(["darwin"]);
    (expect* res.eligible).is(false);
  });
});
