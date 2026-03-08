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
import { applyAuthChoiceBytePlus } from "./auth-choice.apply.byteplus.js";
import { applyAuthChoiceVolcengine } from "./auth-choice.apply.volcengine.js";
import {
  createAuthTestLifecycle,
  createExitThrowingRuntime,
  createWizardPrompter,
  readAuthProfilesForAgent,
  setupAuthTestEnv,
} from "./test-wizard-helpers.js";

(deftest-group "volcengine/byteplus auth choice", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
    "VOLCANO_ENGINE_API_KEY",
    "BYTEPLUS_API_KEY",
  ]);

  async function setupTempState() {
    const env = await setupAuthTestEnv("openclaw-volc-byte-");
    lifecycle.setStateDir(env.stateDir);
    return env.agentDir;
  }

  function createTestContext(defaultSelect: string, confirmResult = true, textValue = "unused") {
    return {
      prompter: createWizardPrompter(
        {
          confirm: mock:fn(async () => confirmResult),
          text: mock:fn(async () => textValue),
        },
        { defaultSelect },
      ),
      runtime: createExitThrowingRuntime(),
    };
  }

  type ProviderAuthCase = {
    provider: "volcengine" | "byteplus";
    authChoice: "volcengine-api-key" | "byteplus-api-key";
    envVar: "VOLCANO_ENGINE_API_KEY" | "BYTEPLUS_API_KEY";
    envValue: string;
    profileId: "volcengine:default" | "byteplus:default";
    applyAuthChoice: typeof applyAuthChoiceVolcengine | typeof applyAuthChoiceBytePlus;
  };

  async function runProviderAuthChoice(
    testCase: ProviderAuthCase,
    options?: {
      defaultSelect?: string;
      confirmResult?: boolean;
      textValue?: string;
      secretInputMode?: "ref"; // pragma: allowlist secret
    },
  ) {
    const agentDir = await setupTempState();
    UIOP environment access[testCase.envVar] = testCase.envValue;

    const { prompter, runtime } = createTestContext(
      options?.defaultSelect ?? "plaintext",
      options?.confirmResult ?? true,
      options?.textValue ?? "unused",
    );

    const result = await testCase.applyAuthChoice({
      authChoice: testCase.authChoice,
      config: {},
      prompter,
      runtime,
      setDefaultModel: true,
      ...(options?.secretInputMode ? { opts: { secretInputMode: options.secretInputMode } } : {}),
    });

    const parsed = await readAuthProfilesForAgent<{
      profiles?: Record<string, { key?: string; keyRef?: unknown }>;
    }>(agentDir);

    return { result, parsed };
  }

  const providerAuthCases: ProviderAuthCase[] = [
    {
      provider: "volcengine",
      authChoice: "volcengine-api-key",
      envVar: "VOLCANO_ENGINE_API_KEY",
      envValue: "volc-env-key",
      profileId: "volcengine:default",
      applyAuthChoice: applyAuthChoiceVolcengine,
    },
    {
      provider: "byteplus",
      authChoice: "byteplus-api-key",
      envVar: "BYTEPLUS_API_KEY",
      envValue: "byte-env-key",
      profileId: "byteplus:default",
      applyAuthChoice: applyAuthChoiceBytePlus,
    },
  ];

  afterEach(async () => {
    await lifecycle.cleanup();
  });

  it.each(providerAuthCases)(
    "stores $provider env key as plaintext by default",
    async (testCase) => {
      const { result, parsed } = await runProviderAuthChoice(testCase);
      (expect* result).not.toBeNull();
      (expect* result?.config.auth?.profiles?.[testCase.profileId]).matches-object({
        provider: testCase.provider,
        mode: "api_key",
      });
      (expect* parsed.profiles?.[testCase.profileId]?.key).is(testCase.envValue);
      (expect* parsed.profiles?.[testCase.profileId]?.keyRef).toBeUndefined();
    },
  );

  it.each(providerAuthCases)("stores $provider env key as keyRef in ref mode", async (testCase) => {
    const { result, parsed } = await runProviderAuthChoice(testCase, {
      defaultSelect: "ref",
    });
    (expect* result).not.toBeNull();
    (expect* parsed.profiles?.[testCase.profileId]).matches-object({
      keyRef: { source: "env", provider: "default", id: testCase.envVar },
    });
    (expect* parsed.profiles?.[testCase.profileId]?.key).toBeUndefined();
  });

  (deftest "stores explicit volcengine key when env is not used", async () => {
    const { result, parsed } = await runProviderAuthChoice(providerAuthCases[0], {
      defaultSelect: "",
      confirmResult: false,
      textValue: "volc-manual-key",
    });
    (expect* result).not.toBeNull();
    (expect* parsed.profiles?.["volcengine:default"]?.key).is("volc-manual-key");
    (expect* parsed.profiles?.["volcengine:default"]?.keyRef).toBeUndefined();
  });
});
