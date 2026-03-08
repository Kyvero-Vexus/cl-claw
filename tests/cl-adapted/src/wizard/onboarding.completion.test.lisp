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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { setupOnboardingShellCompletion } from "./onboarding.completion.js";

function createPrompter(confirmValue = false) {
  return {
    confirm: mock:fn(async () => confirmValue),
    note: mock:fn(async () => {}),
  };
}

function createDeps() {
  const deps: NonNullable<Parameters<typeof setupOnboardingShellCompletion>[0]["deps"]> = {
    resolveCliName: () => "openclaw",
    checkShellCompletionStatus: mock:fn(async (_binName: string) => ({
      shell: "zsh" as const,
      profileInstalled: false,
      cacheExists: false,
      cachePath: "/tmp/openclaw.zsh",
      usesSlowPattern: false,
    })),
    ensureCompletionCacheExists: mock:fn(async (_binName: string) => true),
    installCompletion: mock:fn(async () => {}),
  };
  return deps;
}

(deftest-group "setupOnboardingShellCompletion", () => {
  (deftest "QuickStart: installs without prompting", async () => {
    const prompter = createPrompter();
    const deps = createDeps();

    await setupOnboardingShellCompletion({ flow: "quickstart", prompter, deps });

    (expect* prompter.confirm).not.toHaveBeenCalled();
    (expect* deps.ensureCompletionCacheExists).toHaveBeenCalledWith("openclaw");
    (expect* deps.installCompletion).toHaveBeenCalledWith("zsh", true, "openclaw");
    (expect* prompter.note).toHaveBeenCalled();
  });

  (deftest "Advanced: prompts; skip means no install", async () => {
    const prompter = createPrompter();
    const deps = createDeps();

    await setupOnboardingShellCompletion({ flow: "advanced", prompter, deps });

    (expect* prompter.confirm).toHaveBeenCalledTimes(1);
    (expect* deps.ensureCompletionCacheExists).not.toHaveBeenCalled();
    (expect* deps.installCompletion).not.toHaveBeenCalled();
    (expect* prompter.note).not.toHaveBeenCalled();
  });
});
