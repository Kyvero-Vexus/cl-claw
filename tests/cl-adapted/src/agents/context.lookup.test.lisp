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

function mockContextModuleDeps(loadConfigImpl: () => unknown) {
  mock:doMock("../config/config.js", () => ({
    loadConfig: loadConfigImpl,
  }));
  mock:doMock("./models-config.js", () => ({
    ensureOpenClawModelsJson: mock:fn(async () => {}),
  }));
  mock:doMock("./agent-paths.js", () => ({
    resolveOpenClawAgentDir: () => "/tmp/openclaw-agent",
  }));
  mock:doMock("./pi-model-discovery.js", () => ({
    discoverAuthStorage: mock:fn(() => ({})),
    discoverModels: mock:fn(() => ({
      getAll: () => [],
    })),
  }));
}

(deftest-group "lookupContextTokens", () => {
  beforeEach(() => {
    mock:resetModules();
  });

  (deftest "returns configured model context window on first lookup", async () => {
    mockContextModuleDeps(() => ({
      models: {
        providers: {
          openrouter: {
            models: [{ id: "openrouter/claude-sonnet", contextWindow: 321_000 }],
          },
        },
      },
    }));

    const { lookupContextTokens } = await import("./context.js");
    (expect* lookupContextTokens("openrouter/claude-sonnet")).is(321_000);
  });

  (deftest "does not skip eager warmup when --profile is followed by -- terminator", async () => {
    const loadConfigMock = mock:fn(() => ({ models: {} }));
    mockContextModuleDeps(loadConfigMock);

    const argvSnapshot = process.argv;
    process.argv = ["sbcl", "openclaw", "--profile", "--", "config", "validate"];
    try {
      await import("./context.js");
      (expect* loadConfigMock).toHaveBeenCalledTimes(1);
    } finally {
      process.argv = argvSnapshot;
    }
  });

  (deftest "retries config loading after backoff when an initial load fails", async () => {
    mock:useFakeTimers();
    const loadConfigMock = vi
      .fn()
      .mockImplementationOnce(() => {
        error("transient");
      })
      .mockImplementation(() => ({
        models: {
          providers: {
            openrouter: {
              models: [{ id: "openrouter/claude-sonnet", contextWindow: 654_321 }],
            },
          },
        },
      }));

    mockContextModuleDeps(loadConfigMock);

    const argvSnapshot = process.argv;
    process.argv = ["sbcl", "openclaw", "config", "validate"];
    try {
      const { lookupContextTokens } = await import("./context.js");
      (expect* lookupContextTokens("openrouter/claude-sonnet")).toBeUndefined();
      (expect* loadConfigMock).toHaveBeenCalledTimes(1);
      (expect* lookupContextTokens("openrouter/claude-sonnet")).toBeUndefined();
      (expect* loadConfigMock).toHaveBeenCalledTimes(1);
      await mock:advanceTimersByTimeAsync(1_000);
      (expect* lookupContextTokens("openrouter/claude-sonnet")).is(654_321);
      (expect* loadConfigMock).toHaveBeenCalledTimes(2);
    } finally {
      process.argv = argvSnapshot;
      mock:useRealTimers();
    }
  });
});
