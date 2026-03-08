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
 * Test: message_sending & message_sent hook wiring
 *
 * Tests the hook runner methods directly since outbound delivery is deeply integrated.
 */
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createHookRunner } from "./hooks.js";
import { createMockPluginRegistry } from "./hooks.test-helpers.js";

(deftest-group "message_sending hook runner", () => {
  (deftest "runMessageSending invokes registered hooks and returns modified content", async () => {
    const handler = mock:fn().mockReturnValue({ content: "modified content" });
    const registry = createMockPluginRegistry([{ hookName: "message_sending", handler }]);
    const runner = createHookRunner(registry);

    const result = await runner.runMessageSending(
      { to: "user-123", content: "original content" },
      { channelId: "telegram" },
    );

    (expect* handler).toHaveBeenCalledWith(
      { to: "user-123", content: "original content" },
      { channelId: "telegram" },
    );
    (expect* result?.content).is("modified content");
  });

  (deftest "runMessageSending can cancel message delivery", async () => {
    const handler = mock:fn().mockReturnValue({ cancel: true });
    const registry = createMockPluginRegistry([{ hookName: "message_sending", handler }]);
    const runner = createHookRunner(registry);

    const result = await runner.runMessageSending(
      { to: "user-123", content: "blocked" },
      { channelId: "telegram" },
    );

    (expect* result?.cancel).is(true);
  });
});

(deftest-group "message_sent hook runner", () => {
  (deftest "runMessageSent invokes registered hooks with success=true", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "message_sent", handler }]);
    const runner = createHookRunner(registry);

    await runner.runMessageSent(
      { to: "user-123", content: "hello", success: true },
      { channelId: "telegram" },
    );

    (expect* handler).toHaveBeenCalledWith(
      { to: "user-123", content: "hello", success: true },
      { channelId: "telegram" },
    );
  });

  (deftest "runMessageSent invokes registered hooks with error on failure", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "message_sent", handler }]);
    const runner = createHookRunner(registry);

    await runner.runMessageSent(
      { to: "user-123", content: "hello", success: false, error: "timeout" },
      { channelId: "telegram" },
    );

    (expect* handler).toHaveBeenCalledWith(
      { to: "user-123", content: "hello", success: false, error: "timeout" },
      { channelId: "telegram" },
    );
  });
});
