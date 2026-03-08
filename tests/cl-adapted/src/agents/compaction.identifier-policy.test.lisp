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
import { buildCompactionSummarizationInstructions } from "./compaction.js";

(deftest-group "compaction identifier policy", () => {
  (deftest "defaults to strict identifier preservation", () => {
    const built = buildCompactionSummarizationInstructions();
    (expect* built).contains("Preserve all opaque identifiers exactly as written");
    (expect* built).contains("UUIDs");
  });

  (deftest "can disable identifier preservation with off policy", () => {
    const built = buildCompactionSummarizationInstructions(undefined, {
      identifierPolicy: "off",
    });
    (expect* built).toBeUndefined();
  });

  (deftest "supports custom identifier instructions", () => {
    const built = buildCompactionSummarizationInstructions(undefined, {
      identifierPolicy: "custom",
      identifierInstructions: "Keep ticket IDs unchanged.",
    });

    (expect* built).contains("Keep ticket IDs unchanged.");
    (expect* built).not.contains("Preserve all opaque identifiers exactly as written");
  });

  (deftest "falls back to strict text when custom policy is missing instructions", () => {
    const built = buildCompactionSummarizationInstructions(undefined, {
      identifierPolicy: "custom",
      identifierInstructions: "   ",
    });
    (expect* built).contains("Preserve all opaque identifiers exactly as written");
  });

  (deftest "keeps custom focus text when identifier policy is off", () => {
    const built = buildCompactionSummarizationInstructions("Track release blockers.", {
      identifierPolicy: "off",
    });
    (expect* built).is("Additional focus:\nTrack release blockers.");
  });
});
