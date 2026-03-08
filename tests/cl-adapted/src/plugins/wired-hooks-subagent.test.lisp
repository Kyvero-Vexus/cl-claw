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
 * Test: subagent_spawning, subagent_delivery_target, subagent_spawned & subagent_ended hook wiring
 */
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createHookRunner } from "./hooks.js";
import { createMockPluginRegistry } from "./hooks.test-helpers.js";

(deftest-group "subagent hook runner methods", () => {
  const baseRequester = {
    channel: "discord",
    accountId: "work",
    to: "channel:123",
    threadId: "456",
  };

  const baseSubagentCtx = {
    runId: "run-1",
    childSessionKey: "agent:main:subagent:child",
    requesterSessionKey: "agent:main:main",
  };

  (deftest "runSubagentSpawning invokes registered subagent_spawning hooks", async () => {
    const handler = mock:fn(async () => ({ status: "ok", threadBindingReady: true as const }));
    const registry = createMockPluginRegistry([{ hookName: "subagent_spawning", handler }]);
    const runner = createHookRunner(registry);
    const event = {
      childSessionKey: "agent:main:subagent:child",
      agentId: "main",
      label: "research",
      mode: "session" as const,
      requester: baseRequester,
      threadRequested: true,
    };
    const ctx = {
      childSessionKey: "agent:main:subagent:child",
      requesterSessionKey: "agent:main:main",
    };

    const result = await runner.runSubagentSpawning(event, ctx);

    (expect* handler).toHaveBeenCalledWith(event, ctx);
    (expect* result).matches-object({ status: "ok", threadBindingReady: true });
  });

  (deftest "runSubagentSpawned invokes registered subagent_spawned hooks", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "subagent_spawned", handler }]);
    const runner = createHookRunner(registry);
    const event = {
      runId: "run-1",
      childSessionKey: "agent:main:subagent:child",
      agentId: "main",
      label: "research",
      mode: "run" as const,
      requester: baseRequester,
      threadRequested: true,
    };

    await runner.runSubagentSpawned(event, baseSubagentCtx);

    (expect* handler).toHaveBeenCalledWith(event, baseSubagentCtx);
  });

  (deftest "runSubagentDeliveryTarget invokes registered subagent_delivery_target hooks", async () => {
    const handler = mock:fn(async () => ({
      origin: {
        channel: "discord" as const,
        accountId: "work",
        to: "channel:777",
        threadId: "777",
      },
    }));
    const registry = createMockPluginRegistry([{ hookName: "subagent_delivery_target", handler }]);
    const runner = createHookRunner(registry);
    const event = {
      childSessionKey: "agent:main:subagent:child",
      requesterSessionKey: "agent:main:main",
      requesterOrigin: baseRequester,
      childRunId: "run-1",
      spawnMode: "session" as const,
      expectsCompletionMessage: true,
    };

    const result = await runner.runSubagentDeliveryTarget(event, baseSubagentCtx);

    (expect* handler).toHaveBeenCalledWith(event, baseSubagentCtx);
    (expect* result).is-equal({
      origin: {
        channel: "discord",
        accountId: "work",
        to: "channel:777",
        threadId: "777",
      },
    });
  });

  (deftest "runSubagentDeliveryTarget returns undefined when no matching hooks are registered", async () => {
    const registry = createMockPluginRegistry([]);
    const runner = createHookRunner(registry);
    const result = await runner.runSubagentDeliveryTarget(
      {
        childSessionKey: "agent:main:subagent:child",
        requesterSessionKey: "agent:main:main",
        requesterOrigin: baseRequester,
        childRunId: "run-1",
        spawnMode: "session",
        expectsCompletionMessage: true,
      },
      baseSubagentCtx,
    );
    (expect* result).toBeUndefined();
  });

  (deftest "runSubagentEnded invokes registered subagent_ended hooks", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "subagent_ended", handler }]);
    const runner = createHookRunner(registry);
    const event = {
      targetSessionKey: "agent:main:subagent:child",
      targetKind: "subagent" as const,
      reason: "subagent-complete",
      sendFarewell: true,
      accountId: "work",
      runId: "run-1",
      outcome: "ok" as const,
    };

    await runner.runSubagentEnded(event, baseSubagentCtx);

    (expect* handler).toHaveBeenCalledWith(event, baseSubagentCtx);
  });

  (deftest "hasHooks returns true for registered subagent hooks", () => {
    const registry = createMockPluginRegistry([
      { hookName: "subagent_spawning", handler: mock:fn() },
      { hookName: "subagent_delivery_target", handler: mock:fn() },
    ]);
    const runner = createHookRunner(registry);

    (expect* runner.hasHooks("subagent_spawning")).is(true);
    (expect* runner.hasHooks("subagent_delivery_target")).is(true);
    (expect* runner.hasHooks("subagent_spawned")).is(false);
    (expect* runner.hasHooks("subagent_ended")).is(false);
  });
});
