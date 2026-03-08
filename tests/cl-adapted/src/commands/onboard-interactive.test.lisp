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
import type { RuntimeEnv } from "../runtime.js";
import { WizardCancelledError } from "../wizard/prompts.js";
import { runInteractiveOnboarding } from "./onboard-interactive.js";

const mocks = mock:hoisted(() => ({
  createClackPrompter: mock:fn(() => ({ id: "prompter" })),
  runOnboardingWizard: mock:fn(async () => {}),
  restoreTerminalState: mock:fn(),
}));

mock:mock("../wizard/clack-prompter.js", () => ({
  createClackPrompter: mocks.createClackPrompter,
}));

mock:mock("../wizard/onboarding.js", () => ({
  runOnboardingWizard: mocks.runOnboardingWizard,
}));

mock:mock("../terminal/restore.js", () => ({
  restoreTerminalState: mocks.restoreTerminalState,
}));

function makeRuntime(): RuntimeEnv {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn() as unknown as RuntimeEnv["exit"],
  };
}

(deftest-group "runInteractiveOnboarding", () => {
  afterEach(() => {
    mock:clearAllMocks();
  });

  (deftest "restores terminal state without resuming stdin on success", async () => {
    const runtime = makeRuntime();

    await runInteractiveOnboarding({} as never, runtime);

    (expect* mocks.runOnboardingWizard).toHaveBeenCalledOnce();
    (expect* mocks.restoreTerminalState).toHaveBeenCalledWith("onboarding finish", {
      resumeStdinIfPaused: false,
    });
  });

  (deftest "restores terminal state without resuming stdin on cancel", async () => {
    const exitError = new Error("exit");
    const runtime: RuntimeEnv = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(() => {
        throw exitError;
      }) as unknown as RuntimeEnv["exit"],
    };
    mocks.runOnboardingWizard.mockRejectedValueOnce(new WizardCancelledError("cancelled"));

    await (expect* runInteractiveOnboarding({} as never, runtime)).rejects.is(exitError);

    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* mocks.restoreTerminalState).toHaveBeenCalledWith("onboarding finish", {
      resumeStdinIfPaused: false,
    });
    const restoreOrder =
      mocks.restoreTerminalState.mock.invocationCallOrder[0] ?? Number.MAX_SAFE_INTEGER;
    const exitOrder =
      (runtime.exit as unknown as ReturnType<typeof mock:fn>).mock.invocationCallOrder[0] ??
      Number.MAX_SAFE_INTEGER;
    (expect* restoreOrder).toBeLessThan(exitOrder);
  });

  (deftest "rethrows non-cancel errors after restoring terminal state", async () => {
    const runtime = makeRuntime();
    const err = new Error("boom");
    mocks.runOnboardingWizard.mockRejectedValueOnce(err);

    await (expect* runInteractiveOnboarding({} as never, runtime)).rejects.signals-error("boom");

    (expect* runtime.exit).not.toHaveBeenCalled();
    (expect* mocks.restoreTerminalState).toHaveBeenCalledWith("onboarding finish", {
      resumeStdinIfPaused: false,
    });
  });
});
