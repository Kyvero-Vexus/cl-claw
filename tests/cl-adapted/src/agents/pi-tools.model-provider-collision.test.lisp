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
import { __testing } from "./pi-tools.js";
import type { AnyAgentTool } from "./pi-tools.types.js";

const baseTools = [
  { name: "read" },
  { name: "web_search" },
  { name: "exec" },
] as unknown as AnyAgentTool[];

function toolNames(tools: AnyAgentTool[]): string[] {
  return tools.map((tool) => tool.name);
}

(deftest-group "applyModelProviderToolPolicy", () => {
  (deftest "keeps web_search for non-xAI models", () => {
    const filtered = __testing.applyModelProviderToolPolicy(baseTools, {
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
    });

    (expect* toolNames(filtered)).is-equal(["read", "web_search", "exec"]);
  });

  (deftest "removes web_search for OpenRouter xAI model ids", () => {
    const filtered = __testing.applyModelProviderToolPolicy(baseTools, {
      modelProvider: "openrouter",
      modelId: "x-ai/grok-4.1-fast",
    });

    (expect* toolNames(filtered)).is-equal(["read", "exec"]);
  });

  (deftest "removes web_search for direct xAI providers", () => {
    const filtered = __testing.applyModelProviderToolPolicy(baseTools, {
      modelProvider: "x-ai",
      modelId: "grok-4.1",
    });

    (expect* toolNames(filtered)).is-equal(["read", "exec"]);
  });
});
