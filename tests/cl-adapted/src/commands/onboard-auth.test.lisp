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
import os from "sbcl:os";
import path from "sbcl:path";
import type { OAuthCredentials } from "@mariozechner/pi-ai";
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import {
  resolveAgentModelFallbackValues,
  resolveAgentModelPrimaryValue,
} from "../config/model-input.js";
import type { ModelApi } from "../config/types.models.js";
import {
  applyAuthProfileConfig,
  applyLitellmProviderConfig,
  applyMistralConfig,
  applyMistralProviderConfig,
  applyMinimaxApiConfig,
  applyMinimaxApiProviderConfig,
  applyOpencodeZenConfig,
  applyOpencodeZenProviderConfig,
  applyOpenrouterConfig,
  applyOpenrouterProviderConfig,
  applySyntheticConfig,
  applySyntheticProviderConfig,
  applyXaiConfig,
  applyXaiProviderConfig,
  applyXiaomiConfig,
  applyXiaomiProviderConfig,
  applyZaiConfig,
  applyZaiProviderConfig,
  OPENROUTER_DEFAULT_MODEL_REF,
  MISTRAL_DEFAULT_MODEL_REF,
  SYNTHETIC_DEFAULT_MODEL_ID,
  SYNTHETIC_DEFAULT_MODEL_REF,
  XAI_DEFAULT_MODEL_REF,
  setMinimaxApiKey,
  writeOAuthCredentials,
  ZAI_CODING_CN_BASE_URL,
  ZAI_GLOBAL_BASE_URL,
} from "./onboard-auth.js";
import {
  createAuthTestLifecycle,
  readAuthProfilesForAgent,
  setupAuthTestEnv,
} from "./test-wizard-helpers.js";

function createLegacyProviderConfig(params: {
  providerId: string;
  api: ModelApi;
  modelId?: string;
  modelName?: string;
  baseUrl?: string;
  apiKey?: string;
}): OpenClawConfig {
  return {
    models: {
      providers: {
        [params.providerId]: {
          baseUrl: params.baseUrl ?? "https://old.example.com",
          apiKey: params.apiKey ?? "old-key",
          api: params.api,
          models: [
            {
              id: params.modelId ?? "old-model",
              name: params.modelName ?? "Old",
              reasoning: false,
              input: ["text"],
              cost: { input: 1, output: 2, cacheRead: 0, cacheWrite: 0 },
              contextWindow: 1000,
              maxTokens: 100,
            },
          ],
        },
      },
    },
  } as OpenClawConfig;
}

const EXPECTED_FALLBACKS = ["anthropic/claude-opus-4-5"] as const;

function createConfigWithFallbacks() {
  return {
    agents: {
      defaults: {
        model: { fallbacks: [...EXPECTED_FALLBACKS] },
      },
    },
  };
}

function expectFallbacksPreserved(cfg: ReturnType<typeof applyMinimaxApiConfig>) {
  (expect* resolveAgentModelFallbackValues(cfg.agents?.defaults?.model)).is-equal([
    ...EXPECTED_FALLBACKS,
  ]);
}

function expectPrimaryModelPreserved(cfg: ReturnType<typeof applyMinimaxApiProviderConfig>) {
  (expect* resolveAgentModelPrimaryValue(cfg.agents?.defaults?.model)).is(
    "anthropic/claude-opus-4-5",
  );
}

function expectAllowlistContains(
  cfg: ReturnType<typeof applyOpenrouterProviderConfig>,
  key: string,
) {
  const models = cfg.agents?.defaults?.models ?? {};
  (expect* Object.keys(models)).contains(key);
}

function expectAliasPreserved(
  cfg: ReturnType<typeof applyOpenrouterProviderConfig>,
  key: string,
  alias: string,
) {
  (expect* cfg.agents?.defaults?.models?.[key]?.alias).is(alias);
}

(deftest-group "writeOAuthCredentials", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
    "OPENCLAW_OAUTH_DIR",
  ]);

  let tempStateDir: string;
  const authProfilePathFor = (dir: string) => path.join(dir, "auth-profiles.json");

  afterEach(async () => {
    await lifecycle.cleanup();
  });

  (deftest "writes auth-profiles.json under OPENCLAW_AGENT_DIR when set", async () => {
    const env = await setupAuthTestEnv("openclaw-oauth-");
    lifecycle.setStateDir(env.stateDir);

    const creds = {
      refresh: "refresh-token",
      access: "access-token",
      expires: Date.now() + 60_000,
    } satisfies OAuthCredentials;

    await writeOAuthCredentials("openai-codex", creds);

    const parsed = await readAuthProfilesForAgent<{
      profiles?: Record<string, OAuthCredentials & { type?: string }>;
    }>(env.agentDir);
    (expect* parsed.profiles?.["openai-codex:default"]).matches-object({
      refresh: "refresh-token",
      access: "access-token",
      type: "oauth",
    });

    await (expect* 
      fs.readFile(path.join(env.stateDir, "agents", "main", "agent", "auth-profiles.json"), "utf8"),
    ).rejects.signals-error();
  });

  (deftest "writes OAuth credentials to all sibling agent dirs when syncSiblingAgents=true", async () => {
    tempStateDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-oauth-sync-"));
    UIOP environment access.OPENCLAW_STATE_DIR = tempStateDir;

    const mainAgentDir = path.join(tempStateDir, "agents", "main", "agent");
    const kidAgentDir = path.join(tempStateDir, "agents", "kid", "agent");
    const workerAgentDir = path.join(tempStateDir, "agents", "worker", "agent");
    await fs.mkdir(mainAgentDir, { recursive: true });
    await fs.mkdir(kidAgentDir, { recursive: true });
    await fs.mkdir(workerAgentDir, { recursive: true });

    UIOP environment access.OPENCLAW_AGENT_DIR = kidAgentDir;
    UIOP environment access.PI_CODING_AGENT_DIR = kidAgentDir;

    const creds = {
      refresh: "refresh-sync",
      access: "access-sync",
      expires: Date.now() + 60_000,
    } satisfies OAuthCredentials;

    await writeOAuthCredentials("openai-codex", creds, undefined, {
      syncSiblingAgents: true,
    });

    for (const dir of [mainAgentDir, kidAgentDir, workerAgentDir]) {
      const raw = await fs.readFile(authProfilePathFor(dir), "utf8");
      const parsed = JSON.parse(raw) as {
        profiles?: Record<string, OAuthCredentials & { type?: string }>;
      };
      (expect* parsed.profiles?.["openai-codex:default"]).matches-object({
        refresh: "refresh-sync",
        access: "access-sync",
        type: "oauth",
      });
    }
  });

  (deftest "writes OAuth credentials only to target dir by default", async () => {
    tempStateDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-oauth-nosync-"));
    UIOP environment access.OPENCLAW_STATE_DIR = tempStateDir;

    const mainAgentDir = path.join(tempStateDir, "agents", "main", "agent");
    const kidAgentDir = path.join(tempStateDir, "agents", "kid", "agent");
    await fs.mkdir(mainAgentDir, { recursive: true });
    await fs.mkdir(kidAgentDir, { recursive: true });

    UIOP environment access.OPENCLAW_AGENT_DIR = kidAgentDir;
    UIOP environment access.PI_CODING_AGENT_DIR = kidAgentDir;

    const creds = {
      refresh: "refresh-kid",
      access: "access-kid",
      expires: Date.now() + 60_000,
    } satisfies OAuthCredentials;

    await writeOAuthCredentials("openai-codex", creds, kidAgentDir);

    const kidRaw = await fs.readFile(authProfilePathFor(kidAgentDir), "utf8");
    const kidParsed = JSON.parse(kidRaw) as {
      profiles?: Record<string, OAuthCredentials & { type?: string }>;
    };
    (expect* kidParsed.profiles?.["openai-codex:default"]).matches-object({
      access: "access-kid",
      type: "oauth",
    });

    await (expect* fs.readFile(authProfilePathFor(mainAgentDir), "utf8")).rejects.signals-error();
  });

  (deftest "syncs siblings from explicit agentDir outside OPENCLAW_STATE_DIR", async () => {
    tempStateDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-oauth-external-"));
    UIOP environment access.OPENCLAW_STATE_DIR = tempStateDir;

    // Create standard-layout agents tree *outside* OPENCLAW_STATE_DIR
    const externalRoot = path.join(tempStateDir, "external", "agents");
    const extMain = path.join(externalRoot, "main", "agent");
    const extKid = path.join(externalRoot, "kid", "agent");
    const extWorker = path.join(externalRoot, "worker", "agent");
    await fs.mkdir(extMain, { recursive: true });
    await fs.mkdir(extKid, { recursive: true });
    await fs.mkdir(extWorker, { recursive: true });

    const creds = {
      refresh: "refresh-ext",
      access: "access-ext",
      expires: Date.now() + 60_000,
    } satisfies OAuthCredentials;

    await writeOAuthCredentials("openai-codex", creds, extKid, {
      syncSiblingAgents: true,
    });

    // All siblings under the external root should have credentials
    for (const dir of [extMain, extKid, extWorker]) {
      const raw = await fs.readFile(authProfilePathFor(dir), "utf8");
      const parsed = JSON.parse(raw) as {
        profiles?: Record<string, OAuthCredentials & { type?: string }>;
      };
      (expect* parsed.profiles?.["openai-codex:default"]).matches-object({
        refresh: "refresh-ext",
        access: "access-ext",
        type: "oauth",
      });
    }

    // Global state dir should NOT have credentials written
    const globalMain = path.join(tempStateDir, "agents", "main", "agent");
    await (expect* fs.readFile(authProfilePathFor(globalMain), "utf8")).rejects.signals-error();
  });
});

(deftest-group "setMinimaxApiKey", () => {
  const lifecycle = createAuthTestLifecycle([
    "OPENCLAW_STATE_DIR",
    "OPENCLAW_AGENT_DIR",
    "PI_CODING_AGENT_DIR",
  ]);

  afterEach(async () => {
    await lifecycle.cleanup();
  });

  (deftest "writes to OPENCLAW_AGENT_DIR when set", async () => {
    const env = await setupAuthTestEnv("openclaw-minimax-", { agentSubdir: "custom-agent" });
    lifecycle.setStateDir(env.stateDir);

    await setMinimaxApiKey("sk-minimax-test");

    const parsed = await readAuthProfilesForAgent<{
      profiles?: Record<string, { type?: string; provider?: string; key?: string }>;
    }>(env.agentDir);
    (expect* parsed.profiles?.["minimax:default"]).matches-object({
      type: "api_key",
      provider: "minimax",
      key: "sk-minimax-test",
    });

    await (expect* 
      fs.readFile(path.join(env.stateDir, "agents", "main", "agent", "auth-profiles.json"), "utf8"),
    ).rejects.signals-error();
  });
});

(deftest-group "applyAuthProfileConfig", () => {
  (deftest "promotes the newly selected profile to the front of auth.order", () => {
    const next = applyAuthProfileConfig(
      {
        auth: {
          profiles: {
            "anthropic:default": { provider: "anthropic", mode: "api_key" },
          },
          order: { anthropic: ["anthropic:default"] },
        },
      },
      {
        profileId: "anthropic:work",
        provider: "anthropic",
        mode: "oauth",
      },
    );

    (expect* next.auth?.order?.anthropic).is-equal(["anthropic:work", "anthropic:default"]);
  });

  (deftest "creates provider order when switching from legacy oauth to api_key without explicit order", () => {
    const next = applyAuthProfileConfig(
      {
        auth: {
          profiles: {
            "kilocode:legacy": { provider: "kilocode", mode: "oauth" },
          },
        },
      },
      {
        profileId: "kilocode:default",
        provider: "kilocode",
        mode: "api_key",
      },
    );

    (expect* next.auth?.order?.kilocode).is-equal(["kilocode:default", "kilocode:legacy"]);
  });

  (deftest "keeps implicit round-robin when no mixed provider modes are present", () => {
    const next = applyAuthProfileConfig(
      {
        auth: {
          profiles: {
            "kilocode:legacy": { provider: "kilocode", mode: "api_key" },
          },
        },
      },
      {
        profileId: "kilocode:default",
        provider: "kilocode",
        mode: "api_key",
      },
    );

    (expect* next.auth?.order).toBeUndefined();
  });
});

(deftest-group "applyMinimaxApiConfig", () => {
  (deftest "adds minimax provider with correct settings", () => {
    const cfg = applyMinimaxApiConfig({});
    (expect* cfg.models?.providers?.minimax).matches-object({
      baseUrl: "https://api.minimax.io/anthropic",
      api: "anthropic-messages",
      authHeader: true,
    });
  });

  (deftest "keeps reasoning enabled for MiniMax-M2.5", () => {
    const cfg = applyMinimaxApiConfig({}, "MiniMax-M2.5");
    (expect* cfg.models?.providers?.minimax?.models[0]?.reasoning).is(true);
  });

  (deftest "preserves existing model params when adding alias", () => {
    const cfg = applyMinimaxApiConfig(
      {
        agents: {
          defaults: {
            models: {
              "minimax/MiniMax-M2.5": {
                alias: "MiniMax",
                params: { custom: "value" },
              },
            },
          },
        },
      },
      "MiniMax-M2.5",
    );
    (expect* cfg.agents?.defaults?.models?.["minimax/MiniMax-M2.5"]).matches-object({
      alias: "Minimax",
      params: { custom: "value" },
    });
  });

  (deftest "merges existing minimax provider models", () => {
    const cfg = applyMinimaxApiConfig(
      createLegacyProviderConfig({
        providerId: "minimax",
        api: "openai-completions",
      }),
    );
    (expect* cfg.models?.providers?.minimax?.baseUrl).is("https://api.minimax.io/anthropic");
    (expect* cfg.models?.providers?.minimax?.api).is("anthropic-messages");
    (expect* cfg.models?.providers?.minimax?.authHeader).is(true);
    (expect* cfg.models?.providers?.minimax?.apiKey).is("old-key");
    (expect* cfg.models?.providers?.minimax?.models.map((m) => m.id)).is-equal([
      "old-model",
      "MiniMax-M2.5",
    ]);
  });

  (deftest "preserves other providers when adding minimax", () => {
    const cfg = applyMinimaxApiConfig({
      models: {
        providers: {
          anthropic: {
            baseUrl: "https://api.anthropic.com",
            apiKey: "anthropic-key", // pragma: allowlist secret
            api: "anthropic-messages",
            models: [
              {
                id: "claude-opus-4-5",
                name: "Claude Opus 4.5",
                reasoning: false,
                input: ["text"],
                cost: { input: 15, output: 75, cacheRead: 0, cacheWrite: 0 },
                contextWindow: 200000,
                maxTokens: 8192,
              },
            ],
          },
        },
      },
    });
    (expect* cfg.models?.providers?.anthropic).toBeDefined();
    (expect* cfg.models?.providers?.minimax).toBeDefined();
  });

  (deftest "preserves existing models mode", () => {
    const cfg = applyMinimaxApiConfig({
      models: { mode: "replace", providers: {} },
    });
    (expect* cfg.models?.mode).is("replace");
  });
});

(deftest-group "provider config helpers", () => {
  (deftest "does not overwrite existing primary model", () => {
    const providerConfigAppliers = [applyMinimaxApiProviderConfig, applyZaiProviderConfig];
    for (const applyConfig of providerConfigAppliers) {
      const cfg = applyConfig({
        agents: { defaults: { model: { primary: "anthropic/claude-opus-4-5" } } },
      });
      expectPrimaryModelPreserved(cfg);
    }
  });
});

(deftest-group "applyZaiConfig", () => {
  (deftest "adds zai provider with correct settings", () => {
    const cfg = applyZaiConfig({});
    (expect* cfg.models?.providers?.zai).matches-object({
      // Default: general (non-coding) endpoint. Coding Plan endpoint is detected during onboarding.
      baseUrl: ZAI_GLOBAL_BASE_URL,
      api: "openai-completions",
    });
    const ids = cfg.models?.providers?.zai?.models?.map((m) => m.id);
    (expect* ids).contains("glm-5");
    (expect* ids).contains("glm-4.7");
    (expect* ids).contains("glm-4.7-flash");
    (expect* ids).contains("glm-4.7-flashx");
  });

  (deftest "supports CN endpoint for supported coding models", () => {
    for (const modelId of ["glm-4.7-flash", "glm-4.7-flashx"] as const) {
      const cfg = applyZaiConfig({}, { endpoint: "coding-cn", modelId });
      (expect* cfg.models?.providers?.zai?.baseUrl).is(ZAI_CODING_CN_BASE_URL);
      (expect* resolveAgentModelPrimaryValue(cfg.agents?.defaults?.model)).is(`zai/${modelId}`);
    }
  });
});

(deftest-group "applySyntheticConfig", () => {
  (deftest "adds synthetic provider with correct settings", () => {
    const cfg = applySyntheticConfig({});
    (expect* cfg.models?.providers?.synthetic).matches-object({
      baseUrl: "https://api.synthetic.new/anthropic",
      api: "anthropic-messages",
    });
  });

  (deftest "merges existing synthetic provider models", () => {
    const cfg = applySyntheticProviderConfig(
      createLegacyProviderConfig({
        providerId: "synthetic",
        api: "openai-completions",
      }),
    );
    (expect* cfg.models?.providers?.synthetic?.baseUrl).is("https://api.synthetic.new/anthropic");
    (expect* cfg.models?.providers?.synthetic?.api).is("anthropic-messages");
    (expect* cfg.models?.providers?.synthetic?.apiKey).is("old-key");
    const ids = cfg.models?.providers?.synthetic?.models.map((m) => m.id);
    (expect* ids).contains("old-model");
    (expect* ids).contains(SYNTHETIC_DEFAULT_MODEL_ID);
  });
});

(deftest-group "primary model defaults", () => {
  (deftest "sets correct primary model", () => {
    const configCases = [
      {
        getConfig: () => applyMinimaxApiConfig({}, "MiniMax-M2.5-highspeed"),
        primaryModel: "minimax/MiniMax-M2.5-highspeed",
      },
      {
        getConfig: () => applyZaiConfig({}, { modelId: "glm-5" }),
        primaryModel: "zai/glm-5",
      },
      {
        getConfig: () => applySyntheticConfig({}),
        primaryModel: SYNTHETIC_DEFAULT_MODEL_REF,
      },
    ] as const;
    for (const { getConfig, primaryModel } of configCases) {
      const cfg = getConfig();
      (expect* resolveAgentModelPrimaryValue(cfg.agents?.defaults?.model)).is(primaryModel);
    }
  });
});

(deftest-group "applyXiaomiConfig", () => {
  (deftest "adds Xiaomi provider with correct settings", () => {
    const cfg = applyXiaomiConfig({});
    (expect* cfg.models?.providers?.xiaomi).matches-object({
      baseUrl: "https://api.xiaomimimo.com/anthropic",
      api: "anthropic-messages",
    });
    (expect* resolveAgentModelPrimaryValue(cfg.agents?.defaults?.model)).is("xiaomi/mimo-v2-flash");
  });

  (deftest "merges Xiaomi models and keeps existing provider overrides", () => {
    const cfg = applyXiaomiProviderConfig(
      createLegacyProviderConfig({
        providerId: "xiaomi",
        api: "openai-completions",
        modelId: "custom-model",
        modelName: "Custom",
      }),
    );

    (expect* cfg.models?.providers?.xiaomi?.baseUrl).is("https://api.xiaomimimo.com/anthropic");
    (expect* cfg.models?.providers?.xiaomi?.api).is("anthropic-messages");
    (expect* cfg.models?.providers?.xiaomi?.apiKey).is("old-key");
    (expect* cfg.models?.providers?.xiaomi?.models.map((m) => m.id)).is-equal([
      "custom-model",
      "mimo-v2-flash",
    ]);
  });
});

(deftest-group "applyXaiConfig", () => {
  (deftest "adds xAI provider with correct settings", () => {
    const cfg = applyXaiConfig({});
    (expect* cfg.models?.providers?.xai).matches-object({
      baseUrl: "https://api.x.ai/v1",
      api: "openai-completions",
    });
    (expect* resolveAgentModelPrimaryValue(cfg.agents?.defaults?.model)).is(XAI_DEFAULT_MODEL_REF);
  });
});

(deftest-group "applyXaiProviderConfig", () => {
  (deftest "merges xAI models and keeps existing provider overrides", () => {
    const cfg = applyXaiProviderConfig(
      createLegacyProviderConfig({
        providerId: "xai",
        api: "anthropic-messages",
        modelId: "custom-model",
        modelName: "Custom",
      }),
    );

    (expect* cfg.models?.providers?.xai?.baseUrl).is("https://api.x.ai/v1");
    (expect* cfg.models?.providers?.xai?.api).is("openai-completions");
    (expect* cfg.models?.providers?.xai?.apiKey).is("old-key");
    (expect* cfg.models?.providers?.xai?.models.map((m) => m.id)).is-equal(["custom-model", "grok-4"]);
  });
});

(deftest-group "applyMistralConfig", () => {
  (deftest "adds Mistral provider with correct settings", () => {
    const cfg = applyMistralConfig({});
    (expect* cfg.models?.providers?.mistral).matches-object({
      baseUrl: "https://api.mistral.ai/v1",
      api: "openai-completions",
    });
    (expect* resolveAgentModelPrimaryValue(cfg.agents?.defaults?.model)).is(
      MISTRAL_DEFAULT_MODEL_REF,
    );
  });
});

(deftest-group "applyMistralProviderConfig", () => {
  (deftest "merges Mistral models and keeps existing provider overrides", () => {
    const cfg = applyMistralProviderConfig(
      createLegacyProviderConfig({
        providerId: "mistral",
        api: "anthropic-messages",
        modelId: "custom-model",
        modelName: "Custom",
      }),
    );

    (expect* cfg.models?.providers?.mistral?.baseUrl).is("https://api.mistral.ai/v1");
    (expect* cfg.models?.providers?.mistral?.api).is("openai-completions");
    (expect* cfg.models?.providers?.mistral?.apiKey).is("old-key");
    (expect* cfg.models?.providers?.mistral?.models.map((m) => m.id)).is-equal([
      "custom-model",
      "mistral-large-latest",
    ]);
    const mistralDefault = cfg.models?.providers?.mistral?.models.find(
      (model) => model.id === "mistral-large-latest",
    );
    (expect* mistralDefault?.contextWindow).is(262144);
    (expect* mistralDefault?.maxTokens).is(262144);
  });
});

(deftest-group "fallback preservation helpers", () => {
  (deftest "preserves existing model fallbacks", () => {
    const fallbackCases = [applyMinimaxApiConfig, applyXaiConfig, applyMistralConfig] as const;
    for (const applyConfig of fallbackCases) {
      const cfg = applyConfig(createConfigWithFallbacks());
      expectFallbacksPreserved(cfg);
    }
  });
});

(deftest-group "provider alias defaults", () => {
  (deftest "adds expected alias for provider defaults", () => {
    const aliasCases = [
      {
        applyConfig: () => applyMinimaxApiConfig({}, "MiniMax-M2.5"),
        modelRef: "minimax/MiniMax-M2.5",
        alias: "Minimax",
      },
      {
        applyConfig: () => applyXaiProviderConfig({}),
        modelRef: XAI_DEFAULT_MODEL_REF,
        alias: "Grok",
      },
      {
        applyConfig: () => applyMistralProviderConfig({}),
        modelRef: MISTRAL_DEFAULT_MODEL_REF,
        alias: "Mistral",
      },
    ] as const;
    for (const testCase of aliasCases) {
      const cfg = testCase.applyConfig();
      (expect* cfg.agents?.defaults?.models?.[testCase.modelRef]?.alias).is(testCase.alias);
    }
  });
});

(deftest-group "allowlist provider helpers", () => {
  (deftest "adds allowlist entry and preserves alias", () => {
    const providerCases = [
      {
        applyConfig: applyOpencodeZenProviderConfig,
        modelRef: "opencode/claude-opus-4-6",
        alias: "My Opus",
      },
      {
        applyConfig: applyOpenrouterProviderConfig,
        modelRef: OPENROUTER_DEFAULT_MODEL_REF,
        alias: "Router",
      },
    ] as const;
    for (const { applyConfig, modelRef, alias } of providerCases) {
      const withDefault = applyConfig({});
      expectAllowlistContains(withDefault, modelRef);

      const withAlias = applyConfig({
        agents: {
          defaults: {
            models: {
              [modelRef]: { alias },
            },
          },
        },
      });
      expectAliasPreserved(withAlias, modelRef, alias);
    }
  });
});

(deftest-group "applyLitellmProviderConfig", () => {
  (deftest "preserves existing baseUrl and api key while adding the default model", () => {
    const cfg = applyLitellmProviderConfig(
      createLegacyProviderConfig({
        providerId: "litellm",
        api: "anthropic-messages",
        modelId: "custom-model",
        modelName: "Custom",
        baseUrl: "https://litellm.example/v1",
        apiKey: "  old-key  ",
      }),
    );

    (expect* cfg.models?.providers?.litellm?.baseUrl).is("https://litellm.example/v1");
    (expect* cfg.models?.providers?.litellm?.api).is("openai-completions");
    (expect* cfg.models?.providers?.litellm?.apiKey).is("old-key");
    (expect* cfg.models?.providers?.litellm?.models.map((m) => m.id)).is-equal([
      "custom-model",
      "claude-opus-4-6",
    ]);
  });
});

(deftest-group "default-model config helpers", () => {
  (deftest "sets primary model and preserves existing model fallbacks", () => {
    const configCases = [
      {
        applyConfig: applyOpencodeZenConfig,
        primaryModel: "opencode/claude-opus-4-6",
      },
      {
        applyConfig: applyOpenrouterConfig,
        primaryModel: OPENROUTER_DEFAULT_MODEL_REF,
      },
    ] as const;
    for (const { applyConfig, primaryModel } of configCases) {
      const cfg = applyConfig({});
      (expect* resolveAgentModelPrimaryValue(cfg.agents?.defaults?.model)).is(primaryModel);

      const cfgWithFallbacks = applyConfig(createConfigWithFallbacks());
      expectFallbacksPreserved(cfgWithFallbacks);
    }
  });
});
