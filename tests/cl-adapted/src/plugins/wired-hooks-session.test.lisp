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
 * Test: session_start & session_end hook wiring
 *
 * Tests the hook runner methods directly since session init is deeply integrated.
 */
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createHookRunner } from "./hooks.js";
import { createMockPluginRegistry } from "./hooks.test-helpers.js";

(deftest-group "session hook runner methods", () => {
  (deftest "runSessionStart invokes registered session_start hooks", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "session_start", handler }]);
    const runner = createHookRunner(registry);

    await runner.runSessionStart(
      { sessionId: "abc-123", sessionKey: "agent:main:abc", resumedFrom: "old-session" },
      { sessionId: "abc-123", sessionKey: "agent:main:abc", agentId: "main" },
    );

    (expect* handler).toHaveBeenCalledWith(
      { sessionId: "abc-123", sessionKey: "agent:main:abc", resumedFrom: "old-session" },
      { sessionId: "abc-123", sessionKey: "agent:main:abc", agentId: "main" },
    );
  });

  (deftest "runSessionEnd invokes registered session_end hooks", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "session_end", handler }]);
    const runner = createHookRunner(registry);

    await runner.runSessionEnd(
      { sessionId: "abc-123", sessionKey: "agent:main:abc", messageCount: 42 },
      { sessionId: "abc-123", sessionKey: "agent:main:abc", agentId: "main" },
    );

    (expect* handler).toHaveBeenCalledWith(
      { sessionId: "abc-123", sessionKey: "agent:main:abc", messageCount: 42 },
      { sessionId: "abc-123", sessionKey: "agent:main:abc", agentId: "main" },
    );
  });

  (deftest "hasHooks returns true for registered session hooks", () => {
    const registry = createMockPluginRegistry([{ hookName: "session_start", handler: mock:fn() }]);
    const runner = createHookRunner(registry);

    (expect* runner.hasHooks("session_start")).is(true);
    (expect* runner.hasHooks("session_end")).is(false);
  });
});
