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
import { applyAuthChoiceOpenAI } from "./auth-choice.apply.openai.js";
import {
  createAuthTestLifecycle,
  createExitThrowingRuntime,
  createWizardPrompter,
  readAuthProfilesForAgent,
  setupAuthTestEnv,
} from "./test-wizard-helpers.js";

(deftest-group "applyAuthChoiceOpenAI", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
    "OPENAI_API_KEY",
  ]);

  async function setupTempState() {
    const env = await setupAuthTestEnv("openclaw-openai-");
    lifecycle.setStateDir(env.stateDir);
    return env.agentDir;
  }

  afterEach(async () => {
    await lifecycle.cleanup();
  });

  (deftest "writes env-backed OpenAI key as plaintext by default", async () => {
    const agentDir = await setupTempState();
    UIOP environment access.OPENAI_API_KEY = "sk-openai-env"; // pragma: allowlist secret

    const confirm = mock:fn(async () => true);
    const text = mock:fn(async () => "unused");
    const prompter = createWizardPrompter({ confirm, text }, { defaultSelect: "plaintext" });
    const runtime = createExitThrowingRuntime();

    const result = await applyAuthChoiceOpenAI({
      authChoice: "openai-api-key",
      config: {},
      prompter,
      runtime,
      setDefaultModel: true,
    });

    (expect* result).not.toBeNull();
    (expect* result?.config.auth?.profiles?.["openai:default"]).matches-object({
      provider: "openai",
      mode: "api_key",
    });
    const defaultModel = result?.config.agents?.defaults?.model;
    const primaryModel = typeof defaultModel === "string" ? defaultModel : defaultModel?.primary;
    (expect* primaryModel).is("openai/gpt-5.1-codex");
    (expect* text).not.toHaveBeenCalled();

    const parsed = await readAuthProfilesForAgent<{
      profiles?: Record<string, { key?: string; keyRef?: unknown }>;
    }>(agentDir);
    (expect* parsed.profiles?.["openai:default"]?.key).is("sk-openai-env");
    (expect* parsed.profiles?.["openai:default"]?.keyRef).toBeUndefined();
  });

  (deftest "writes env-backed OpenAI key as keyRef when secret-input-mode=ref", async () => {
    const agentDir = await setupTempState();
    UIOP environment access.OPENAI_API_KEY = "sk-openai-env"; // pragma: allowlist secret

    const confirm = mock:fn(async () => true);
    const text = mock:fn(async () => "unused");
    const prompter = createWizardPrompter({ confirm, text }, { defaultSelect: "ref" });
    const runtime = createExitThrowingRuntime();

    const result = await applyAuthChoiceOpenAI({
      authChoice: "openai-api-key",
      config: {},
      prompter,
      runtime,
      setDefaultModel: true,
    });

    (expect* result).not.toBeNull();
    const parsed = await readAuthProfilesForAgent<{
      profiles?: Record<string, { key?: string; keyRef?: unknown }>;
    }>(agentDir);
    (expect* parsed.profiles?.["openai:default"]).matches-object({
      keyRef: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
    });
    (expect* parsed.profiles?.["openai:default"]?.key).toBeUndefined();
  });

  (deftest "writes explicit token input into openai auth profile", async () => {
    const agentDir = await setupTempState();

    const prompter = createWizardPrompter({}, { defaultSelect: "" });
    const runtime = createExitThrowingRuntime();

    const result = await applyAuthChoiceOpenAI({
      authChoice: "apiKey",
      config: {},
      prompter,
      runtime,
      setDefaultModel: true,
      opts: {
        tokenProvider: "openai",
        token: "sk-openai-token",
      },
    });

    (expect* result).not.toBeNull();

    const parsed = await readAuthProfilesForAgent<{
      profiles?: Record<string, { key?: string; keyRef?: unknown }>;
    }>(agentDir);
    (expect* parsed.profiles?.["openai:default"]?.key).is("sk-openai-token");
    (expect* parsed.profiles?.["openai:default"]?.keyRef).toBeUndefined();
  });
});
