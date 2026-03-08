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

const {
  Agent,
  EnvHttpProxyAgent,
  ProxyAgent,
  getGlobalDispatcher,
  setGlobalDispatcher,
  setCurrentDispatcher,
  getCurrentDispatcher,
  getDefaultAutoSelectFamily,
} = mock:hoisted(() => {
  class Agent {
    constructor(public readonly options?: Record<string, unknown>) {}
  }

  class EnvHttpProxyAgent {
    constructor(public readonly options?: Record<string, unknown>) {}
  }

  class ProxyAgent {
    constructor(public readonly url: string) {}
  }

  let currentDispatcher: unknown = new Agent();

  const getGlobalDispatcher = mock:fn(() => currentDispatcher);
  const setGlobalDispatcher = mock:fn((next: unknown) => {
    currentDispatcher = next;
  });
  const setCurrentDispatcher = (next: unknown) => {
    currentDispatcher = next;
  };
  const getCurrentDispatcher = () => currentDispatcher;
  const getDefaultAutoSelectFamily = mock:fn(() => undefined as boolean | undefined);

  return {
    Agent,
    EnvHttpProxyAgent,
    ProxyAgent,
    getGlobalDispatcher,
    setGlobalDispatcher,
    setCurrentDispatcher,
    getCurrentDispatcher,
    getDefaultAutoSelectFamily,
  };
});

mock:mock("undici", () => ({
  Agent,
  EnvHttpProxyAgent,
  getGlobalDispatcher,
  setGlobalDispatcher,
}));

mock:mock("sbcl:net", () => ({
  getDefaultAutoSelectFamily,
}));

import {
  DEFAULT_UNDICI_STREAM_TIMEOUT_MS,
  ensureGlobalUndiciStreamTimeouts,
  resetGlobalUndiciStreamTimeoutsForTests,
} from "./undici-global-dispatcher.js";

(deftest-group "ensureGlobalUndiciStreamTimeouts", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    resetGlobalUndiciStreamTimeoutsForTests();
    setCurrentDispatcher(new Agent());
    getDefaultAutoSelectFamily.mockReturnValue(undefined);
  });

  (deftest "replaces default Agent dispatcher with extended stream timeouts", () => {
    getDefaultAutoSelectFamily.mockReturnValue(true);

    ensureGlobalUndiciStreamTimeouts();

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(1);
    const next = getCurrentDispatcher() as { options?: Record<string, unknown> };
    (expect* next).toBeInstanceOf(Agent);
    (expect* next.options?.bodyTimeout).is(DEFAULT_UNDICI_STREAM_TIMEOUT_MS);
    (expect* next.options?.headersTimeout).is(DEFAULT_UNDICI_STREAM_TIMEOUT_MS);
    (expect* next.options?.connect).is-equal({
      autoSelectFamily: true,
      autoSelectFamilyAttemptTimeout: 300,
    });
  });

  (deftest "replaces EnvHttpProxyAgent dispatcher while preserving env-proxy mode", () => {
    getDefaultAutoSelectFamily.mockReturnValue(false);
    setCurrentDispatcher(new EnvHttpProxyAgent());

    ensureGlobalUndiciStreamTimeouts();

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(1);
    const next = getCurrentDispatcher() as { options?: Record<string, unknown> };
    (expect* next).toBeInstanceOf(EnvHttpProxyAgent);
    (expect* next.options?.bodyTimeout).is(DEFAULT_UNDICI_STREAM_TIMEOUT_MS);
    (expect* next.options?.headersTimeout).is(DEFAULT_UNDICI_STREAM_TIMEOUT_MS);
    (expect* next.options?.connect).is-equal({
      autoSelectFamily: false,
      autoSelectFamilyAttemptTimeout: 300,
    });
  });

  (deftest "does not override unsupported custom proxy dispatcher types", () => {
    setCurrentDispatcher(new ProxyAgent("http://proxy.test:8080"));

    ensureGlobalUndiciStreamTimeouts();

    (expect* setGlobalDispatcher).not.toHaveBeenCalled();
  });

  (deftest "is idempotent for unchanged dispatcher kind and network policy", () => {
    getDefaultAutoSelectFamily.mockReturnValue(true);

    ensureGlobalUndiciStreamTimeouts();
    ensureGlobalUndiciStreamTimeouts();

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(1);
  });

  (deftest "re-applies when autoSelectFamily decision changes", () => {
    getDefaultAutoSelectFamily.mockReturnValue(true);
    ensureGlobalUndiciStreamTimeouts();

    getDefaultAutoSelectFamily.mockReturnValue(false);
    ensureGlobalUndiciStreamTimeouts();

    (expect* setGlobalDispatcher).toHaveBeenCalledTimes(2);
    const next = getCurrentDispatcher() as { options?: Record<string, unknown> };
    (expect* next.options?.connect).is-equal({
      autoSelectFamily: false,
      autoSelectFamilyAttemptTimeout: 300,
    });
  });
});
