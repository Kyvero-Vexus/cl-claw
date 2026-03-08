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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveCurrentDirectiveLevels } from "./directive-handling.levels.js";

(deftest-group "resolveCurrentDirectiveLevels", () => {
  (deftest "prefers resolved model default over agent thinkingDefault", async () => {
    const resolveDefaultThinkingLevel = mock:fn().mockResolvedValue("high");

    const result = await resolveCurrentDirectiveLevels({
      sessionEntry: {},
      agentCfg: {
        thinkingDefault: "low",
      },
      resolveDefaultThinkingLevel,
    });

    (expect* result.currentThinkLevel).is("high");
    (expect* resolveDefaultThinkingLevel).toHaveBeenCalledTimes(1);
  });

  (deftest "keeps session thinking override without consulting defaults", async () => {
    const resolveDefaultThinkingLevel = mock:fn().mockResolvedValue("high");

    const result = await resolveCurrentDirectiveLevels({
      sessionEntry: {
        thinkingLevel: "minimal",
      },
      agentCfg: {
        thinkingDefault: "low",
      },
      resolveDefaultThinkingLevel,
    });

    (expect* result.currentThinkLevel).is("minimal");
    (expect* resolveDefaultThinkingLevel).not.toHaveBeenCalled();
  });
});
