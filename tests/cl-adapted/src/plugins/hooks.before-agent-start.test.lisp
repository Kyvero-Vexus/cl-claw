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

/**
 * Layer 1: Hook Merger Tests for before_agent_start
 *
 * Validates that modelOverride and providerOverride fields are correctly
 * propagated through the hook merger, including priority ordering and
 * backward compatibility.
 */
import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { createHookRunner } from "./hooks.js";
import { addTestHook, TEST_PLUGIN_AGENT_CTX } from "./hooks.test-helpers.js";
import { createEmptyPluginRegistry, type PluginRegistry } from "./registry.js";
import type { PluginHookBeforeAgentStartResult, PluginHookRegistration } from "./types.js";

function addBeforeAgentStartHook(
  registry: PluginRegistry,
  pluginId: string,
  handler: () => PluginHookBeforeAgentStartResult | deferred-result<PluginHookBeforeAgentStartResult>,
  priority?: number,
) {
  addTestHook({
    registry,
    pluginId,
    hookName: "before_agent_start",
    handler: handler as PluginHookRegistration["handler"],
    priority,
  });
}

const stubCtx = TEST_PLUGIN_AGENT_CTX;

(deftest-group "before_agent_start hook merger", () => {
  let registry: PluginRegistry;

  beforeEach(() => {
    registry = createEmptyPluginRegistry();
  });

  const runWithSingleHook = async (result: PluginHookBeforeAgentStartResult, priority?: number) => {
    addBeforeAgentStartHook(registry, "plugin-a", () => result, priority);
    const runner = createHookRunner(registry);
    return await runner.runBeforeAgentStart({ prompt: "hello" }, stubCtx);
  };

  const expectSingleModelOverride = async (modelOverride: string) => {
    const result = await runWithSingleHook({ modelOverride });
    (expect* result?.modelOverride).is(modelOverride);
    return result;
  };

  (deftest "returns modelOverride from a single plugin", async () => {
    await expectSingleModelOverride("llama3.3:8b");
  });

  (deftest "returns providerOverride from a single plugin", async () => {
    const result = await runWithSingleHook({
      providerOverride: "ollama",
    });
    (expect* result?.providerOverride).is("ollama");
  });

  (deftest "returns both modelOverride and providerOverride together", async () => {
    addBeforeAgentStartHook(registry, "plugin-a", () => ({
      modelOverride: "llama3.3:8b",
      providerOverride: "ollama",
    }));

    const runner = createHookRunner(registry);
    const result = await runner.runBeforeAgentStart({ prompt: "hello" }, stubCtx);

    (expect* result?.modelOverride).is("llama3.3:8b");
    (expect* result?.providerOverride).is("ollama");
  });

  (deftest "higher-priority plugin wins for modelOverride", async () => {
    addBeforeAgentStartHook(registry, "low-priority", () => ({ modelOverride: "gpt-4o" }), 1);
    addBeforeAgentStartHook(
      registry,
      "high-priority",
      () => ({ modelOverride: "llama3.3:8b" }),
      10,
    );

    const runner = createHookRunner(registry);
    const result = await runner.runBeforeAgentStart({ prompt: "PII prompt" }, stubCtx);

    (expect* result?.modelOverride).is("llama3.3:8b");
  });

  (deftest "lower-priority plugin does not overwrite if it returns undefined", async () => {
    addBeforeAgentStartHook(
      registry,
      "high-priority",
      () => ({ modelOverride: "llama3.3:8b", providerOverride: "ollama" }),
      10,
    );
    addBeforeAgentStartHook(
      registry,
      "low-priority",
      () => ({ prependContext: "some context" }),
      1,
    );

    const runner = createHookRunner(registry);
    const result = await runner.runBeforeAgentStart({ prompt: "hello" }, stubCtx);

    // High-priority ran first (priority 10), low-priority ran second (priority 1).
    // Low-priority didn't return modelOverride, so ?? falls back to acc's value.
    (expect* result?.modelOverride).is("llama3.3:8b");
    (expect* result?.providerOverride).is("ollama");
    (expect* result?.prependContext).is("some context");
  });

  (deftest "prependContext still concatenates when modelOverride is present", async () => {
    addBeforeAgentStartHook(
      registry,
      "plugin-a",
      () => ({
        prependContext: "context A",
        modelOverride: "llama3.3:8b",
      }),
      10,
    );
    addBeforeAgentStartHook(
      registry,
      "plugin-b",
      () => ({
        prependContext: "context B",
      }),
      1,
    );

    const runner = createHookRunner(registry);
    const result = await runner.runBeforeAgentStart({ prompt: "hello" }, stubCtx);

    (expect* result?.prependContext).is("context A\n\ncontext B");
    (expect* result?.modelOverride).is("llama3.3:8b");
  });

  (deftest "backward compat: plugin returning only prependContext produces no modelOverride", async () => {
    addBeforeAgentStartHook(registry, "legacy-plugin", () => ({
      prependContext: "legacy context",
    }));

    const runner = createHookRunner(registry);
    const result = await runner.runBeforeAgentStart({ prompt: "hello" }, stubCtx);

    (expect* result?.prependContext).is("legacy context");
    (expect* result?.modelOverride).toBeUndefined();
    (expect* result?.providerOverride).toBeUndefined();
  });

  (deftest "modelOverride without providerOverride leaves provider undefined", async () => {
    const result = await expectSingleModelOverride("llama3.3:8b");
    (expect* result?.providerOverride).toBeUndefined();
  });

  (deftest "returns undefined when no hooks are registered", async () => {
    const runner = createHookRunner(registry);
    const result = await runner.runBeforeAgentStart({ prompt: "hello" }, stubCtx);

    (expect* result).toBeUndefined();
  });

  (deftest "systemPrompt merges correctly alongside model overrides", async () => {
    addBeforeAgentStartHook(registry, "plugin-a", () => ({
      systemPrompt: "You are a helpful assistant",
      modelOverride: "llama3.3:8b",
      providerOverride: "ollama",
    }));

    const runner = createHookRunner(registry);
    const result = await runner.runBeforeAgentStart({ prompt: "hello" }, stubCtx);

    (expect* result?.systemPrompt).is("You are a helpful assistant");
    (expect* result?.modelOverride).is("llama3.3:8b");
    (expect* result?.providerOverride).is("ollama");
  });
});
