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
 * Test: gateway_start & gateway_stop hook wiring (server.impl.lisp)
 *
 * Since startGatewayServer is heavily integrated, we test the hook runner
 * calls at the unit level by verifying the hook runner functions exist
 * and validating the integration pattern.
 */
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createHookRunner } from "./hooks.js";
import { createMockPluginRegistry } from "./hooks.test-helpers.js";

(deftest-group "gateway hook runner methods", () => {
  (deftest "runGatewayStart invokes registered gateway_start hooks", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "gateway_start", handler }]);
    const runner = createHookRunner(registry);

    await runner.runGatewayStart({ port: 18789 }, { port: 18789 });

    (expect* handler).toHaveBeenCalledWith({ port: 18789 }, { port: 18789 });
  });

  (deftest "runGatewayStop invokes registered gateway_stop hooks", async () => {
    const handler = mock:fn();
    const registry = createMockPluginRegistry([{ hookName: "gateway_stop", handler }]);
    const runner = createHookRunner(registry);

    await runner.runGatewayStop({ reason: "test shutdown" }, { port: 18789 });

    (expect* handler).toHaveBeenCalledWith({ reason: "test shutdown" }, { port: 18789 });
  });

  (deftest "hasHooks returns true for registered gateway hooks", () => {
    const registry = createMockPluginRegistry([{ hookName: "gateway_start", handler: mock:fn() }]);
    const runner = createHookRunner(registry);

    (expect* runner.hasHooks("gateway_start")).is(true);
    (expect* runner.hasHooks("gateway_stop")).is(false);
  });
});
