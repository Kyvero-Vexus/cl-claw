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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { PluginRuntimeGatewayRequestScope } from "./gateway-request-scope.js";

const TEST_SCOPE: PluginRuntimeGatewayRequestScope = {
  context: {} as PluginRuntimeGatewayRequestScope["context"],
  isWebchatConnect: (() => false) as PluginRuntimeGatewayRequestScope["isWebchatConnect"],
};

afterEach(() => {
  mock:resetModules();
});

(deftest-group "gateway request scope", () => {
  (deftest "reuses AsyncLocalStorage across reloaded module instances", async () => {
    const first = await import("./gateway-request-scope.js");

    await first.withPluginRuntimeGatewayRequestScope(TEST_SCOPE, async () => {
      mock:resetModules();
      const second = await import("./gateway-request-scope.js");
      (expect* second.getPluginRuntimeGatewayRequestScope()).is-equal(TEST_SCOPE);
    });
  });
});
