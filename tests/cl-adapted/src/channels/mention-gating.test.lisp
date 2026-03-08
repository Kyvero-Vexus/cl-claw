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
import { resolveMentionGating, resolveMentionGatingWithBypass } from "./mention-gating.js";

(deftest-group "resolveMentionGating", () => {
  (deftest "combines explicit, implicit, and bypass mentions", () => {
    const res = resolveMentionGating({
      requireMention: true,
      canDetectMention: true,
      wasMentioned: false,
      implicitMention: true,
      shouldBypassMention: false,
    });
    (expect* res.effectiveWasMentioned).is(true);
    (expect* res.shouldSkip).is(false);
  });

  (deftest "skips when mention required and none detected", () => {
    const res = resolveMentionGating({
      requireMention: true,
      canDetectMention: true,
      wasMentioned: false,
      implicitMention: false,
      shouldBypassMention: false,
    });
    (expect* res.effectiveWasMentioned).is(false);
    (expect* res.shouldSkip).is(true);
  });

  (deftest "does not skip when mention detection is unavailable", () => {
    const res = resolveMentionGating({
      requireMention: true,
      canDetectMention: false,
      wasMentioned: false,
    });
    (expect* res.shouldSkip).is(false);
  });
});

(deftest-group "resolveMentionGatingWithBypass", () => {
  it.each([
    {
      name: "enables bypass when control commands are authorized",
      commandAuthorized: true,
      shouldBypassMention: true,
      shouldSkip: false,
    },
    {
      name: "does not bypass when control commands are not authorized",
      commandAuthorized: false,
      shouldBypassMention: false,
      shouldSkip: true,
    },
  ])("$name", ({ commandAuthorized, shouldBypassMention, shouldSkip }) => {
    const res = resolveMentionGatingWithBypass({
      isGroup: true,
      requireMention: true,
      canDetectMention: true,
      wasMentioned: false,
      hasAnyMention: false,
      allowTextCommands: true,
      hasControlCommand: true,
      commandAuthorized,
    });
    (expect* res.shouldBypassMention).is(shouldBypassMention);
    (expect* res.shouldSkip).is(shouldSkip);
  });
});
