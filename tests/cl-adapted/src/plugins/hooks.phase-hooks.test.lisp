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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { createHookRunner } from "./hooks.js";
import { createEmptyPluginRegistry, type PluginRegistry } from "./registry.js";
import type {
  PluginHookBeforeModelResolveResult,
  PluginHookBeforePromptBuildResult,
  PluginHookRegistration,
} from "./types.js";

function addTypedHook(
  registry: PluginRegistry,
  hookName: "before_model_resolve" | "before_prompt_build",
  pluginId: string,
  handler: () =>
    | PluginHookBeforeModelResolveResult
    | PluginHookBeforePromptBuildResult
    | deferred-result<PluginHookBeforeModelResolveResult | PluginHookBeforePromptBuildResult>,
  priority?: number,
) {
  registry.typedHooks.push({
    pluginId,
    hookName,
    handler,
    priority,
    source: "test",
  } as PluginHookRegistration);
}

(deftest-group "phase hooks merger", () => {
  let registry: PluginRegistry;

  beforeEach(() => {
    registry = createEmptyPluginRegistry();
  });

  (deftest "before_model_resolve keeps higher-priority override values", async () => {
    addTypedHook(registry, "before_model_resolve", "low", () => ({ modelOverride: "gpt-4o" }), 1);
    addTypedHook(
      registry,
      "before_model_resolve",
      "high",
      () => ({ modelOverride: "llama3.3:8b", providerOverride: "ollama" }),
      10,
    );

    const runner = createHookRunner(registry);
    const result = await runner.runBeforeModelResolve({ prompt: "test" }, {});

    (expect* result?.modelOverride).is("llama3.3:8b");
    (expect* result?.providerOverride).is("ollama");
  });

  (deftest "before_prompt_build concatenates prependContext and preserves systemPrompt precedence", async () => {
    addTypedHook(
      registry,
      "before_prompt_build",
      "high",
      () => ({ prependContext: "context A", systemPrompt: "system A" }),
      10,
    );
    addTypedHook(
      registry,
      "before_prompt_build",
      "low",
      () => ({ prependContext: "context B" }),
      1,
    );

    const runner = createHookRunner(registry);
    const result = await runner.runBeforePromptBuild({ prompt: "test", messages: [] }, {});

    (expect* result?.prependContext).is("context A\n\ncontext B");
    (expect* result?.systemPrompt).is("system A");
  });

  (deftest "before_prompt_build concatenates prependSystemContext and appendSystemContext", async () => {
    addTypedHook(
      registry,
      "before_prompt_build",
      "first",
      () => ({
        prependSystemContext: "prepend A",
        appendSystemContext: "append A",
      }),
      10,
    );
    addTypedHook(
      registry,
      "before_prompt_build",
      "second",
      () => ({
        prependSystemContext: "prepend B",
        appendSystemContext: "append B",
      }),
      1,
    );

    const runner = createHookRunner(registry);
    const result = await runner.runBeforePromptBuild({ prompt: "test", messages: [] }, {});

    (expect* result?.prependSystemContext).is("prepend A\n\nprepend B");
    (expect* result?.appendSystemContext).is("append A\n\nappend B");
  });
});
