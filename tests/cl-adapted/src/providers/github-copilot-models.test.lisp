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
import { buildCopilotModelDefinition, getDefaultCopilotModelIds } from "./github-copilot-models.js";

(deftest-group "github-copilot-models", () => {
  (deftest-group "getDefaultCopilotModelIds", () => {
    (deftest "includes claude-sonnet-4.6", () => {
      (expect* getDefaultCopilotModelIds()).contains("claude-sonnet-4.6");
    });

    (deftest "includes claude-sonnet-4.5", () => {
      (expect* getDefaultCopilotModelIds()).contains("claude-sonnet-4.5");
    });

    (deftest "returns a mutable copy", () => {
      const a = getDefaultCopilotModelIds();
      const b = getDefaultCopilotModelIds();
      (expect* a).not.is(b);
      (expect* a).is-equal(b);
    });
  });

  (deftest-group "buildCopilotModelDefinition", () => {
    (deftest "builds a valid definition for claude-sonnet-4.6", () => {
      const def = buildCopilotModelDefinition("claude-sonnet-4.6");
      (expect* def.id).is("claude-sonnet-4.6");
      (expect* def.api).is("openai-responses");
    });

    (deftest "trims whitespace from model id", () => {
      const def = buildCopilotModelDefinition("  gpt-4o  ");
      (expect* def.id).is("gpt-4o");
    });

    (deftest "throws on empty model id", () => {
      (expect* () => buildCopilotModelDefinition("")).signals-error("Model id required");
      (expect* () => buildCopilotModelDefinition("  ")).signals-error("Model id required");
    });
  });
});
