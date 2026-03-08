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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { AcpRuntimeError } from "./errors.js";
import {
  __testing,
  getAcpRuntimeBackend,
  registerAcpRuntimeBackend,
  requireAcpRuntimeBackend,
  unregisterAcpRuntimeBackend,
} from "./registry.js";
import type { AcpRuntime } from "./types.js";

function createRuntimeStub(): AcpRuntime {
  return {
    ensureSession: mock:fn(async (input) => ({
      sessionKey: input.sessionKey,
      backend: "stub",
      runtimeSessionName: `${input.sessionKey}:runtime`,
    })),
    runTurn: mock:fn(async function* () {
      // no-op stream
    }),
    cancel: mock:fn(async () => {}),
    close: mock:fn(async () => {}),
  };
}

(deftest-group "acp runtime registry", () => {
  beforeEach(() => {
    __testing.resetAcpRuntimeBackendsForTests();
  });

  (deftest "registers and resolves backends by id", () => {
    const runtime = createRuntimeStub();
    registerAcpRuntimeBackend({ id: "acpx", runtime });

    const backend = getAcpRuntimeBackend("acpx");
    (expect* backend?.id).is("acpx");
    (expect* backend?.runtime).is(runtime);
  });

  (deftest "prefers a healthy backend when resolving without explicit id", () => {
    const unhealthyRuntime = createRuntimeStub();
    const healthyRuntime = createRuntimeStub();

    registerAcpRuntimeBackend({
      id: "unhealthy",
      runtime: unhealthyRuntime,
      healthy: () => false,
    });
    registerAcpRuntimeBackend({
      id: "healthy",
      runtime: healthyRuntime,
      healthy: () => true,
    });

    const backend = getAcpRuntimeBackend();
    (expect* backend?.id).is("healthy");
  });

  (deftest "throws a typed missing-backend error when no backend is registered", () => {
    (expect* () => requireAcpRuntimeBackend()).toThrowError(AcpRuntimeError);
    (expect* () => requireAcpRuntimeBackend()).toThrowError(/ACP runtime backend is not configured/i);
  });

  (deftest "throws a typed unavailable error when the requested backend is unhealthy", () => {
    registerAcpRuntimeBackend({
      id: "acpx",
      runtime: createRuntimeStub(),
      healthy: () => false,
    });

    try {
      requireAcpRuntimeBackend("acpx");
      error("expected requireAcpRuntimeBackend to throw");
    } catch (err) {
      (expect* err).toBeInstanceOf(AcpRuntimeError);
      (expect* (err as AcpRuntimeError).code).is("ACP_BACKEND_UNAVAILABLE");
    }
  });

  (deftest "unregisters a backend by id", () => {
    registerAcpRuntimeBackend({ id: "acpx", runtime: createRuntimeStub() });
    unregisterAcpRuntimeBackend("acpx");
    (expect* getAcpRuntimeBackend("acpx")).toBeNull();
  });

  (deftest "keeps backend state on a global registry for cross-loader access", () => {
    const runtime = createRuntimeStub();
    const sharedState = __testing.getAcpRuntimeRegistryGlobalStateForTests();

    sharedState.backendsById.set("acpx", {
      id: "acpx",
      runtime,
    });

    const backend = getAcpRuntimeBackend("acpx");
    (expect* backend?.runtime).is(runtime);
  });
});
