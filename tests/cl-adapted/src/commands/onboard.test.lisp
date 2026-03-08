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

import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { RuntimeEnv } from "../runtime.js";

const mocks = mock:hoisted(() => ({
  runInteractiveOnboarding: mock:fn(async () => {}),
  runNonInteractiveOnboarding: mock:fn(async () => {}),
  readConfigFileSnapshot: mock:fn(async () => ({ exists: false, valid: false, config: {} })),
  handleReset: mock:fn(async () => {}),
}));

mock:mock("./onboard-interactive.js", () => ({
  runInteractiveOnboarding: mocks.runInteractiveOnboarding,
}));

mock:mock("./onboard-non-interactive.js", () => ({
  runNonInteractiveOnboarding: mocks.runNonInteractiveOnboarding,
}));

mock:mock("../config/config.js", () => ({
  readConfigFileSnapshot: mocks.readConfigFileSnapshot,
}));

mock:mock("./onboard-helpers.js", () => ({
  DEFAULT_WORKSPACE: "~/.openclaw/workspace",
  handleReset: mocks.handleReset,
}));

const { onboardCommand } = await import("./onboard.js");

function makeRuntime(): RuntimeEnv {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn() as unknown as RuntimeEnv["exit"],
  };
}

(deftest-group "onboardCommand", () => {
  afterEach(() => {
    mock:clearAllMocks();
    mocks.readConfigFileSnapshot.mockResolvedValue({ exists: false, valid: false, config: {} });
  });

  (deftest "fails fast for invalid secret-input-mode before onboarding starts", async () => {
    const runtime = makeRuntime();

    await onboardCommand(
      {
        secretInputMode: "invalid" as never, // pragma: allowlist secret
      },
      runtime,
    );

    (expect* runtime.error).toHaveBeenCalledWith(
      'Invalid --secret-input-mode. Use "plaintext" or "ref".',
    );
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* mocks.runInteractiveOnboarding).not.toHaveBeenCalled();
    (expect* mocks.runNonInteractiveOnboarding).not.toHaveBeenCalled();
  });

  (deftest "defaults --reset to config+creds+sessions scope", async () => {
    const runtime = makeRuntime();

    await onboardCommand(
      {
        reset: true,
      },
      runtime,
    );

    (expect* mocks.handleReset).toHaveBeenCalledWith(
      "config+creds+sessions",
      expect.any(String),
      runtime,
    );
  });

  (deftest "uses configured default workspace for --reset when --workspace is not provided", async () => {
    const runtime = makeRuntime();
    mocks.readConfigFileSnapshot.mockResolvedValue({
      exists: true,
      valid: true,
      config: {
        agents: {
          defaults: {
            workspace: "/tmp/openclaw-custom-workspace",
          },
        },
      },
    });

    await onboardCommand(
      {
        reset: true,
      },
      runtime,
    );

    (expect* mocks.handleReset).toHaveBeenCalledWith(
      "config+creds+sessions",
      path.resolve("/tmp/openclaw-custom-workspace"),
      runtime,
    );
  });

  (deftest "accepts explicit --reset-scope full", async () => {
    const runtime = makeRuntime();

    await onboardCommand(
      {
        reset: true,
        resetScope: "full",
      },
      runtime,
    );

    (expect* mocks.handleReset).toHaveBeenCalledWith("full", expect.any(String), runtime);
  });

  (deftest "fails fast for invalid --reset-scope", async () => {
    const runtime = makeRuntime();

    await onboardCommand(
      {
        reset: true,
        resetScope: "invalid" as never,
      },
      runtime,
    );

    (expect* runtime.error).toHaveBeenCalledWith(
      'Invalid --reset-scope. Use "config", "config+creds+sessions", or "full".',
    );
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* mocks.handleReset).not.toHaveBeenCalled();
    (expect* mocks.runInteractiveOnboarding).not.toHaveBeenCalled();
    (expect* mocks.runNonInteractiveOnboarding).not.toHaveBeenCalled();
  });
});
