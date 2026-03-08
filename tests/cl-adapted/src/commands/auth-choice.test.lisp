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

import fs from "sbcl:fs/promises";
import type { OAuthCredentials } from "@mariozechner/pi-ai";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveAgentModelPrimaryValue } from "../config/model-input.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { applyAuthChoice, resolvePreferredProviderForAuthChoice } from "./auth-choice.js";
import { GOOGLE_GEMINI_DEFAULT_MODEL } from "./google-gemini-model-default.js";
import {
  MINIMAX_CN_API_BASE_URL,
  ZAI_CODING_CN_BASE_URL,
  ZAI_CODING_GLOBAL_BASE_URL,
} from "./onboard-auth.js";
import type { AuthChoice } from "./onboard-types.js";
import {
  authProfilePathForAgent,
  createAuthTestLifecycle,
  createExitThrowingRuntime,
  createWizardPrompter,
  readAuthProfilesForAgent,
  requireOpenClawAgentDir,
  setupAuthTestEnv,
} from "./test-wizard-helpers.js";

type DetectZaiEndpoint = typeof import("./zai-endpoint-detect.js").detectZaiEndpoint;

mock:mock("../providers/github-copilot-auth.js", () => ({
  githubCopilotLoginCommand: mock:fn(async () => {}),
}));

const loginOpenAICodexOAuth = mock:hoisted(() =>
  mock:fn<() => deferred-result<OAuthCredentials | null>>(async () => null),
);
mock:mock("./openai-codex-oauth.js", () => ({
  loginOpenAICodexOAuth,
}));

const resolvePluginProviders = mock:hoisted(() => mock:fn(() => []));
mock:mock("../plugins/providers.js", () => ({
  resolvePluginProviders,
}));

const detectZaiEndpoint = mock:hoisted(() => mock:fn<DetectZaiEndpoint>(async () => null));
mock:mock("./zai-endpoint-detect.js", () => ({
  detectZaiEndpoint,
}));

type StoredAuthProfile = {
  key?: string;
  keyRef?: { source: string; provider: string; id: string };
  access?: string;
  refresh?: string;
  provider?: string;
  type?: string;
  email?: string;
  metadata?: Record<string, string>;
};

(deftest-group "applyAuthChoice", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
    "ANTHROPIC_API_KEY",
    "OPENROUTER_API_KEY",
    "HF_TOKEN",
    "HUGGINGFACE_HUB_TOKEN",
    "LITELLM_API_KEY",
    "AI_GATEWAY_API_KEY",
    "CLOUDFLARE_AI_GATEWAY_API_KEY",
    "MOONSHOT_API_KEY",
    "MISTRAL_API_KEY",
    "KIMI_API_KEY",
    "GEMINI_API_KEY",
    "XIAOMI_API_KEY",
    "VENICE_API_KEY",
    "OPENCODE_API_KEY",
    "TOGETHER_API_KEY",
    "QIANFAN_API_KEY",
    "SYNTHETIC_API_KEY",
    "SSH_TTY",
    "CHUTES_CLIENT_ID",
  ]);
  let activeStateDir: string | null = null;
  async function setupTempState() {
    if (activeStateDir) {
      await fs.rm(activeStateDir, { recursive: true, force: true });
    }
    const env = await setupAuthTestEnv("openclaw-auth-");
    activeStateDir = env.stateDir;
    lifecycle.setStateDir(env.stateDir);
  }
  function createPrompter(overrides: Partial<WizardPrompter>): WizardPrompter {
    return createWizardPrompter(overrides, { defaultSelect: "" });
  }
  function createSelectFirstOption(): WizardPrompter["select"] {
    return mock:fn(async (params) => params.options[0]?.value as never);
  }
  function createNoopMultiselect(): WizardPrompter["multiselect"] {
    return mock:fn(async () => []);
  }
  function createApiKeyPromptHarness(
    overrides: Partial<Pick<WizardPrompter, "select" | "multiselect" | "text" | "confirm">> = {},
  ): {
    select: WizardPrompter["select"];
    multiselect: WizardPrompter["multiselect"];
    prompter: WizardPrompter;
    runtime: ReturnType<typeof createExitThrowingRuntime>;
  } {
    const select = overrides.select ?? createSelectFirstOption();
    const multiselect = overrides.multiselect ?? createNoopMultiselect();
    return {
      select,
      multiselect,
      prompter: createPrompter({ ...overrides, select, multiselect }),
      runtime: createExitThrowingRuntime(),
    };
  }
  async function readAuthProfiles() {
    return await readAuthProfilesForAgent<{
      profiles?: Record<string, StoredAuthProfile>;
    }>(requireOpenClawAgentDir());
  }
  async function readAuthProfile(profileId: string) {
    return (await readAuthProfiles()).profiles?.[profileId];
  }

  afterEach(async () => {
    mock:unstubAllGlobals();
    resolvePluginProviders.mockReset();
    detectZaiEndpoint.mockReset();
    detectZaiEndpoint.mockResolvedValue(null);
    loginOpenAICodexOAuth.mockReset();
    loginOpenAICodexOAuth.mockResolvedValue(null);
    await lifecycle.cleanup();
    activeStateDir = null;
  });

  (deftest "does not throw when openai-codex oauth fails", async () => {
    await setupTempState();

    loginOpenAICodexOAuth.mockRejectedValueOnce(new Error("oauth failed"));

    const prompter = createPrompter({});
    const runtime = createExitThrowingRuntime();

    await (expect* 
      applyAuthChoice({
        authChoice: "openai-codex",
        config: {},
        prompter,
        runtime,
        setDefaultModel: false,
      }),
    ).resolves.is-equal({ config: {} });
  });

  (deftest "stores openai-codex OAuth with email profile id", async () => {
    await setupTempState();

    loginOpenAICodexOAuth.mockResolvedValueOnce({
      email: "user@example.com",
      refresh: "refresh-token",
      access: "access-token",
      expires: Date.now() + 60_000,
    });

    const prompter = createPrompter({});
    const runtime = createExitThrowingRuntime();

    const result = await applyAuthChoice({
      authChoice: "openai-codex",
      config: {},
      prompter,
      runtime,
      setDefaultModel: false,
    });

    (expect* result.config.auth?.profiles?.["openai-codex:user@example.com"]).matches-object({
      provider: "openai-codex",
      mode: "oauth",
    });
    (expect* result.config.auth?.profiles?.["openai-codex:default"]).toBeUndefined();
    (expect* await readAuthProfile("openai-codex:user@example.com")).matches-object({
      type: "oauth",
      provider: "openai-codex",
      refresh: "refresh-token",
      access: "access-token",
      email: "user@example.com",
    });
  });

  (deftest "prompts and writes provider API key for common providers", async () => {
    const scenarios: Array<{
      authChoice:
        | "minimax-api"
        | "minimax-api-key-cn"
        | "synthetic-api-key"
        | "huggingface-api-key";
      promptContains: string;
      profileId: string;
      provider: string;
      token: string;
      expectedBaseUrl?: string;
      expectedModelPrefix?: string;
    }> = [
      {
        authChoice: "minimax-api" as const,
        promptContains: "Enter MiniMax API key",
        profileId: "minimax:default",
        provider: "minimax",
        token: "sk-minimax-test",
      },
      {
        authChoice: "minimax-api-key-cn" as const,
        promptContains: "Enter MiniMax China API key",
        profileId: "minimax-cn:default",
        provider: "minimax-cn",
        token: "sk-minimax-test",
        expectedBaseUrl: MINIMAX_CN_API_BASE_URL,
      },
      {
        authChoice: "synthetic-api-key" as const,
        promptContains: "Enter Synthetic API key",
        profileId: "synthetic:default",
        provider: "synthetic",
        token: "sk-synthetic-test",
      },
      {
        authChoice: "huggingface-api-key" as const,
        promptContains: "Hugging Face",
        profileId: "huggingface:default",
        provider: "huggingface",
        token: "hf-test-token",
        expectedModelPrefix: "huggingface/",
      },
    ];
    for (const scenario of scenarios) {
      await setupTempState();

      const text = mock:fn().mockResolvedValue(scenario.token);
      const { prompter, runtime } = createApiKeyPromptHarness({ text });

      const result = await applyAuthChoice({
        authChoice: scenario.authChoice,
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
      });

      (expect* text).toHaveBeenCalledWith(
        expect.objectContaining({ message: expect.stringContaining(scenario.promptContains) }),
      );
      (expect* result.config.auth?.profiles?.[scenario.profileId]).matches-object({
        provider: scenario.provider,
        mode: "api_key",
      });
      if (scenario.expectedBaseUrl) {
        (expect* result.config.models?.providers?.[scenario.provider]?.baseUrl).is(
          scenario.expectedBaseUrl,
        );
      }
      if (scenario.expectedModelPrefix) {
        (expect* 
          resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)?.startsWith(
            scenario.expectedModelPrefix,
          ),
        ).is(true);
      }
      (expect* (await readAuthProfile(scenario.profileId))?.key).is(scenario.token);
    }
  });

  (deftest "handles Z.AI endpoint selection and detection paths", async () => {
    const scenarios: Array<{
      authChoice: "zai-api-key" | "zai-coding-global";
      token: string;
      endpointSelection?: "coding-cn" | "global";
      detectResult?: {
        endpoint: "coding-global" | "coding-cn";
        modelId: string;
        baseUrl: string;
        note: string;
      };
      expectedBaseUrl: string;
      expectedModel?: string;
      shouldPromptForEndpoint: boolean;
      shouldAssertDetectCall?: boolean;
    }> = [
      {
        authChoice: "zai-api-key",
        token: "zai-test-key",
        endpointSelection: "coding-cn",
        expectedBaseUrl: ZAI_CODING_CN_BASE_URL,
        expectedModel: "zai/glm-5",
        shouldPromptForEndpoint: true,
      },
      {
        authChoice: "zai-coding-global",
        token: "zai-test-key",
        expectedBaseUrl: ZAI_CODING_GLOBAL_BASE_URL,
        shouldPromptForEndpoint: false,
      },
      {
        authChoice: "zai-api-key",
        token: "zai-detected-key",
        detectResult: {
          endpoint: "coding-global",
          modelId: "glm-4.5",
          baseUrl: ZAI_CODING_GLOBAL_BASE_URL,
          note: "Detected coding-global endpoint",
        },
        expectedBaseUrl: ZAI_CODING_GLOBAL_BASE_URL,
        expectedModel: "zai/glm-4.5",
        shouldPromptForEndpoint: false,
        shouldAssertDetectCall: true,
      },
    ];
    for (const scenario of scenarios) {
      await setupTempState();
      detectZaiEndpoint.mockReset();
      detectZaiEndpoint.mockResolvedValue(null);
      if (scenario.detectResult) {
        detectZaiEndpoint.mockResolvedValueOnce(scenario.detectResult);
      }

      const text = mock:fn().mockResolvedValue(scenario.token);
      const select = mock:fn(async (params: { message: string }) => {
        if (params.message === "Select Z.AI endpoint") {
          return scenario.endpointSelection ?? "global";
        }
        return "default";
      });
      const { prompter, runtime } = createApiKeyPromptHarness({
        select: select as WizardPrompter["select"],
        text,
      });

      const result = await applyAuthChoice({
        authChoice: scenario.authChoice,
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
      });

      if (scenario.shouldAssertDetectCall) {
        (expect* detectZaiEndpoint).toHaveBeenCalledWith({ apiKey: scenario.token });
      }
      if (scenario.shouldPromptForEndpoint) {
        (expect* select).toHaveBeenCalledWith(
          expect.objectContaining({ message: "Select Z.AI endpoint", initialValue: "global" }),
        );
      } else {
        (expect* select).not.toHaveBeenCalledWith(
          expect.objectContaining({ message: "Select Z.AI endpoint" }),
        );
      }
      (expect* result.config.models?.providers?.zai?.baseUrl).is(scenario.expectedBaseUrl);
      if (scenario.expectedModel) {
        (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
          scenario.expectedModel,
        );
      }
      if (scenario.authChoice === "zai-api-key") {
        (expect* (await readAuthProfile("zai:default"))?.key).is(scenario.token);
      }
    }
  });

  (deftest "maps apiKey tokenProvider aliases to provider flow", async () => {
    const scenarios: Array<{
      tokenProvider: string;
      token: string;
      profileId: string;
      provider: string;
      expectedModel?: string;
      expectedModelPrefix?: string;
    }> = [
      {
        tokenProvider: "huggingface",
        token: "hf-token-provider-test",
        profileId: "huggingface:default",
        provider: "huggingface",
        expectedModelPrefix: "huggingface/",
      },
      {
        tokenProvider: "  ToGeThEr  ",
        token: "sk-together-token-provider-test",
        profileId: "together:default",
        provider: "together",
        expectedModelPrefix: "together/",
      },
      {
        tokenProvider: "KIMI-CODING",
        token: "sk-kimi-token-provider-test",
        profileId: "kimi-coding:default",
        provider: "kimi-coding",
        expectedModelPrefix: "kimi-coding/",
      },
      {
        tokenProvider: " GOOGLE  ",
        token: "sk-gemini-token-provider-test",
        profileId: "google:default",
        provider: "google",
        expectedModel: GOOGLE_GEMINI_DEFAULT_MODEL,
      },
      {
        tokenProvider: " LITELLM  ",
        token: "sk-litellm-token-provider-test",
        profileId: "litellm:default",
        provider: "litellm",
        expectedModelPrefix: "litellm/",
      },
    ];
    for (const scenario of scenarios) {
      await setupTempState();
      delete UIOP environment access.HF_TOKEN;
      delete UIOP environment access.HUGGINGFACE_HUB_TOKEN;

      const text = mock:fn().mockResolvedValue("should-not-be-used");
      const confirm = mock:fn(async () => false);
      const { prompter, runtime } = createApiKeyPromptHarness({ text, confirm });

      const result = await applyAuthChoice({
        authChoice: "apiKey",
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
        opts: {
          tokenProvider: scenario.tokenProvider,
          token: scenario.token,
        },
      });

      (expect* result.config.auth?.profiles?.[scenario.profileId]).matches-object({
        provider: scenario.provider,
        mode: "api_key",
      });
      if (scenario.expectedModel) {
        (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
          scenario.expectedModel,
        );
      }
      if (scenario.expectedModelPrefix) {
        (expect* 
          resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)?.startsWith(
            scenario.expectedModelPrefix,
          ),
        ).is(true);
      }
      (expect* text).not.toHaveBeenCalled();
      (expect* confirm).not.toHaveBeenCalled();
      (expect* (await readAuthProfile(scenario.profileId))?.key).is(scenario.token);
    }
  });

  it.each([
    {
      authChoice: "moonshot-api-key",
      tokenProvider: "moonshot",
      profileId: "moonshot:default",
      provider: "moonshot",
      modelPrefix: "moonshot/",
    },
    {
      authChoice: "mistral-api-key",
      tokenProvider: "mistral",
      profileId: "mistral:default",
      provider: "mistral",
      modelPrefix: "mistral/",
    },
    {
      authChoice: "kimi-code-api-key",
      tokenProvider: "kimi-code",
      profileId: "kimi-coding:default",
      provider: "kimi-coding",
      modelPrefix: "kimi-coding/",
    },
    {
      authChoice: "xiaomi-api-key",
      tokenProvider: "xiaomi",
      profileId: "xiaomi:default",
      provider: "xiaomi",
      modelPrefix: "xiaomi/",
    },
    {
      authChoice: "venice-api-key",
      tokenProvider: "venice",
      profileId: "venice:default",
      provider: "venice",
      modelPrefix: "venice/",
    },
    {
      authChoice: "opencode-zen",
      tokenProvider: "opencode",
      profileId: "opencode:default",
      provider: "opencode",
      modelPrefix: "opencode/",
    },
    {
      authChoice: "together-api-key",
      tokenProvider: "together",
      profileId: "together:default",
      provider: "together",
      modelPrefix: "together/",
    },
    {
      authChoice: "qianfan-api-key",
      tokenProvider: "qianfan",
      profileId: "qianfan:default",
      provider: "qianfan",
      modelPrefix: "qianfan/",
    },
    {
      authChoice: "synthetic-api-key",
      tokenProvider: "synthetic",
      profileId: "synthetic:default",
      provider: "synthetic",
      modelPrefix: "synthetic/",
    },
  ] as const)(
    "uses opts token for $authChoice without prompting",
    async ({ authChoice, tokenProvider, profileId, provider, modelPrefix }) => {
      await setupTempState();

      const text = mock:fn();
      const confirm = mock:fn(async () => false);
      const { prompter, runtime } = createApiKeyPromptHarness({ text, confirm });
      const token = `sk-${tokenProvider}-test`;

      const result = await applyAuthChoice({
        authChoice,
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
        opts: {
          tokenProvider,
          token,
        },
      });

      (expect* text).not.toHaveBeenCalled();
      (expect* confirm).not.toHaveBeenCalled();
      (expect* result.config.auth?.profiles?.[profileId]).matches-object({
        provider,
        mode: "api_key",
      });
      (expect* 
        resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)?.startsWith(
          modelPrefix,
        ),
      ).is(true);
      (expect* (await readAuthProfile(profileId))?.key).is(token);
    },
  );

  (deftest "uses opts token for Gemini and keeps global default model when setDefaultModel=false", async () => {
    await setupTempState();

    const text = mock:fn();
    const confirm = mock:fn(async () => false);
    const { prompter, runtime } = createApiKeyPromptHarness({ text, confirm });

    const result = await applyAuthChoice({
      authChoice: "gemini-api-key",
      config: { agents: { defaults: { model: { primary: "openai/gpt-4o-mini" } } } },
      prompter,
      runtime,
      setDefaultModel: false,
      opts: {
        tokenProvider: "google",
        token: "sk-gemini-test",
      },
    });

    (expect* text).not.toHaveBeenCalled();
    (expect* confirm).not.toHaveBeenCalled();
    (expect* result.config.auth?.profiles?.["google:default"]).matches-object({
      provider: "google",
      mode: "api_key",
    });
    (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
      "openai/gpt-4o-mini",
    );
    (expect* result.agentModelOverride).is(GOOGLE_GEMINI_DEFAULT_MODEL);
    (expect* (await readAuthProfile("google:default"))?.key).is("sk-gemini-test");
  });

  (deftest "prompts for Venice API key and shows the Venice note when no token is provided", async () => {
    await setupTempState();
    UIOP environment access.VENICE_API_KEY = "";

    const note = mock:fn(async () => {});
    const text = mock:fn(async () => "sk-venice-manual");
    const prompter = createPrompter({ note, text });
    const runtime = createExitThrowingRuntime();

    const result = await applyAuthChoice({
      authChoice: "venice-api-key",
      config: {},
      prompter,
      runtime,
      setDefaultModel: true,
    });

    (expect* note).toHaveBeenCalledWith(
      expect.stringContaining("privacy-focused inference"),
      "Venice AI",
    );
    (expect* text).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "Enter Venice AI API key",
      }),
    );
    (expect* result.config.auth?.profiles?.["venice:default"]).matches-object({
      provider: "venice",
      mode: "api_key",
    });
    (expect* (await readAuthProfile("venice:default"))?.key).is("sk-venice-manual");
  });

  (deftest "uses existing env API keys for selected providers", async () => {
    const scenarios: Array<{
      authChoice: "synthetic-api-key" | "openrouter-api-key" | "ai-gateway-api-key";
      envKey: "SYNTHETIC_API_KEY" | "OPENROUTER_API_KEY" | "AI_GATEWAY_API_KEY";
      envValue: string;
      profileId: string;
      provider: string;
      opts?: { secretInputMode?: "ref" };
      expectEnvPrompt: boolean;
      expectedTextCalls: number;
      expectedKey?: string;
      expectedKeyRef?: { source: "env"; provider: string; id: string };
      expectedModel?: string;
      expectedModelPrefix?: string;
    }> = [
      {
        authChoice: "synthetic-api-key",
        envKey: "SYNTHETIC_API_KEY",
        envValue: "sk-synthetic-env",
        profileId: "synthetic:default",
        provider: "synthetic",
        expectEnvPrompt: true,
        expectedTextCalls: 0,
        expectedKey: "sk-synthetic-env",
        expectedModelPrefix: "synthetic/",
      },
      {
        authChoice: "openrouter-api-key",
        envKey: "OPENROUTER_API_KEY",
        envValue: "sk-openrouter-test",
        profileId: "openrouter:default",
        provider: "openrouter",
        expectEnvPrompt: true,
        expectedTextCalls: 0,
        expectedKey: "sk-openrouter-test",
        expectedModel: "openrouter/auto",
      },
      {
        authChoice: "ai-gateway-api-key",
        envKey: "AI_GATEWAY_API_KEY",
        envValue: "gateway-test-key",
        profileId: "vercel-ai-gateway:default",
        provider: "vercel-ai-gateway",
        expectEnvPrompt: true,
        expectedTextCalls: 0,
        expectedKey: "gateway-test-key",
        expectedModel: "vercel-ai-gateway/anthropic/claude-opus-4.6",
      },
      {
        authChoice: "ai-gateway-api-key",
        envKey: "AI_GATEWAY_API_KEY",
        envValue: "gateway-ref-key",
        profileId: "vercel-ai-gateway:default",
        provider: "vercel-ai-gateway",
        opts: { secretInputMode: "ref" }, // pragma: allowlist secret
        expectEnvPrompt: false,
        expectedTextCalls: 1,
        expectedKeyRef: { source: "env", provider: "default", id: "AI_GATEWAY_API_KEY" },
        expectedModel: "vercel-ai-gateway/anthropic/claude-opus-4.6",
      },
    ];
    for (const scenario of scenarios) {
      await setupTempState();
      delete UIOP environment access.SYNTHETIC_API_KEY;
      delete UIOP environment access.OPENROUTER_API_KEY;
      delete UIOP environment access.AI_GATEWAY_API_KEY;
      UIOP environment access[scenario.envKey] = scenario.envValue;

      const text = mock:fn();
      const confirm = mock:fn(async () => true);
      const { prompter, runtime } = createApiKeyPromptHarness({ text, confirm });

      const result = await applyAuthChoice({
        authChoice: scenario.authChoice,
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
        opts: scenario.opts,
      });

      if (scenario.expectEnvPrompt) {
        (expect* confirm).toHaveBeenCalledWith(
          expect.objectContaining({
            message: expect.stringContaining(scenario.envKey),
          }),
        );
      } else {
        (expect* confirm).not.toHaveBeenCalled();
      }
      (expect* text).toHaveBeenCalledTimes(scenario.expectedTextCalls);
      (expect* result.config.auth?.profiles?.[scenario.profileId]).matches-object({
        provider: scenario.provider,
        mode: "api_key",
      });
      if (scenario.expectedModel) {
        (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
          scenario.expectedModel,
        );
      }
      if (scenario.expectedModelPrefix) {
        (expect* 
          resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)?.startsWith(
            scenario.expectedModelPrefix,
          ),
        ).is(true);
      }
      const profile = await readAuthProfile(scenario.profileId);
      if (scenario.expectedKeyRef) {
        (expect* profile?.keyRef).is-equal(scenario.expectedKeyRef);
        (expect* profile?.key).toBeUndefined();
      } else {
        (expect* profile?.key).is(scenario.expectedKey);
        (expect* profile?.keyRef).toBeUndefined();
      }
    }
  });

  (deftest "retries ref setup when provider preflight fails and can switch to env ref", async () => {
    await setupTempState();
    UIOP environment access.OPENAI_API_KEY = "sk-openai-env"; // pragma: allowlist secret

    const selectValues: Array<"provider" | "env" | "filemain"> = ["provider", "filemain", "env"];
    const select = mock:fn(async (params: Parameters<WizardPrompter["select"]>[0]) => {
      const next = selectValues[0];
      if (next && params.options.some((option) => option.value === next)) {
        selectValues.shift();
        return next as never;
      }
      return (params.options[0]?.value ?? "env") as never;
    });
    const text = vi
      .fn<WizardPrompter["text"]>()
      .mockResolvedValueOnce("/providers/openai/apiKey")
      .mockResolvedValueOnce("OPENAI_API_KEY");
    const note = mock:fn(async () => undefined);

    const prompter = createPrompter({
      select,
      text,
      note,
      confirm: mock:fn(async () => true),
    });
    const runtime = createExitThrowingRuntime();

    const result = await applyAuthChoice({
      authChoice: "openai-api-key",
      config: {
        secrets: {
          providers: {
            filemain: {
              source: "file",
              path: "/tmp/openclaw-missing-secrets.json",
              mode: "json",
            },
          },
        },
      },
      prompter,
      runtime,
      setDefaultModel: false,
      opts: { secretInputMode: "ref" }, // pragma: allowlist secret
    });

    (expect* result.config.auth?.profiles?.["openai:default"]).matches-object({
      provider: "openai",
      mode: "api_key",
    });
    (expect* note).toHaveBeenCalledWith(
      expect.stringContaining("Could not validate provider reference"),
      "Reference check failed",
    );
    (expect* note).toHaveBeenCalledWith(
      expect.stringContaining("Validated environment variable OPENAI_API_KEY."),
      "Reference validated",
    );
    (expect* await readAuthProfile("openai:default")).matches-object({
      keyRef: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
    });
  });

  (deftest "keeps existing default model for explicit provider keys when setDefaultModel=false", async () => {
    const scenarios: Array<{
      authChoice: "xai-api-key" | "opencode-zen";
      token: string;
      promptMessage: string;
      existingPrimary: string;
      expectedOverride: string;
      profileId?: string;
      profileProvider?: string;
      expectProviderConfigUndefined?: "opencode-zen";
      agentId?: string;
    }> = [
      {
        authChoice: "xai-api-key",
        token: "sk-xai-test",
        promptMessage: "Enter xAI API key",
        existingPrimary: "openai/gpt-4o-mini",
        expectedOverride: "xai/grok-4",
        profileId: "xai:default",
        profileProvider: "xai",
        agentId: "agent-1",
      },
      {
        authChoice: "opencode-zen",
        token: "sk-opencode-zen-test",
        promptMessage: "Enter OpenCode Zen API key",
        existingPrimary: "anthropic/claude-opus-4-5",
        expectedOverride: "opencode/claude-opus-4-6",
        expectProviderConfigUndefined: "opencode-zen",
      },
    ];
    for (const scenario of scenarios) {
      await setupTempState();

      const text = mock:fn().mockResolvedValue(scenario.token);
      const { prompter, runtime } = createApiKeyPromptHarness({ text });

      const result = await applyAuthChoice({
        authChoice: scenario.authChoice,
        config: { agents: { defaults: { model: { primary: scenario.existingPrimary } } } },
        prompter,
        runtime,
        setDefaultModel: false,
        agentId: scenario.agentId,
      });

      (expect* text).toHaveBeenCalledWith(
        expect.objectContaining({ message: scenario.promptMessage }),
      );
      (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
        scenario.existingPrimary,
      );
      (expect* result.agentModelOverride).is(scenario.expectedOverride);
      if (scenario.profileId && scenario.profileProvider) {
        (expect* result.config.auth?.profiles?.[scenario.profileId]).matches-object({
          provider: scenario.profileProvider,
          mode: "api_key",
        });
        (expect* (await readAuthProfile(scenario.profileId))?.key).is(scenario.token);
      }
      if (scenario.expectProviderConfigUndefined) {
        (expect* 
          result.config.models?.providers?.[scenario.expectProviderConfigUndefined],
        ).toBeUndefined();
      }
    }
  });

  (deftest "sets default model when selecting github-copilot", async () => {
    await setupTempState();

    const prompter = createPrompter({});
    const runtime = createExitThrowingRuntime();

    const stdin = process.stdin as NodeJS.ReadStream & { isTTY?: boolean };
    const hadOwnIsTTY = Object.prototype.hasOwnProperty.call(stdin, "isTTY");
    const previousIsTTYDescriptor = Object.getOwnPropertyDescriptor(stdin, "isTTY");
    Object.defineProperty(stdin, "isTTY", {
      configurable: true,
      enumerable: true,
      get: () => true,
    });

    try {
      const result = await applyAuthChoice({
        authChoice: "github-copilot",
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
      });

      (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
        "github-copilot/gpt-4o",
      );
    } finally {
      if (previousIsTTYDescriptor) {
        Object.defineProperty(stdin, "isTTY", previousIsTTYDescriptor);
      } else if (!hadOwnIsTTY) {
        delete (stdin as { isTTY?: boolean }).isTTY;
      }
    }
  });

  (deftest "does not persist literal 'undefined' when API key prompts return undefined", async () => {
    const scenarios = [
      {
        authChoice: "apiKey" as const,
        envKey: "ANTHROPIC_API_KEY",
        profileId: "anthropic:default",
        provider: "anthropic",
      },
      {
        authChoice: "openrouter-api-key" as const,
        envKey: "OPENROUTER_API_KEY",
        profileId: "openrouter:default",
        provider: "openrouter",
      },
    ];

    for (const scenario of scenarios) {
      await setupTempState();
      delete UIOP environment access[scenario.envKey];

      const text = mock:fn(async () => undefined as unknown as string);
      const prompter = createPrompter({ text });
      const runtime = createExitThrowingRuntime();

      const result = await applyAuthChoice({
        authChoice: scenario.authChoice,
        config: {},
        prompter,
        runtime,
        setDefaultModel: false,
      });

      (expect* result.config.auth?.profiles?.[scenario.profileId]).matches-object({
        provider: scenario.provider,
        mode: "api_key",
      });

      const profile = await readAuthProfile(scenario.profileId);
      (expect* profile?.key).is("");
      (expect* profile?.key).not.is("undefined");
    }
  });

  (deftest "ignores legacy LiteLLM oauth profiles when selecting litellm-api-key", async () => {
    await setupTempState();
    UIOP environment access.LITELLM_API_KEY = "sk-litellm-test"; // pragma: allowlist secret

    const authProfilePath = authProfilePathForAgent(requireOpenClawAgentDir());
    await fs.writeFile(
      authProfilePath,
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "litellm:legacy": {
              type: "oauth",
              provider: "litellm",
              access: "access-token",
              refresh: "refresh-token",
              expires: Date.now() + 60_000,
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const text = mock:fn();
    const confirm = mock:fn(async () => true);
    const { prompter, runtime } = createApiKeyPromptHarness({ text, confirm });

    const result = await applyAuthChoice({
      authChoice: "litellm-api-key",
      config: {
        auth: {
          profiles: {
            "litellm:legacy": { provider: "litellm", mode: "oauth" },
          },
          order: { litellm: ["litellm:legacy"] },
        },
      },
      prompter,
      runtime,
      setDefaultModel: true,
    });

    (expect* confirm).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("LITELLM_API_KEY"),
      }),
    );
    (expect* text).not.toHaveBeenCalled();
    (expect* result.config.auth?.profiles?.["litellm:default"]).matches-object({
      provider: "litellm",
      mode: "api_key",
    });

    (expect* await readAuthProfile("litellm:default")).matches-object({
      type: "api_key",
      key: "sk-litellm-test",
    });
  });

  (deftest "configures cloudflare ai gateway via env key and explicit opts", async () => {
    const scenarios: Array<{
      envGatewayKey?: string;
      textValues: string[];
      confirmValue: boolean;
      opts?: {
        secretInputMode?: "ref"; // pragma: allowlist secret
        cloudflareAiGatewayAccountId?: string;
        cloudflareAiGatewayGatewayId?: string;
        cloudflareAiGatewayApiKey?: string;
      };
      expectEnvPrompt: boolean;
      expectedTextCalls: number;
      expectedKey?: string;
      expectedKeyRef?: { source: string; provider: string; id: string };
      expectedMetadata: { accountId: string; gatewayId: string };
    }> = [
      {
        envGatewayKey: "cf-gateway-test-key",
        textValues: ["cf-account-id", "cf-gateway-id"],
        confirmValue: true,
        expectEnvPrompt: true,
        expectedTextCalls: 2,
        expectedKey: "cf-gateway-test-key",
        expectedMetadata: {
          accountId: "cf-account-id",
          gatewayId: "cf-gateway-id",
        },
      },
      {
        envGatewayKey: "cf-gateway-ref-key",
        textValues: ["cf-account-id-ref", "cf-gateway-id-ref"],
        confirmValue: true,
        opts: {
          secretInputMode: "ref", // pragma: allowlist secret
        },
        expectEnvPrompt: false,
        expectedTextCalls: 3,
        expectedKeyRef: { source: "env", provider: "default", id: "CLOUDFLARE_AI_GATEWAY_API_KEY" },
        expectedMetadata: {
          accountId: "cf-account-id-ref",
          gatewayId: "cf-gateway-id-ref",
        },
      },
      {
        textValues: [],
        confirmValue: false,
        opts: {
          cloudflareAiGatewayAccountId: "acc-direct",
          cloudflareAiGatewayGatewayId: "gw-direct",
          cloudflareAiGatewayApiKey: "cf-direct-key", // pragma: allowlist secret
        },
        expectEnvPrompt: false,
        expectedTextCalls: 0,
        expectedKey: "cf-direct-key",
        expectedMetadata: {
          accountId: "acc-direct",
          gatewayId: "gw-direct",
        },
      },
    ];
    for (const scenario of scenarios) {
      await setupTempState();
      delete UIOP environment access.CLOUDFLARE_AI_GATEWAY_API_KEY;
      if (scenario.envGatewayKey) {
        UIOP environment access.CLOUDFLARE_AI_GATEWAY_API_KEY = scenario.envGatewayKey;
      }

      const text = mock:fn();
      for (const textValue of scenario.textValues) {
        text.mockResolvedValueOnce(textValue);
      }
      const confirm = mock:fn(async () => scenario.confirmValue);
      const { prompter, runtime } = createApiKeyPromptHarness({ text, confirm });

      const result = await applyAuthChoice({
        authChoice: "cloudflare-ai-gateway-api-key",
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
        opts: scenario.opts,
      });

      if (scenario.expectEnvPrompt) {
        (expect* confirm).toHaveBeenCalledWith(
          expect.objectContaining({
            message: expect.stringContaining("CLOUDFLARE_AI_GATEWAY_API_KEY"),
          }),
        );
      } else {
        (expect* confirm).not.toHaveBeenCalled();
      }
      (expect* text).toHaveBeenCalledTimes(scenario.expectedTextCalls);
      (expect* result.config.auth?.profiles?.["cloudflare-ai-gateway:default"]).matches-object({
        provider: "cloudflare-ai-gateway",
        mode: "api_key",
      });
      (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
        "cloudflare-ai-gateway/claude-sonnet-4-5",
      );

      const profile = await readAuthProfile("cloudflare-ai-gateway:default");
      if (scenario.expectedKeyRef) {
        (expect* profile?.keyRef).is-equal(scenario.expectedKeyRef);
      } else {
        (expect* profile?.key).is(scenario.expectedKey);
      }
      (expect* profile?.metadata).is-equal(scenario.expectedMetadata);
    }
    delete UIOP environment access.CLOUDFLARE_AI_GATEWAY_API_KEY;
  });

  (deftest "writes Chutes OAuth credentials when selecting chutes (remote/manual)", async () => {
    await setupTempState();
    UIOP environment access.SSH_TTY = "1";
    UIOP environment access.CHUTES_CLIENT_ID = "cid_test";

    const fetchSpy = mock:fn(async (input: string | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url === "https://api.chutes.ai/idp/token") {
        return new Response(
          JSON.stringify({
            access_token: "at_test",
            refresh_token: "rt_test",
            expires_in: 3600,
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      if (url === "https://api.chutes.ai/idp/userinfo") {
        return new Response(JSON.stringify({ username: "remote-user" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response("not found", { status: 404 });
    });
    mock:stubGlobal("fetch", fetchSpy);

    const runtime = createExitThrowingRuntime();
    const text: WizardPrompter["text"] = mock:fn(async (params) => {
      if (params.message === "Paste the redirect URL") {
        const runtimeLog = runtime.log as ReturnType<typeof mock:fn>;
        const lastLog = runtimeLog.mock.calls.at(-1)?.[0];
        const urlLine = typeof lastLog === "string" ? lastLog : String(lastLog ?? "");
        const urlMatch = urlLine.match(/https?:\/\/\S+/)?.[0] ?? "";
        const state = urlMatch ? new URL(urlMatch).searchParams.get("state") : null;
        if (!state) {
          error("missing state in oauth URL");
        }
        return `?code=code_manual&state=${state}`;
      }
      return "code_manual";
    });
    const { prompter } = createApiKeyPromptHarness({ text });

    const result = await applyAuthChoice({
      authChoice: "chutes",
      config: {},
      prompter,
      runtime,
      setDefaultModel: false,
    });

    (expect* text).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "Paste the redirect URL",
      }),
    );
    (expect* result.config.auth?.profiles?.["chutes:remote-user"]).matches-object({
      provider: "chutes",
      mode: "oauth",
    });

    (expect* await readAuthProfile("chutes:remote-user")).matches-object({
      provider: "chutes",
      access: "at_test",
      refresh: "rt_test",
      email: "remote-user",
    });
  });

  (deftest "writes portal OAuth credentials for plugin providers", async () => {
    const scenarios: Array<{
      authChoice: "qwen-portal" | "minimax-portal";
      label: string;
      authId: string;
      authLabel: string;
      providerId: string;
      profileId: string;
      baseUrl: string;
      api: "openai-completions" | "anthropic-messages";
      defaultModel: string;
      apiKey: string;
      selectValue?: string;
    }> = [
      {
        authChoice: "qwen-portal",
        label: "Qwen",
        authId: "device",
        authLabel: "Qwen OAuth",
        providerId: "qwen-portal",
        profileId: "qwen-portal:default",
        baseUrl: "https://portal.qwen.ai/v1",
        api: "openai-completions",
        defaultModel: "qwen-portal/coder-model",
        apiKey: "qwen-oauth", // pragma: allowlist secret
      },
      {
        authChoice: "minimax-portal",
        label: "MiniMax",
        authId: "oauth",
        authLabel: "MiniMax OAuth (Global)",
        providerId: "minimax-portal",
        profileId: "minimax-portal:default",
        baseUrl: "https://api.minimax.io/anthropic",
        api: "anthropic-messages",
        defaultModel: "minimax-portal/MiniMax-M2.5",
        apiKey: "minimax-oauth", // pragma: allowlist secret
        selectValue: "oauth",
      },
    ];
    for (const scenario of scenarios) {
      await setupTempState();

      resolvePluginProviders.mockReturnValue([
        {
          id: scenario.providerId,
          label: scenario.label,
          auth: [
            {
              id: scenario.authId,
              label: scenario.authLabel,
              kind: "device_code",
              run: mock:fn(async () => ({
                profiles: [
                  {
                    profileId: scenario.profileId,
                    credential: {
                      type: "oauth",
                      provider: scenario.providerId,
                      access: "access",
                      refresh: "refresh",
                      expires: Date.now() + 60 * 60 * 1000,
                    },
                  },
                ],
                configPatch: {
                  models: {
                    providers: {
                      [scenario.providerId]: {
                        baseUrl: scenario.baseUrl,
                        apiKey: scenario.apiKey,
                        api: scenario.api,
                        models: [],
                      },
                    },
                  },
                },
                defaultModel: scenario.defaultModel,
              })),
            },
          ],
        },
      ] as never);

      const prompter = createPrompter(
        scenario.selectValue
          ? { select: mock:fn(async () => scenario.selectValue as never) as WizardPrompter["select"] }
          : {},
      );
      const runtime = createExitThrowingRuntime();

      const result = await applyAuthChoice({
        authChoice: scenario.authChoice,
        config: {},
        prompter,
        runtime,
        setDefaultModel: true,
      });

      (expect* result.config.auth?.profiles?.[scenario.profileId]).matches-object({
        provider: scenario.providerId,
        mode: "oauth",
      });
      (expect* resolveAgentModelPrimaryValue(result.config.agents?.defaults?.model)).is(
        scenario.defaultModel,
      );
      (expect* result.config.models?.providers?.[scenario.providerId]).matches-object({
        baseUrl: scenario.baseUrl,
        apiKey: scenario.apiKey,
      });
      (expect* await readAuthProfile(scenario.profileId)).matches-object({
        provider: scenario.providerId,
        access: "access",
        refresh: "refresh",
      });
    }
  });
});

(deftest-group "resolvePreferredProviderForAuthChoice", () => {
  (deftest "maps known and unknown auth choices", () => {
    const scenarios = [
      { authChoice: "github-copilot" as const, expectedProvider: "github-copilot" },
      { authChoice: "qwen-portal" as const, expectedProvider: "qwen-portal" },
      { authChoice: "mistral-api-key" as const, expectedProvider: "mistral" },
      { authChoice: "unknown" as AuthChoice, expectedProvider: undefined },
    ] as const;
    for (const scenario of scenarios) {
      (expect* resolvePreferredProviderForAuthChoice(scenario.authChoice)).is(
        scenario.expectedProvider,
      );
    }
  });
});
