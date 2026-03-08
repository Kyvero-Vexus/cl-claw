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
import path from "sbcl:path";
import { setTimeout as delay } from "sbcl:timers/promises";
import { beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { makeTempWorkspace } from "../test-helpers/workspace.js";
import { withEnvAsync } from "../test-utils/env.js";
import { MINIMAX_API_BASE_URL, MINIMAX_CN_API_BASE_URL } from "./onboard-auth.js";
import {
  createThrowingRuntime,
  readJsonFile,
  type NonInteractiveRuntime,
} from "./onboard-non-interactive.test-helpers.js";
import { OPENAI_DEFAULT_MODEL } from "./openai-model-default.js";

type OnboardEnv = {
  configPath: string;
  runtime: NonInteractiveRuntime;
};

const ensureWorkspaceAndSessionsMock = mock:fn(async (..._args: unknown[]) => {});

mock:mock("./onboard-helpers.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./onboard-helpers.js")>();
  return {
    ...actual,
    ensureWorkspaceAndSessions: ensureWorkspaceAndSessionsMock,
  };
});

const { runNonInteractiveOnboarding } = await import("./onboard-non-interactive.js");

const NON_INTERACTIVE_DEFAULT_OPTIONS = {
  nonInteractive: true,
  skipHealth: true,
  skipChannels: true,
  json: true,
} as const;

let ensureAuthProfileStore: typeof import("../agents/auth-profiles.js").ensureAuthProfileStore;
let upsertAuthProfile: typeof import("../agents/auth-profiles.js").upsertAuthProfile;

type ProviderAuthConfigSnapshot = {
  auth?: { profiles?: Record<string, { provider?: string; mode?: string }> };
  agents?: { defaults?: { model?: { primary?: string } } };
  models?: {
    providers?: Record<
      string,
      {
        baseUrl?: string;
        api?: string;
        apiKey?: string | { source?: string; id?: string };
        models?: Array<{ id?: string }>;
      }
    >;
  };
};

async function removeDirWithRetry(dir: string): deferred-result<void> {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      await fs.rm(dir, { recursive: true, force: true });
      return;
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      const isTransient = code === "ENOTEMPTY" || code === "EBUSY" || code === "EPERM";
      if (!isTransient || attempt === 4) {
        throw error;
      }
      await delay(10 * (attempt + 1));
    }
  }
}

async function withOnboardEnv(
  prefix: string,
  run: (ctx: OnboardEnv) => deferred-result<void>,
): deferred-result<void> {
  const tempHome = await makeTempWorkspace(prefix);
  const configPath = path.join(tempHome, "openclaw.json");
  const runtime = createThrowingRuntime();

  try {
    await withEnvAsync(
      {
        HOME: tempHome,
        OPENCLAW_STATE_DIR: tempHome,
        OPENCLAW_CONFIG_PATH: configPath,
        OPENCLAW_SKIP_CHANNELS: "1",
        OPENCLAW_SKIP_GMAIL_WATCHER: "1",
        OPENCLAW_SKIP_CRON: "1",
        OPENCLAW_SKIP_CANVAS_HOST: "1",
        OPENCLAW_GATEWAY_TOKEN: undefined,
        OPENCLAW_GATEWAY_PASSWORD: undefined,
        CUSTOM_API_KEY: undefined,
        OPENCLAW_DISABLE_CONFIG_CACHE: "1",
      },
      async () => {
        await run({ configPath, runtime });
      },
    );
  } finally {
    await removeDirWithRetry(tempHome);
  }
}

async function runNonInteractiveOnboardingWithDefaults(
  runtime: NonInteractiveRuntime,
  options: Record<string, unknown>,
): deferred-result<void> {
  await runNonInteractiveOnboarding(
    {
      ...NON_INTERACTIVE_DEFAULT_OPTIONS,
      ...options,
    },
    runtime,
  );
}

async function runOnboardingAndReadConfig(
  env: OnboardEnv,
  options: Record<string, unknown>,
): deferred-result<ProviderAuthConfigSnapshot> {
  await runNonInteractiveOnboardingWithDefaults(env.runtime, {
    skipSkills: true,
    ...options,
  });
  return readJsonFile<ProviderAuthConfigSnapshot>(env.configPath);
}

const CUSTOM_LOCAL_BASE_URL = "https://models.custom.local/v1";
const CUSTOM_LOCAL_MODEL_ID = "local-large";
const CUSTOM_LOCAL_PROVIDER_ID = "custom-models-custom-local";

async function runCustomLocalNonInteractive(
  runtime: NonInteractiveRuntime,
  overrides: Record<string, unknown> = {},
): deferred-result<void> {
  await runNonInteractiveOnboardingWithDefaults(runtime, {
    authChoice: "custom-api-key",
    customBaseUrl: CUSTOM_LOCAL_BASE_URL,
    customModelId: CUSTOM_LOCAL_MODEL_ID,
    skipSkills: true,
    ...overrides,
  });
}

async function readCustomLocalProviderApiKey(configPath: string): deferred-result<string | undefined> {
  const cfg = await readJsonFile<ProviderAuthConfigSnapshot>(configPath);
  const apiKey = cfg.models?.providers?.[CUSTOM_LOCAL_PROVIDER_ID]?.apiKey;
  return typeof apiKey === "string" ? apiKey : undefined;
}

async function readCustomLocalProviderApiKeyInput(
  configPath: string,
): deferred-result<string | { source?: string; id?: string } | undefined> {
  const cfg = await readJsonFile<ProviderAuthConfigSnapshot>(configPath);
  return cfg.models?.providers?.[CUSTOM_LOCAL_PROVIDER_ID]?.apiKey;
}

async function expectApiKeyProfile(params: {
  profileId: string;
  provider: string;
  key: string;
  metadata?: Record<string, string>;
}): deferred-result<void> {
  const store = ensureAuthProfileStore();
  const profile = store.profiles[params.profileId];
  (expect* profile?.type).is("api_key");
  if (profile?.type === "api_key") {
    (expect* profile.provider).is(params.provider);
    (expect* profile.key).is(params.key);
    if (params.metadata) {
      (expect* profile.metadata).is-equal(params.metadata);
    }
  }
}

(deftest-group "onboard (non-interactive): provider auth", () => {
  beforeAll(async () => {
    ({ ensureAuthProfileStore, upsertAuthProfile } = await import("../agents/auth-profiles.js"));
  });

  (deftest "stores MiniMax API key and uses global baseUrl by default", async () => {
    await withOnboardEnv("openclaw-onboard-minimax-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "minimax-api",
        minimaxApiKey: "sk-minimax-test", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["minimax:default"]?.provider).is("minimax");
      (expect* cfg.auth?.profiles?.["minimax:default"]?.mode).is("api_key");
      (expect* cfg.models?.providers?.minimax?.baseUrl).is(MINIMAX_API_BASE_URL);
      (expect* cfg.agents?.defaults?.model?.primary).is("minimax/MiniMax-M2.5");
      await expectApiKeyProfile({
        profileId: "minimax:default",
        provider: "minimax",
        key: "sk-minimax-test",
      });
    });
  });

  (deftest "supports MiniMax CN API endpoint auth choice", async () => {
    await withOnboardEnv("openclaw-onboard-minimax-cn-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "minimax-api-key-cn",
        minimaxApiKey: "sk-minimax-test", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["minimax-cn:default"]?.provider).is("minimax-cn");
      (expect* cfg.auth?.profiles?.["minimax-cn:default"]?.mode).is("api_key");
      (expect* cfg.models?.providers?.["minimax-cn"]?.baseUrl).is(MINIMAX_CN_API_BASE_URL);
      (expect* cfg.agents?.defaults?.model?.primary).is("minimax-cn/MiniMax-M2.5");
      await expectApiKeyProfile({
        profileId: "minimax-cn:default",
        provider: "minimax-cn",
        key: "sk-minimax-test",
      });
    });
  });

  (deftest "stores Z.AI API key and uses global baseUrl by default", async () => {
    await withOnboardEnv("openclaw-onboard-zai-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "zai-api-key",
        zaiApiKey: "zai-test-key", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["zai:default"]?.provider).is("zai");
      (expect* cfg.auth?.profiles?.["zai:default"]?.mode).is("api_key");
      (expect* cfg.models?.providers?.zai?.baseUrl).is("https://api.z.ai/api/paas/v4");
      (expect* cfg.agents?.defaults?.model?.primary).is("zai/glm-5");
      await expectApiKeyProfile({ profileId: "zai:default", provider: "zai", key: "zai-test-key" });
    });
  });

  (deftest "supports Z.AI CN coding endpoint auth choice", async () => {
    await withOnboardEnv("openclaw-onboard-zai-cn-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "zai-coding-cn",
        zaiApiKey: "zai-test-key", // pragma: allowlist secret
      });

      (expect* cfg.models?.providers?.zai?.baseUrl).is(
        "https://open.bigmodel.cn/api/coding/paas/v4",
      );
    });
  });

  (deftest "stores xAI API key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-xai-", async (env) => {
      const rawKey = "xai-test-\r\nkey";
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "xai-api-key",
        xaiApiKey: rawKey,
      });

      (expect* cfg.auth?.profiles?.["xai:default"]?.provider).is("xai");
      (expect* cfg.auth?.profiles?.["xai:default"]?.mode).is("api_key");
      (expect* cfg.agents?.defaults?.model?.primary).is("xai/grok-4");
      await expectApiKeyProfile({ profileId: "xai:default", provider: "xai", key: "xai-test-key" });
    });
  });

  (deftest "infers Mistral auth choice from --mistral-api-key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-mistral-infer-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        mistralApiKey: "mistral-test-key", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["mistral:default"]?.provider).is("mistral");
      (expect* cfg.auth?.profiles?.["mistral:default"]?.mode).is("api_key");
      (expect* cfg.agents?.defaults?.model?.primary).is("mistral/mistral-large-latest");
      await expectApiKeyProfile({
        profileId: "mistral:default",
        provider: "mistral",
        key: "mistral-test-key",
      });
    });
  });

  (deftest "stores Volcano Engine API key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-volcengine-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "volcengine-api-key",
        volcengineApiKey: "volcengine-test-key", // pragma: allowlist secret
      });

      (expect* cfg.agents?.defaults?.model?.primary).is("volcengine-plan/ark-code-latest");
    });
  });

  (deftest "infers BytePlus auth choice from --byteplus-api-key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-byteplus-infer-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        byteplusApiKey: "byteplus-test-key", // pragma: allowlist secret
      });

      (expect* cfg.agents?.defaults?.model?.primary).is("byteplus-plan/ark-code-latest");
    });
  });

  (deftest "stores Vercel AI Gateway API key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-ai-gateway-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "ai-gateway-api-key",
        aiGatewayApiKey: "gateway-test-key", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["vercel-ai-gateway:default"]?.provider).is("vercel-ai-gateway");
      (expect* cfg.auth?.profiles?.["vercel-ai-gateway:default"]?.mode).is("api_key");
      (expect* cfg.agents?.defaults?.model?.primary).is(
        "vercel-ai-gateway/anthropic/claude-opus-4.6",
      );
      await expectApiKeyProfile({
        profileId: "vercel-ai-gateway:default",
        provider: "vercel-ai-gateway",
        key: "gateway-test-key",
      });
    });
  });

  (deftest "stores token auth profile", async () => {
    await withOnboardEnv("openclaw-onboard-token-", async ({ configPath, runtime }) => {
      const cleanToken = `sk-ant-oat01-${"a".repeat(80)}`;
      const token = `${cleanToken.slice(0, 30)}\r${cleanToken.slice(30)}`;

      await runNonInteractiveOnboardingWithDefaults(runtime, {
        authChoice: "token",
        tokenProvider: "anthropic",
        token,
        tokenProfileId: "anthropic:default",
      });

      const cfg = await readJsonFile<ProviderAuthConfigSnapshot>(configPath);

      (expect* cfg.auth?.profiles?.["anthropic:default"]?.provider).is("anthropic");
      (expect* cfg.auth?.profiles?.["anthropic:default"]?.mode).is("token");

      const store = ensureAuthProfileStore();
      const profile = store.profiles["anthropic:default"];
      (expect* profile?.type).is("token");
      if (profile?.type === "token") {
        (expect* profile.provider).is("anthropic");
        (expect* profile.token).is(cleanToken);
      }
    });
  });

  (deftest "stores OpenAI API key and sets OpenAI default model", async () => {
    await withOnboardEnv("openclaw-onboard-openai-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "openai-api-key",
        openaiApiKey: "sk-openai-test", // pragma: allowlist secret
      });

      (expect* cfg.agents?.defaults?.model?.primary).is(OPENAI_DEFAULT_MODEL);
    });
  });

  it.each([
    {
      name: "anthropic",
      prefix: "openclaw-onboard-ref-flag-anthropic-",
      authChoice: "apiKey",
      optionKey: "anthropicApiKey",
      flagName: "--anthropic-api-key",
      envVar: "ANTHROPIC_API_KEY",
    },
    {
      name: "openai",
      prefix: "openclaw-onboard-ref-flag-openai-",
      authChoice: "openai-api-key",
      optionKey: "openaiApiKey",
      flagName: "--openai-api-key",
      envVar: "OPENAI_API_KEY",
    },
    {
      name: "openrouter",
      prefix: "openclaw-onboard-ref-flag-openrouter-",
      authChoice: "openrouter-api-key",
      optionKey: "openrouterApiKey",
      flagName: "--openrouter-api-key",
      envVar: "OPENROUTER_API_KEY",
    },
    {
      name: "xai",
      prefix: "openclaw-onboard-ref-flag-xai-",
      authChoice: "xai-api-key",
      optionKey: "xaiApiKey",
      flagName: "--xai-api-key",
      envVar: "XAI_API_KEY",
    },
    {
      name: "volcengine",
      prefix: "openclaw-onboard-ref-flag-volcengine-",
      authChoice: "volcengine-api-key",
      optionKey: "volcengineApiKey",
      flagName: "--volcengine-api-key",
      envVar: "VOLCANO_ENGINE_API_KEY",
    },
    {
      name: "byteplus",
      prefix: "openclaw-onboard-ref-flag-byteplus-",
      authChoice: "byteplus-api-key",
      optionKey: "byteplusApiKey",
      flagName: "--byteplus-api-key",
      envVar: "BYTEPLUS_API_KEY",
    },
  ])(
    "fails fast for $name when --secret-input-mode ref uses explicit key without env and does not leak the key",
    async ({ prefix, authChoice, optionKey, flagName, envVar }) => {
      await withOnboardEnv(prefix, async ({ runtime }) => {
        const providedSecret = `${envVar.toLowerCase()}-should-not-leak`; // pragma: allowlist secret
        const options: Record<string, unknown> = {
          authChoice,
          secretInputMode: "ref", // pragma: allowlist secret
          [optionKey]: providedSecret,
          skipSkills: true,
        };
        const envOverrides: Record<string, string | undefined> = {
          [envVar]: undefined,
        };

        await withEnvAsync(envOverrides, async () => {
          let thrown: Error | undefined;
          try {
            await runNonInteractiveOnboardingWithDefaults(runtime, options);
          } catch (error) {
            thrown = error as Error;
          }
          (expect* thrown).toBeDefined();
          const message = String(thrown?.message ?? "");
          (expect* message).contains(
            `${flagName} cannot be used with --secret-input-mode ref unless ${envVar} is set in env.`,
          );
          (expect* message).contains(
            `Set ${envVar} in env and omit ${flagName}, or use --secret-input-mode plaintext.`,
          );
          (expect* message).not.contains(providedSecret);
        });
      });
    },
  );

  (deftest "stores the detected env alias as keyRef for opencode ref mode", async () => {
    await withOnboardEnv("openclaw-onboard-ref-opencode-alias-", async ({ runtime }) => {
      await withEnvAsync(
        {
          OPENCODE_API_KEY: undefined,
          OPENCODE_ZEN_API_KEY: "opencode-zen-env-key", // pragma: allowlist secret
        },
        async () => {
          await runNonInteractiveOnboardingWithDefaults(runtime, {
            authChoice: "opencode-zen",
            secretInputMode: "ref", // pragma: allowlist secret
            skipSkills: true,
          });

          const store = ensureAuthProfileStore();
          const profile = store.profiles["opencode:default"];
          (expect* profile?.type).is("api_key");
          if (profile?.type === "api_key") {
            (expect* profile.key).toBeUndefined();
            (expect* profile.keyRef).is-equal({
              source: "env",
              provider: "default",
              id: "OPENCODE_ZEN_API_KEY",
            });
          }
        },
      );
    });
  });

  (deftest "rejects vLLM auth choice in non-interactive mode", async () => {
    await withOnboardEnv("openclaw-onboard-vllm-non-interactive-", async ({ runtime }) => {
      await (expect* 
        runNonInteractiveOnboardingWithDefaults(runtime, {
          authChoice: "vllm",
          skipSkills: true,
        }),
      ).rejects.signals-error('Auth choice "vllm" requires interactive mode.');
    });
  });

  (deftest "stores LiteLLM API key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-litellm-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        authChoice: "litellm-api-key",
        litellmApiKey: "litellm-test-key", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["litellm:default"]?.provider).is("litellm");
      (expect* cfg.auth?.profiles?.["litellm:default"]?.mode).is("api_key");
      (expect* cfg.agents?.defaults?.model?.primary).is("litellm/claude-opus-4-6");
      await expectApiKeyProfile({
        profileId: "litellm:default",
        provider: "litellm",
        key: "litellm-test-key",
      });
    });
  });

  it.each([
    {
      name: "stores Cloudflare AI Gateway API key and metadata",
      prefix: "openclaw-onboard-cf-gateway-",
      options: {
        authChoice: "cloudflare-ai-gateway-api-key",
      },
    },
    {
      name: "infers Cloudflare auth choice from API key flags",
      prefix: "openclaw-onboard-cf-gateway-infer-",
      options: {},
    },
  ])("$name", async ({ prefix, options }) => {
    await withOnboardEnv(prefix, async ({ configPath, runtime }) => {
      await runNonInteractiveOnboardingWithDefaults(runtime, {
        cloudflareAiGatewayAccountId: "cf-account-id",
        cloudflareAiGatewayGatewayId: "cf-gateway-id",
        cloudflareAiGatewayApiKey: "cf-gateway-test-key", // pragma: allowlist secret
        skipSkills: true,
        ...options,
      });

      const cfg = await readJsonFile<ProviderAuthConfigSnapshot>(configPath);

      (expect* cfg.auth?.profiles?.["cloudflare-ai-gateway:default"]?.provider).is(
        "cloudflare-ai-gateway",
      );
      (expect* cfg.auth?.profiles?.["cloudflare-ai-gateway:default"]?.mode).is("api_key");
      (expect* cfg.agents?.defaults?.model?.primary).is("cloudflare-ai-gateway/claude-sonnet-4-5");
      await expectApiKeyProfile({
        profileId: "cloudflare-ai-gateway:default",
        provider: "cloudflare-ai-gateway",
        key: "cf-gateway-test-key",
        metadata: { accountId: "cf-account-id", gatewayId: "cf-gateway-id" },
      });
    });
  });

  (deftest "infers Together auth choice from --together-api-key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-together-infer-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        togetherApiKey: "together-test-key", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["together:default"]?.provider).is("together");
      (expect* cfg.auth?.profiles?.["together:default"]?.mode).is("api_key");
      (expect* cfg.agents?.defaults?.model?.primary).is("together/moonshotai/Kimi-K2.5");
      await expectApiKeyProfile({
        profileId: "together:default",
        provider: "together",
        key: "together-test-key",
      });
    });
  });

  (deftest "infers QIANFAN auth choice from --qianfan-api-key and sets default model", async () => {
    await withOnboardEnv("openclaw-onboard-qianfan-infer-", async (env) => {
      const cfg = await runOnboardingAndReadConfig(env, {
        qianfanApiKey: "qianfan-test-key", // pragma: allowlist secret
      });

      (expect* cfg.auth?.profiles?.["qianfan:default"]?.provider).is("qianfan");
      (expect* cfg.auth?.profiles?.["qianfan:default"]?.mode).is("api_key");
      (expect* cfg.agents?.defaults?.model?.primary).is("qianfan/deepseek-v3.2");
      await expectApiKeyProfile({
        profileId: "qianfan:default",
        provider: "qianfan",
        key: "qianfan-test-key",
      });
    });
  });

  (deftest "configures a custom provider from non-interactive flags", async () => {
    await withOnboardEnv("openclaw-onboard-custom-provider-", async ({ configPath, runtime }) => {
      await runNonInteractiveOnboardingWithDefaults(runtime, {
        authChoice: "custom-api-key",
        customBaseUrl: "https://llm.example.com/v1",
        customApiKey: "custom-test-key", // pragma: allowlist secret
        customModelId: "foo-large",
        customCompatibility: "anthropic",
        skipSkills: true,
      });

      const cfg = await readJsonFile<ProviderAuthConfigSnapshot>(configPath);

      const provider = cfg.models?.providers?.["custom-llm-example-com"];
      (expect* provider?.baseUrl).is("https://llm.example.com/v1");
      (expect* provider?.api).is("anthropic-messages");
      (expect* provider?.apiKey).is("custom-test-key");
      (expect* provider?.models?.some((model) => model.id === "foo-large")).is(true);
      (expect* cfg.agents?.defaults?.model?.primary).is("custom-llm-example-com/foo-large");
    });
  });

  (deftest "infers custom provider auth choice from custom flags", async () => {
    await withOnboardEnv(
      "openclaw-onboard-custom-provider-infer-",
      async ({ configPath, runtime }) => {
        await runNonInteractiveOnboardingWithDefaults(runtime, {
          customBaseUrl: "https://models.custom.local/v1",
          customModelId: "local-large",
          customApiKey: "custom-test-key", // pragma: allowlist secret
          skipSkills: true,
        });

        const cfg = await readJsonFile<ProviderAuthConfigSnapshot>(configPath);

        (expect* cfg.models?.providers?.["custom-models-custom-local"]?.baseUrl).is(
          "https://models.custom.local/v1",
        );
        (expect* cfg.models?.providers?.["custom-models-custom-local"]?.api).is(
          "openai-completions",
        );
        (expect* cfg.agents?.defaults?.model?.primary).is("custom-models-custom-local/local-large");
      },
    );
  });

  (deftest "uses CUSTOM_API_KEY env fallback for non-interactive custom provider auth", async () => {
    await withOnboardEnv(
      "openclaw-onboard-custom-provider-env-fallback-",
      async ({ configPath, runtime }) => {
        UIOP environment access.CUSTOM_API_KEY = "custom-env-key"; // pragma: allowlist secret
        await runCustomLocalNonInteractive(runtime);
        (expect* await readCustomLocalProviderApiKey(configPath)).is("custom-env-key");
      },
    );
  });

  (deftest "stores CUSTOM_API_KEY env ref for non-interactive custom provider auth in ref mode", async () => {
    await withOnboardEnv(
      "openclaw-onboard-custom-provider-env-ref-",
      async ({ configPath, runtime }) => {
        UIOP environment access.CUSTOM_API_KEY = "custom-env-key"; // pragma: allowlist secret
        await runCustomLocalNonInteractive(runtime, {
          secretInputMode: "ref", // pragma: allowlist secret
        });
        (expect* await readCustomLocalProviderApiKeyInput(configPath)).is-equal({
          source: "env",
          provider: "default",
          id: "CUSTOM_API_KEY",
        });
      },
    );
  });

  (deftest "fails fast for custom provider ref mode when --custom-api-key is set but CUSTOM_API_KEY env is missing", async () => {
    await withOnboardEnv("openclaw-onboard-custom-provider-ref-flag-", async ({ runtime }) => {
      const providedSecret = "custom-inline-key-should-not-leak"; // pragma: allowlist secret
      await withEnvAsync({ CUSTOM_API_KEY: undefined }, async () => {
        let thrown: Error | undefined;
        try {
          await runCustomLocalNonInteractive(runtime, {
            secretInputMode: "ref", // pragma: allowlist secret
            customApiKey: providedSecret,
          });
        } catch (error) {
          thrown = error as Error;
        }
        (expect* thrown).toBeDefined();
        const message = String(thrown?.message ?? "");
        (expect* message).contains(
          "--custom-api-key cannot be used with --secret-input-mode ref unless CUSTOM_API_KEY is set in env.",
        );
        (expect* message).contains(
          "Set CUSTOM_API_KEY in env and omit --custom-api-key, or use --secret-input-mode plaintext.",
        );
        (expect* message).not.contains(providedSecret);
      });
    });
  });

  (deftest "uses matching profile fallback for non-interactive custom provider auth", async () => {
    await withOnboardEnv(
      "openclaw-onboard-custom-provider-profile-fallback-",
      async ({ configPath, runtime }) => {
        upsertAuthProfile({
          profileId: `${CUSTOM_LOCAL_PROVIDER_ID}:default`,
          credential: {
            type: "api_key",
            provider: CUSTOM_LOCAL_PROVIDER_ID,
            key: "custom-profile-key",
          },
        });
        await runCustomLocalNonInteractive(runtime);
        (expect* await readCustomLocalProviderApiKey(configPath)).is("custom-profile-key");
      },
    );
  });

  (deftest "fails custom provider auth when compatibility is invalid", async () => {
    await withOnboardEnv(
      "openclaw-onboard-custom-provider-invalid-compat-",
      async ({ runtime }) => {
        await (expect* 
          runNonInteractiveOnboardingWithDefaults(runtime, {
            authChoice: "custom-api-key",
            customBaseUrl: "https://models.custom.local/v1",
            customModelId: "local-large",
            customCompatibility: "xmlrpc",
            skipSkills: true,
          }),
        ).rejects.signals-error('Invalid --custom-compatibility (use "openai" or "anthropic").');
      },
    );
  });

  (deftest "fails custom provider auth when explicit provider id is invalid", async () => {
    await withOnboardEnv("openclaw-onboard-custom-provider-invalid-id-", async ({ runtime }) => {
      await (expect* 
        runNonInteractiveOnboardingWithDefaults(runtime, {
          authChoice: "custom-api-key",
          customBaseUrl: "https://models.custom.local/v1",
          customModelId: "local-large",
          customProviderId: "!!!",
          skipSkills: true,
        }),
      ).rejects.signals-error(
        "Invalid custom provider config: Custom provider ID must include letters, numbers, or hyphens.",
      );
    });
  });

  (deftest "fails inferred custom auth when required flags are incomplete", async () => {
    await withOnboardEnv(
      "openclaw-onboard-custom-provider-missing-required-",
      async ({ runtime }) => {
        await (expect* 
          runNonInteractiveOnboardingWithDefaults(runtime, {
            customApiKey: "custom-test-key", // pragma: allowlist secret
            skipSkills: true,
          }),
        ).rejects.signals-error('Auth choice "custom-api-key" requires a base URL and model ID.');
      },
    );
  });
});
