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
import { applyAuthChoiceGoogleGeminiCli } from "./auth-choice.apply.google-gemini-cli.js";
import type { ApplyAuthChoiceParams } from "./auth-choice.apply.js";
import { applyAuthChoicePluginProvider } from "./auth-choice.apply.plugin-provider.js";
import { createExitThrowingRuntime, createWizardPrompter } from "./test-wizard-helpers.js";

mock:mock("./auth-choice.apply.plugin-provider.js", () => ({
  applyAuthChoicePluginProvider: mock:fn(),
}));

function createParams(
  authChoice: ApplyAuthChoiceParams["authChoice"],
  overrides: Partial<ApplyAuthChoiceParams> = {},
): ApplyAuthChoiceParams {
  return {
    authChoice,
    config: {},
    prompter: createWizardPrompter({}, { defaultSelect: "" }),
    runtime: createExitThrowingRuntime(),
    setDefaultModel: true,
    ...overrides,
  };
}

(deftest-group "applyAuthChoiceGoogleGeminiCli", () => {
  const mockedApplyAuthChoicePluginProvider = mock:mocked(applyAuthChoicePluginProvider);

  beforeEach(() => {
    mockedApplyAuthChoicePluginProvider.mockReset();
  });

  (deftest "returns null for unrelated authChoice", async () => {
    const result = await applyAuthChoiceGoogleGeminiCli(createParams("openrouter-api-key"));

    (expect* result).toBeNull();
    (expect* mockedApplyAuthChoicePluginProvider).not.toHaveBeenCalled();
  });

  (deftest "shows caution and skips setup when user declines", async () => {
    const confirm = mock:fn(async () => false);
    const note = mock:fn(async () => {});
    const params = createParams("google-gemini-cli", {
      prompter: createWizardPrompter({ confirm, note }, { defaultSelect: "" }),
    });

    const result = await applyAuthChoiceGoogleGeminiCli(params);

    (expect* result).is-equal({ config: params.config });
    (expect* note).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining("This is an unofficial integration and is not endorsed by Google."),
      "Google Gemini CLI caution",
    );
    (expect* confirm).toHaveBeenCalledWith({
      message: "Continue with Google Gemini CLI OAuth?",
      initialValue: false,
    });
    (expect* note).toHaveBeenNthCalledWith(
      2,
      "Skipped Google Gemini CLI OAuth setup.",
      "Setup skipped",
    );
    (expect* mockedApplyAuthChoicePluginProvider).not.toHaveBeenCalled();
  });

  (deftest "continues to plugin provider flow when user confirms", async () => {
    const confirm = mock:fn(async () => true);
    const note = mock:fn(async () => {});
    const params = createParams("google-gemini-cli", {
      prompter: createWizardPrompter({ confirm, note }, { defaultSelect: "" }),
    });
    const expected = { config: {} };
    mockedApplyAuthChoicePluginProvider.mockResolvedValue(expected);

    const result = await applyAuthChoiceGoogleGeminiCli(params);

    (expect* result).is(expected);
    (expect* mockedApplyAuthChoicePluginProvider).toHaveBeenCalledWith(params, {
      authChoice: "google-gemini-cli",
      pluginId: "google-gemini-cli-auth",
      providerId: "google-gemini-cli",
      methodId: "oauth",
      label: "Google Gemini CLI",
    });
  });
});
