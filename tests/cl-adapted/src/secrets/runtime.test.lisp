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
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { ensureAuthProfileStore, type AuthProfileStore } from "../agents/auth-profiles.js";
import { loadConfig, type OpenClawConfig } from "../config/config.js";
import {
  activateSecretsRuntimeSnapshot,
  clearSecretsRuntimeSnapshot,
  prepareSecretsRuntimeSnapshot,
} from "./runtime.js";

function asConfig(value: unknown): OpenClawConfig {
  return value as OpenClawConfig;
}

const OPENAI_ENV_KEY_REF = { source: "env", provider: "default", id: "OPENAI_API_KEY" } as const;

function createOpenAiFileModelsConfig(): NonNullable<OpenClawConfig["models"]> {
  return {
    providers: {
      openai: {
        baseUrl: "https://api.openai.com/v1",
        apiKey: { source: "file", provider: "default", id: "/providers/openai/apiKey" },
        models: [],
      },
    },
  };
}

function loadAuthStoreWithProfiles(profiles: AuthProfileStore["profiles"]): AuthProfileStore {
  return {
    version: 1,
    profiles,
  };
}

(deftest-group "secrets runtime snapshot", () => {
  afterEach(() => {
    clearSecretsRuntimeSnapshot();
  });

  (deftest "resolves env refs for config and auth profiles", async () => {
    const config = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            remote: {
              apiKey: { source: "env", provider: "default", id: "MEMORY_REMOTE_API_KEY" },
            },
          },
        },
      },
      models: {
        providers: {
          openai: {
            baseUrl: "https://api.openai.com/v1",
            apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
            headers: {
              Authorization: {
                source: "env",
                provider: "default",
                id: "OPENAI_PROVIDER_AUTH_HEADER",
              },
            },
            models: [],
          },
        },
      },
      skills: {
        entries: {
          "review-pr": {
            enabled: true,
            apiKey: { source: "env", provider: "default", id: "REVIEW_SKILL_API_KEY" },
          },
        },
      },
      talk: {
        apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
        providers: {
          elevenlabs: {
            apiKey: { source: "env", provider: "default", id: "TALK_PROVIDER_API_KEY" },
          },
        },
      },
      gateway: {
        mode: "remote",
        remote: {
          url: "wss://gateway.example",
          token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
          password: { source: "env", provider: "default", id: "REMOTE_GATEWAY_PASSWORD" },
        },
      },
      channels: {
        telegram: {
          botToken: { source: "env", provider: "default", id: "TELEGRAM_BOT_TOKEN_REF" },
          webhookUrl: "https://example.test/telegram-webhook",
          webhookSecret: { source: "env", provider: "default", id: "TELEGRAM_WEBHOOK_SECRET_REF" },
          accounts: {
            work: {
              botToken: {
                source: "env",
                provider: "default",
                id: "TELEGRAM_WORK_BOT_TOKEN_REF",
              },
            },
          },
        },
        slack: {
          mode: "http",
          signingSecret: { source: "env", provider: "default", id: "SLACK_SIGNING_SECRET_REF" },
          accounts: {
            work: {
              botToken: { source: "env", provider: "default", id: "SLACK_WORK_BOT_TOKEN_REF" },
              appToken: { source: "env", provider: "default", id: "SLACK_WORK_APP_TOKEN_REF" },
            },
          },
        },
      },
      tools: {
        web: {
          search: {
            apiKey: { source: "env", provider: "default", id: "WEB_SEARCH_API_KEY" },
          },
        },
      },
    });

    const snapshot = await prepareSecretsRuntimeSnapshot({
      config,
      env: {
        OPENAI_API_KEY: "sk-env-openai", // pragma: allowlist secret
        OPENAI_PROVIDER_AUTH_HEADER: "Bearer sk-env-header", // pragma: allowlist secret
        GITHUB_TOKEN: "ghp-env-token", // pragma: allowlist secret
        REVIEW_SKILL_API_KEY: "sk-skill-ref", // pragma: allowlist secret
        MEMORY_REMOTE_API_KEY: "mem-ref-key", // pragma: allowlist secret
        TALK_API_KEY: "talk-ref-key", // pragma: allowlist secret
        TALK_PROVIDER_API_KEY: "talk-provider-ref-key", // pragma: allowlist secret
        REMOTE_GATEWAY_TOKEN: "remote-token-ref",
        REMOTE_GATEWAY_PASSWORD: "remote-password-ref", // pragma: allowlist secret
        TELEGRAM_BOT_TOKEN_REF: "telegram-bot-ref",
        TELEGRAM_WEBHOOK_SECRET_REF: "telegram-webhook-ref", // pragma: allowlist secret
        TELEGRAM_WORK_BOT_TOKEN_REF: "telegram-work-ref",
        SLACK_SIGNING_SECRET_REF: "slack-signing-ref", // pragma: allowlist secret
        SLACK_WORK_BOT_TOKEN_REF: "slack-work-bot-ref",
        SLACK_WORK_APP_TOKEN_REF: "slack-work-app-ref",
        WEB_SEARCH_API_KEY: "web-search-ref", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () =>
        loadAuthStoreWithProfiles({
          "openai:default": {
            type: "api_key",
            provider: "openai",
            key: "old-openai",
            keyRef: OPENAI_ENV_KEY_REF,
          },
          "github-copilot:default": {
            type: "token",
            provider: "github-copilot",
            token: "old-gh",
            tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
          },
          "openai:inline": {
            type: "api_key",
            provider: "openai",
            key: "${OPENAI_API_KEY}",
          },
        }),
    });

    (expect* snapshot.config.models?.providers?.openai?.apiKey).is("sk-env-openai");
    (expect* snapshot.config.models?.providers?.openai?.headers?.Authorization).is(
      "Bearer sk-env-header",
    );
    (expect* snapshot.config.skills?.entries?.["review-pr"]?.apiKey).is("sk-skill-ref");
    (expect* snapshot.config.agents?.defaults?.memorySearch?.remote?.apiKey).is("mem-ref-key");
    (expect* snapshot.config.talk?.apiKey).is("talk-ref-key");
    (expect* snapshot.config.talk?.providers?.elevenlabs?.apiKey).is("talk-provider-ref-key");
    (expect* snapshot.config.gateway?.remote?.token).is("remote-token-ref");
    (expect* snapshot.config.gateway?.remote?.password).is("remote-password-ref");
    (expect* snapshot.config.channels?.telegram?.botToken).is-equal({
      source: "env",
      provider: "default",
      id: "TELEGRAM_BOT_TOKEN_REF",
    });
    (expect* snapshot.config.channels?.telegram?.webhookSecret).is("telegram-webhook-ref");
    (expect* snapshot.config.channels?.telegram?.accounts?.work?.botToken).is("telegram-work-ref");
    (expect* snapshot.config.channels?.slack?.signingSecret).is("slack-signing-ref");
    (expect* snapshot.config.channels?.slack?.accounts?.work?.botToken).is("slack-work-bot-ref");
    (expect* snapshot.config.channels?.slack?.accounts?.work?.appToken).is-equal({
      source: "env",
      provider: "default",
      id: "SLACK_WORK_APP_TOKEN_REF",
    });
    (expect* snapshot.config.tools?.web?.search?.apiKey).is("web-search-ref");
    (expect* snapshot.warnings).has-length(4);
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.slack.accounts.work.appToken",
    );
    (expect* snapshot.authStores[0]?.store.profiles["openai:default"]).matches-object({
      type: "api_key",
      key: "sk-env-openai",
    });
    (expect* snapshot.authStores[0]?.store.profiles["github-copilot:default"]).matches-object({
      type: "token",
      token: "ghp-env-token",
    });
    (expect* snapshot.authStores[0]?.store.profiles["openai:inline"]).matches-object({
      type: "api_key",
      key: "sk-env-openai",
    });
    // After normalization, inline SecretRef string should be promoted to keyRef
    (expect* 
      (snapshot.authStores[0].store.profiles["openai:inline"] as Record<string, unknown>).keyRef,
    ).is-equal({ source: "env", provider: "default", id: "OPENAI_API_KEY" });
  });

  (deftest "normalizes inline SecretRef object on token to tokenRef", async () => {
    const config: OpenClawConfig = { models: {}, secrets: {} };
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config,
      env: { MY_TOKEN: "resolved-token-value" },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () =>
        loadAuthStoreWithProfiles({
          "custom:inline-token": {
            type: "token",
            provider: "custom",
            token: { source: "env", provider: "default", id: "MY_TOKEN" } as unknown as string,
          },
        }),
    });

    const profile = snapshot.authStores[0]?.store.profiles["custom:inline-token"] as Record<
      string,
      unknown
    >;
    // tokenRef should be set from the inline SecretRef
    (expect* profile.tokenRef).is-equal({ source: "env", provider: "default", id: "MY_TOKEN" });
    // token should be resolved to the actual value after activation
    activateSecretsRuntimeSnapshot(snapshot);
    (expect* profile.token).is("resolved-token-value");
  });

  (deftest "normalizes inline SecretRef object on key to keyRef", async () => {
    const config: OpenClawConfig = { models: {}, secrets: {} };
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config,
      env: { MY_KEY: "resolved-key-value" },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () =>
        loadAuthStoreWithProfiles({
          "custom:inline-key": {
            type: "api_key",
            provider: "custom",
            key: { source: "env", provider: "default", id: "MY_KEY" } as unknown as string,
          },
        }),
    });

    const profile = snapshot.authStores[0]?.store.profiles["custom:inline-key"] as Record<
      string,
      unknown
    >;
    // keyRef should be set from the inline SecretRef
    (expect* profile.keyRef).is-equal({ source: "env", provider: "default", id: "MY_KEY" });
    // key should be resolved to the actual value after activation
    activateSecretsRuntimeSnapshot(snapshot);
    (expect* profile.key).is("resolved-key-value");
  });

  (deftest "keeps explicit keyRef when inline key SecretRef is also present", async () => {
    const config: OpenClawConfig = { models: {}, secrets: {} };
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config,
      env: {
        PRIMARY_KEY: "primary-key-value",
        SHADOW_KEY: "shadow-key-value",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () =>
        loadAuthStoreWithProfiles({
          "custom:explicit-keyref": {
            type: "api_key",
            provider: "custom",
            keyRef: { source: "env", provider: "default", id: "PRIMARY_KEY" },
            key: { source: "env", provider: "default", id: "SHADOW_KEY" } as unknown as string,
          },
        }),
    });

    const profile = snapshot.authStores[0]?.store.profiles["custom:explicit-keyref"] as Record<
      string,
      unknown
    >;
    (expect* profile.keyRef).is-equal({ source: "env", provider: "default", id: "PRIMARY_KEY" });
    activateSecretsRuntimeSnapshot(snapshot);
    (expect* profile.key).is("primary-key-value");
  });

  (deftest "treats non-selected web search provider refs as inactive", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        tools: {
          web: {
            search: {
              enabled: true,
              provider: "brave",
              apiKey: { source: "env", provider: "default", id: "WEB_SEARCH_API_KEY" },
              grok: {
                apiKey: { source: "env", provider: "default", id: "MISSING_GROK_API_KEY" },
              },
            },
          },
        },
      }),
      env: {
        WEB_SEARCH_API_KEY: "web-search-ref", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.tools?.web?.search?.apiKey).is("web-search-ref");
    (expect* snapshot.config.tools?.web?.search?.grok?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_GROK_API_KEY",
    });
    (expect* snapshot.warnings).is-equal(
      expect.arrayContaining([
        expect.objectContaining({
          code: "SECRETS_REF_IGNORED_INACTIVE_SURFACE",
          path: "tools.web.search.grok.apiKey",
        }),
      ]),
    );
  });

  (deftest "resolves provider-specific refs in web search auto mode", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        tools: {
          web: {
            search: {
              enabled: true,
              apiKey: { source: "env", provider: "default", id: "WEB_SEARCH_API_KEY" },
              gemini: {
                apiKey: { source: "env", provider: "default", id: "WEB_SEARCH_GEMINI_API_KEY" },
              },
            },
          },
        },
      }),
      env: {
        WEB_SEARCH_API_KEY: "web-search-ref", // pragma: allowlist secret
        WEB_SEARCH_GEMINI_API_KEY: "web-search-gemini-ref", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.tools?.web?.search?.apiKey).is("web-search-ref");
    (expect* snapshot.config.tools?.web?.search?.gemini?.apiKey).is("web-search-gemini-ref");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "tools.web.search.gemini.apiKey",
    );
  });

  (deftest "resolves selected web search provider ref even when provider config is disabled", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        tools: {
          web: {
            search: {
              enabled: true,
              provider: "gemini",
              gemini: {
                enabled: false,
                apiKey: { source: "env", provider: "default", id: "WEB_SEARCH_GEMINI_API_KEY" },
              },
            },
          },
        },
      }),
      env: {
        WEB_SEARCH_GEMINI_API_KEY: "web-search-gemini-ref", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.tools?.web?.search?.gemini?.apiKey).is("web-search-gemini-ref");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "tools.web.search.gemini.apiKey",
    );
  });

  (deftest "resolves file refs via configured file provider", async () => {
    if (process.platform === "win32") {
      return;
    }
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-secrets-file-provider-"));
    const secretsPath = path.join(root, "secrets.json");
    try {
      await fs.writeFile(
        secretsPath,
        JSON.stringify(
          {
            providers: {
              openai: {
                apiKey: "sk-from-file-provider", // pragma: allowlist secret
              },
            },
          },
          null,
          2,
        ),
        "utf8",
      );
      await fs.chmod(secretsPath, 0o600);

      const config = asConfig({
        secrets: {
          providers: {
            default: {
              source: "file",
              path: secretsPath,
              mode: "json",
            },
          },
          defaults: {
            file: "default",
          },
        },
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: { source: "file", provider: "default", id: "/providers/openai/apiKey" },
              models: [],
            },
          },
        },
      });

      const snapshot = await prepareSecretsRuntimeSnapshot({
        config,
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      });

      (expect* snapshot.config.models?.providers?.openai?.apiKey).is("sk-from-file-provider");
    } finally {
      await fs.rm(root, { recursive: true, force: true });
    }
  });

  (deftest "fails when file provider payload is not a JSON object", async () => {
    if (process.platform === "win32") {
      return;
    }
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-secrets-file-provider-bad-"));
    const secretsPath = path.join(root, "secrets.json");
    try {
      await fs.writeFile(secretsPath, JSON.stringify(["not-an-object"]), "utf8");
      await fs.chmod(secretsPath, 0o600);

      await (expect* 
        prepareSecretsRuntimeSnapshot({
          config: asConfig({
            secrets: {
              providers: {
                default: {
                  source: "file",
                  path: secretsPath,
                  mode: "json",
                },
              },
            },
            models: {
              ...createOpenAiFileModelsConfig(),
            },
          }),
          agentDirs: ["/tmp/openclaw-agent-main"],
          loadAuthStore: () => ({ version: 1, profiles: {} }),
        }),
      ).rejects.signals-error("payload is not a JSON object");
    } finally {
      await fs.rm(root, { recursive: true, force: true });
    }
  });

  (deftest "activates runtime snapshots for loadConfig and ensureAuthProfileStore", async () => {
    const prepared = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
              models: [],
            },
          },
        },
      }),
      env: { OPENAI_API_KEY: "sk-runtime" }, // pragma: allowlist secret
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () =>
        loadAuthStoreWithProfiles({
          "openai:default": {
            type: "api_key",
            provider: "openai",
            keyRef: OPENAI_ENV_KEY_REF,
          },
        }),
    });

    activateSecretsRuntimeSnapshot(prepared);

    (expect* loadConfig().models?.providers?.openai?.apiKey).is("sk-runtime");
    const store = ensureAuthProfileStore("/tmp/openclaw-agent-main");
    (expect* store.profiles["openai:default"]).matches-object({
      type: "api_key",
      key: "sk-runtime",
    });
  });

  (deftest "skips inactive-surface refs and emits diagnostics", async () => {
    const config = asConfig({
      agents: {
        defaults: {
          memorySearch: {
            enabled: false,
            remote: {
              apiKey: { source: "env", provider: "default", id: "DISABLED_MEMORY_API_KEY" },
            },
          },
        },
      },
      gateway: {
        auth: {
          mode: "token",
          password: { source: "env", provider: "default", id: "DISABLED_GATEWAY_PASSWORD" },
        },
      },
      channels: {
        telegram: {
          botToken: { source: "env", provider: "default", id: "DISABLED_TELEGRAM_BASE_TOKEN" },
          accounts: {
            disabled: {
              enabled: false,
              botToken: {
                source: "env",
                provider: "default",
                id: "DISABLED_TELEGRAM_ACCOUNT_TOKEN",
              },
            },
          },
        },
      },
      tools: {
        web: {
          search: {
            enabled: false,
            apiKey: { source: "env", provider: "default", id: "DISABLED_WEB_SEARCH_API_KEY" },
            gemini: {
              apiKey: {
                source: "env",
                provider: "default",
                id: "DISABLED_WEB_SEARCH_GEMINI_API_KEY",
              },
            },
          },
        },
      },
    });

    const snapshot = await prepareSecretsRuntimeSnapshot({
      config,
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.telegram?.botToken).is-equal({
      source: "env",
      provider: "default",
      id: "DISABLED_TELEGRAM_BASE_TOKEN",
    });
    (expect* 
      snapshot.warnings.filter(
        (warning) => warning.code === "SECRETS_REF_IGNORED_INACTIVE_SURFACE",
      ),
    ).has-length(6);
    (expect* snapshot.warnings.map((warning) => warning.path)).is-equal(
      expect.arrayContaining([
        "agents.defaults.memorySearch.remote.apiKey",
        "gateway.auth.password",
        "channels.telegram.botToken",
        "channels.telegram.accounts.disabled.botToken",
        "tools.web.search.apiKey",
        "tools.web.search.gemini.apiKey",
      ]),
    );
  });

  (deftest "treats gateway.remote refs as inactive when local auth credentials are configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          mode: "local",
          auth: {
            mode: "password",
            token: "local-token",
            password: "local-password", // pragma: allowlist secret
          },
          remote: {
            enabled: true,
            token: { source: "env", provider: "default", id: "MISSING_REMOTE_TOKEN" },
            password: { source: "env", provider: "default", id: "MISSING_REMOTE_PASSWORD" },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.remote?.token).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_REMOTE_TOKEN",
    });
    (expect* snapshot.config.gateway?.remote?.password).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_REMOTE_PASSWORD",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).is-equal(
      expect.arrayContaining(["gateway.remote.token", "gateway.remote.password"]),
    );
  });

  (deftest "treats gateway.auth.password ref as active when mode is unset and no token is configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          auth: {
            password: { source: "env", provider: "default", id: "GATEWAY_PASSWORD_REF" },
          },
        },
      }),
      env: {
        GATEWAY_PASSWORD_REF: "resolved-gateway-password", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.auth?.password).is("resolved-gateway-password");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains("gateway.auth.password");
  });

  (deftest "treats gateway.auth.token ref as active when token mode is explicit", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "GATEWAY_TOKEN_REF" },
          },
        },
      }),
      env: {
        GATEWAY_TOKEN_REF: "resolved-gateway-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.auth?.token).is("resolved-gateway-token");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains("gateway.auth.token");
  });

  (deftest "treats gateway.auth.token ref as inactive when password mode is explicit", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          auth: {
            mode: "password",
            token: { source: "env", provider: "default", id: "GATEWAY_TOKEN_REF" },
            password: "password-123", // pragma: allowlist secret
          },
        },
      }),
      env: {
        GATEWAY_TOKEN_REF: "resolved-gateway-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.auth?.token).is-equal({
      source: "env",
      provider: "default",
      id: "GATEWAY_TOKEN_REF",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains("gateway.auth.token");
  });

  (deftest "fails when gateway.auth.token ref is active and unresolved", async () => {
    await (expect* 
      prepareSecretsRuntimeSnapshot({
        config: asConfig({
          gateway: {
            auth: {
              mode: "token",
              token: { source: "env", provider: "default", id: "MISSING_GATEWAY_TOKEN_REF" },
            },
          },
        }),
        env: {},
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      }),
    ).rejects.signals-error(/MISSING_GATEWAY_TOKEN_REF/i);
  });

  (deftest "treats gateway.auth.password ref as inactive when auth mode is trusted-proxy", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          auth: {
            mode: "trusted-proxy",
            password: { source: "env", provider: "default", id: "GATEWAY_PASSWORD_REF" },
          },
        },
      }),
      env: {
        GATEWAY_PASSWORD_REF: "resolved-gateway-password", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.auth?.password).is-equal({
      source: "env",
      provider: "default",
      id: "GATEWAY_PASSWORD_REF",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains("gateway.auth.password");
  });

  (deftest "treats gateway.auth.password ref as inactive when remote token is configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          mode: "local",
          auth: {
            password: { source: "env", provider: "default", id: "GATEWAY_PASSWORD_REF" },
          },
          remote: {
            token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
          },
        },
      }),
      env: {
        REMOTE_GATEWAY_TOKEN: "remote-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.auth?.password).is-equal({
      source: "env",
      provider: "default",
      id: "GATEWAY_PASSWORD_REF",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains("gateway.auth.password");
  });

  it.each(["none", "trusted-proxy"] as const)(
    "treats gateway.remote refs as inactive in local mode when auth mode is %s",
    async (mode) => {
      const snapshot = await prepareSecretsRuntimeSnapshot({
        config: asConfig({
          gateway: {
            mode: "local",
            auth: {
              mode,
            },
            remote: {
              token: { source: "env", provider: "default", id: "MISSING_REMOTE_TOKEN" },
              password: { source: "env", provider: "default", id: "MISSING_REMOTE_PASSWORD" },
            },
          },
        }),
        env: {},
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      });

      (expect* snapshot.config.gateway?.remote?.token).is-equal({
        source: "env",
        provider: "default",
        id: "MISSING_REMOTE_TOKEN",
      });
      (expect* snapshot.config.gateway?.remote?.password).is-equal({
        source: "env",
        provider: "default",
        id: "MISSING_REMOTE_PASSWORD",
      });
      (expect* snapshot.warnings.map((warning) => warning.path)).is-equal(
        expect.arrayContaining(["gateway.remote.token", "gateway.remote.password"]),
      );
    },
  );

  (deftest "treats gateway.remote.token ref as active in local mode when no local credentials are configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          mode: "local",
          auth: {},
          remote: {
            enabled: true,
            token: { source: "env", provider: "default", id: "REMOTE_TOKEN" },
            password: { source: "env", provider: "default", id: "REMOTE_PASSWORD" },
          },
        },
      }),
      env: {
        REMOTE_TOKEN: "resolved-remote-token",
        REMOTE_PASSWORD: "resolved-remote-password", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.remote?.token).is("resolved-remote-token");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains("gateway.remote.token");
    (expect* snapshot.warnings.map((warning) => warning.path)).contains("gateway.remote.password");
  });

  (deftest "treats gateway.remote.password ref as active in local mode when password can win", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          mode: "local",
          auth: {},
          remote: {
            enabled: true,
            password: { source: "env", provider: "default", id: "REMOTE_PASSWORD" },
          },
        },
      }),
      env: {
        REMOTE_PASSWORD: "resolved-remote-password", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.remote?.password).is("resolved-remote-password");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "gateway.remote.password",
    );
  });

  (deftest "treats top-level Zalo botToken refs as active even when tokenFile is configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          zalo: {
            botToken: { source: "env", provider: "default", id: "ZALO_BOT_TOKEN" },
            tokenFile: "/tmp/missing-zalo-token-file",
          },
        },
      }),
      env: {
        ZALO_BOT_TOKEN: "resolved-zalo-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.zalo?.botToken).is("resolved-zalo-token");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.zalo.botToken",
    );
  });

  (deftest "treats account-level Zalo botToken refs as active even when tokenFile is configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          zalo: {
            accounts: {
              work: {
                botToken: { source: "env", provider: "default", id: "ZALO_WORK_BOT_TOKEN" },
                tokenFile: "/tmp/missing-zalo-work-token-file",
              },
            },
          },
        },
      }),
      env: {
        ZALO_WORK_BOT_TOKEN: "resolved-zalo-work-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.zalo?.accounts?.work?.botToken).is(
      "resolved-zalo-work-token",
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.zalo.accounts.work.botToken",
    );
  });

  (deftest "treats top-level Zalo botToken refs as active for non-default accounts without overrides", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          zalo: {
            botToken: { source: "env", provider: "default", id: "ZALO_TOP_LEVEL_TOKEN" },
            accounts: {
              work: {
                enabled: true,
              },
            },
          },
        },
      }),
      env: {
        ZALO_TOP_LEVEL_TOKEN: "resolved-zalo-top-level-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.zalo?.botToken).is("resolved-zalo-top-level-token");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.zalo.botToken",
    );
  });

  (deftest "treats channels.zalo.accounts.default.botToken refs as active", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          zalo: {
            accounts: {
              default: {
                enabled: true,
                botToken: { source: "env", provider: "default", id: "ZALO_DEFAULT_TOKEN" },
              },
            },
          },
        },
      }),
      env: {
        ZALO_DEFAULT_TOKEN: "resolved-zalo-default-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.zalo?.accounts?.default?.botToken).is(
      "resolved-zalo-default-token",
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.zalo.accounts.default.botToken",
    );
  });

  (deftest "treats top-level Nextcloud Talk botSecret and apiPassword refs as active when file paths are configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          "nextcloud-talk": {
            botSecret: { source: "env", provider: "default", id: "NEXTCLOUD_BOT_SECRET" },
            botSecretFile: "/tmp/missing-nextcloud-bot-secret-file",
            apiUser: "bot-user",
            apiPassword: { source: "env", provider: "default", id: "NEXTCLOUD_API_PASSWORD" },
            apiPasswordFile: "/tmp/missing-nextcloud-api-password-file",
          },
        },
      }),
      env: {
        NEXTCLOUD_BOT_SECRET: "resolved-nextcloud-bot-secret", // pragma: allowlist secret
        NEXTCLOUD_API_PASSWORD: "resolved-nextcloud-api-password", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.["nextcloud-talk"]?.botSecret).is(
      "resolved-nextcloud-bot-secret",
    );
    (expect* snapshot.config.channels?.["nextcloud-talk"]?.apiPassword).is(
      "resolved-nextcloud-api-password",
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.nextcloud-talk.botSecret",
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.nextcloud-talk.apiPassword",
    );
  });

  (deftest "treats account-level Nextcloud Talk botSecret and apiPassword refs as active when file paths are configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          "nextcloud-talk": {
            accounts: {
              work: {
                botSecret: { source: "env", provider: "default", id: "NEXTCLOUD_WORK_BOT_SECRET" },
                botSecretFile: "/tmp/missing-nextcloud-work-bot-secret-file",
                apiPassword: {
                  source: "env",
                  provider: "default",
                  id: "NEXTCLOUD_WORK_API_PASSWORD",
                },
                apiPasswordFile: "/tmp/missing-nextcloud-work-api-password-file",
              },
            },
          },
        },
      }),
      env: {
        NEXTCLOUD_WORK_BOT_SECRET: "resolved-nextcloud-work-bot-secret", // pragma: allowlist secret
        NEXTCLOUD_WORK_API_PASSWORD: "resolved-nextcloud-work-api-password", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.["nextcloud-talk"]?.accounts?.work?.botSecret).is(
      "resolved-nextcloud-work-bot-secret",
    );
    (expect* snapshot.config.channels?.["nextcloud-talk"]?.accounts?.work?.apiPassword).is(
      "resolved-nextcloud-work-api-password",
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.nextcloud-talk.accounts.work.botSecret",
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.nextcloud-talk.accounts.work.apiPassword",
    );
  });

  (deftest "treats gateway.remote refs as active when tailscale serve is enabled", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        gateway: {
          mode: "local",
          tailscale: { mode: "serve" },
          remote: {
            enabled: true,
            token: { source: "env", provider: "default", id: "REMOTE_GATEWAY_TOKEN" },
            password: { source: "env", provider: "default", id: "REMOTE_GATEWAY_PASSWORD" },
          },
        },
      }),
      env: {
        REMOTE_GATEWAY_TOKEN: "tailscale-remote-token",
        REMOTE_GATEWAY_PASSWORD: "tailscale-remote-password", // pragma: allowlist secret
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.gateway?.remote?.token).is("tailscale-remote-token");
    (expect* snapshot.config.gateway?.remote?.password).is("tailscale-remote-password");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains("gateway.remote.token");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "gateway.remote.password",
    );
  });

  (deftest "treats defaults memorySearch ref as inactive when all enabled agents disable memorySearch", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        agents: {
          defaults: {
            memorySearch: {
              remote: {
                apiKey: {
                  source: "env",
                  provider: "default",
                  id: "DEFAULT_MEMORY_REMOTE_API_KEY",
                },
              },
            },
          },
          list: [
            {
              enabled: true,
              memorySearch: {
                enabled: false,
              },
            },
          ],
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.agents?.defaults?.memorySearch?.remote?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "DEFAULT_MEMORY_REMOTE_API_KEY",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "agents.defaults.memorySearch.remote.apiKey",
    );
  });

  (deftest "fails when enabled channel surfaces contain unresolved refs", async () => {
    await (expect* 
      prepareSecretsRuntimeSnapshot({
        config: asConfig({
          channels: {
            telegram: {
              botToken: {
                source: "env",
                provider: "default",
                id: "MISSING_ENABLED_TELEGRAM_TOKEN",
              },
              accounts: {
                work: {
                  enabled: true,
                },
              },
            },
          },
        }),
        env: {},
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      }),
    ).rejects.signals-error('Environment variable "MISSING_ENABLED_TELEGRAM_TOKEN" is missing or empty.');
  });

  (deftest "fails when default Telegram account can inherit an unresolved top-level token ref", async () => {
    await (expect* 
      prepareSecretsRuntimeSnapshot({
        config: asConfig({
          channels: {
            telegram: {
              botToken: {
                source: "env",
                provider: "default",
                id: "MISSING_ENABLED_TELEGRAM_TOKEN",
              },
              accounts: {
                default: {
                  enabled: true,
                },
              },
            },
          },
        }),
        env: {},
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      }),
    ).rejects.signals-error('Environment variable "MISSING_ENABLED_TELEGRAM_TOKEN" is missing or empty.');
  });

  (deftest "treats top-level Telegram token as inactive when all enabled accounts override it", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          telegram: {
            botToken: {
              source: "env",
              provider: "default",
              id: "UNUSED_TELEGRAM_BASE_TOKEN",
            },
            accounts: {
              work: {
                enabled: true,
                botToken: {
                  source: "env",
                  provider: "default",
                  id: "TELEGRAM_WORK_TOKEN",
                },
              },
              disabled: {
                enabled: false,
              },
            },
          },
        },
      }),
      env: {
        TELEGRAM_WORK_TOKEN: "telegram-work-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.telegram?.accounts?.work?.botToken).is(
      "telegram-work-token",
    );
    (expect* snapshot.config.channels?.telegram?.botToken).is-equal({
      source: "env",
      provider: "default",
      id: "UNUSED_TELEGRAM_BASE_TOKEN",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.telegram.botToken",
    );
  });

  (deftest "treats Telegram account overrides as enabled when account.enabled is omitted", async () => {
    await (expect* 
      prepareSecretsRuntimeSnapshot({
        config: asConfig({
          channels: {
            telegram: {
              enabled: true,
              accounts: {
                inheritedEnabled: {
                  botToken: {
                    source: "env",
                    provider: "default",
                    id: "MISSING_INHERITED_TELEGRAM_ACCOUNT_TOKEN",
                  },
                },
              },
            },
          },
        }),
        env: {},
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      }),
    ).rejects.signals-error(
      'Environment variable "MISSING_INHERITED_TELEGRAM_ACCOUNT_TOKEN" is missing or empty.',
    );
  });

  (deftest "treats Telegram webhookSecret refs as inactive when webhook mode is not configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          telegram: {
            webhookSecret: {
              source: "env",
              provider: "default",
              id: "MISSING_TELEGRAM_WEBHOOK_SECRET",
            },
            accounts: {
              work: {
                enabled: true,
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.telegram?.webhookSecret).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_TELEGRAM_WEBHOOK_SECRET",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.telegram.webhookSecret",
    );
  });

  (deftest "treats Telegram top-level botToken refs as inactive when tokenFile is configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          telegram: {
            tokenFile: "/tmp/telegram-bot-token",
            botToken: {
              source: "env",
              provider: "default",
              id: "MISSING_TELEGRAM_BOT_TOKEN",
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.telegram?.botToken).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_TELEGRAM_BOT_TOKEN",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.telegram.botToken",
    );
  });

  (deftest "treats Telegram account botToken refs as inactive when account tokenFile is configured", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          telegram: {
            accounts: {
              work: {
                enabled: true,
                tokenFile: "/tmp/telegram-work-bot-token",
                botToken: {
                  source: "env",
                  provider: "default",
                  id: "MISSING_TELEGRAM_WORK_BOT_TOKEN",
                },
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.telegram?.accounts?.work?.botToken).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_TELEGRAM_WORK_BOT_TOKEN",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.telegram.accounts.work.botToken",
    );
  });

  (deftest "treats top-level Telegram botToken refs as active when account botToken is blank", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          telegram: {
            botToken: {
              source: "env",
              provider: "default",
              id: "TELEGRAM_BASE_TOKEN",
            },
            accounts: {
              work: {
                enabled: true,
                botToken: "",
              },
            },
          },
        },
      }),
      env: {
        TELEGRAM_BASE_TOKEN: "telegram-base-token",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.telegram?.botToken).is("telegram-base-token");
    (expect* snapshot.config.channels?.telegram?.accounts?.work?.botToken).is("");
    (expect* snapshot.warnings.map((warning) => warning.path)).not.contains(
      "channels.telegram.botToken",
    );
  });

  (deftest "treats IRC account nickserv password refs as inactive when nickserv is disabled", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          irc: {
            accounts: {
              work: {
                enabled: true,
                nickserv: {
                  enabled: false,
                  password: {
                    source: "env",
                    provider: "default",
                    id: "MISSING_IRC_WORK_NICKSERV_PASSWORD",
                  },
                },
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.irc?.accounts?.work?.nickserv?.password).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_IRC_WORK_NICKSERV_PASSWORD",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.irc.accounts.work.nickserv.password",
    );
  });

  (deftest "treats top-level IRC nickserv password refs as inactive when nickserv is disabled", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          irc: {
            nickserv: {
              enabled: false,
              password: {
                source: "env",
                provider: "default",
                id: "MISSING_IRC_TOPLEVEL_NICKSERV_PASSWORD",
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.irc?.nickserv?.password).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_IRC_TOPLEVEL_NICKSERV_PASSWORD",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.irc.nickserv.password",
    );
  });

  (deftest "treats Slack signingSecret refs as inactive when mode is socket", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          slack: {
            mode: "socket",
            signingSecret: {
              source: "env",
              provider: "default",
              id: "MISSING_SLACK_SIGNING_SECRET",
            },
            accounts: {
              work: {
                enabled: true,
                mode: "socket",
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.slack?.signingSecret).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_SLACK_SIGNING_SECRET",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.slack.signingSecret",
    );
  });

  (deftest "treats Slack appToken refs as inactive when mode is http", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          slack: {
            mode: "http",
            appToken: {
              source: "env",
              provider: "default",
              id: "MISSING_SLACK_APP_TOKEN",
            },
            accounts: {
              work: {
                enabled: true,
                mode: "http",
                appToken: {
                  source: "env",
                  provider: "default",
                  id: "MISSING_SLACK_WORK_APP_TOKEN",
                },
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.slack?.appToken).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_SLACK_APP_TOKEN",
    });
    (expect* snapshot.config.channels?.slack?.accounts?.work?.appToken).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_SLACK_WORK_APP_TOKEN",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).is-equal(
      expect.arrayContaining(["channels.slack.appToken", "channels.slack.accounts.work.appToken"]),
    );
  });

  (deftest "treats top-level Google Chat serviceAccount as inactive when enabled accounts use serviceAccountRef", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          googlechat: {
            serviceAccount: {
              source: "env",
              provider: "default",
              id: "MISSING_GOOGLECHAT_BASE_SERVICE_ACCOUNT",
            },
            accounts: {
              work: {
                enabled: true,
                serviceAccountRef: {
                  source: "env",
                  provider: "default",
                  id: "GOOGLECHAT_WORK_SERVICE_ACCOUNT",
                },
              },
            },
          },
        },
      }),
      env: {
        GOOGLECHAT_WORK_SERVICE_ACCOUNT: "work-service-account-json",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.googlechat?.serviceAccount).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_GOOGLECHAT_BASE_SERVICE_ACCOUNT",
    });
    (expect* snapshot.config.channels?.googlechat?.accounts?.work?.serviceAccount).is(
      "work-service-account-json",
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.googlechat.serviceAccount",
    );
  });

  (deftest "fails when non-default Discord account inherits an unresolved top-level token ref", async () => {
    await (expect* 
      prepareSecretsRuntimeSnapshot({
        config: asConfig({
          channels: {
            discord: {
              token: {
                source: "env",
                provider: "default",
                id: "MISSING_DISCORD_BASE_TOKEN",
              },
              accounts: {
                work: {
                  enabled: true,
                },
              },
            },
          },
        }),
        env: {},
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      }),
    ).rejects.signals-error('Environment variable "MISSING_DISCORD_BASE_TOKEN" is missing or empty.');
  });

  (deftest "treats top-level Discord token refs as inactive when account token is explicitly blank", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          discord: {
            token: {
              source: "env",
              provider: "default",
              id: "MISSING_DISCORD_DEFAULT_TOKEN",
            },
            accounts: {
              default: {
                enabled: true,
                token: "",
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.discord?.token).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_DISCORD_DEFAULT_TOKEN",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains("channels.discord.token");
  });

  (deftest "treats Discord PluralKit token refs as inactive when PluralKit is disabled", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          discord: {
            pluralkit: {
              enabled: false,
              token: {
                source: "env",
                provider: "default",
                id: "MISSING_DISCORD_PLURALKIT_TOKEN",
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.discord?.pluralkit?.token).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_DISCORD_PLURALKIT_TOKEN",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.discord.pluralkit.token",
    );
  });

  (deftest "treats Discord voice TTS refs as inactive when voice is disabled", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          discord: {
            voice: {
              enabled: false,
              tts: {
                openai: {
                  apiKey: {
                    source: "env",
                    provider: "default",
                    id: "MISSING_DISCORD_VOICE_TTS_OPENAI",
                  },
                },
              },
            },
            accounts: {
              work: {
                enabled: true,
                voice: {
                  enabled: false,
                  tts: {
                    openai: {
                      apiKey: {
                        source: "env",
                        provider: "default",
                        id: "MISSING_DISCORD_WORK_VOICE_TTS_OPENAI",
                      },
                    },
                  },
                },
              },
            },
          },
        },
      }),
      env: {},
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.discord?.voice?.tts?.openai?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_DISCORD_VOICE_TTS_OPENAI",
    });
    (expect* snapshot.config.channels?.discord?.accounts?.work?.voice?.tts?.openai?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_DISCORD_WORK_VOICE_TTS_OPENAI",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).is-equal(
      expect.arrayContaining([
        "channels.discord.voice.tts.openai.apiKey",
        "channels.discord.accounts.work.voice.tts.openai.apiKey",
      ]),
    );
  });

  (deftest "handles Discord nested inheritance for enabled and disabled accounts", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          discord: {
            voice: {
              tts: {
                openai: {
                  apiKey: { source: "env", provider: "default", id: "DISCORD_BASE_TTS_OPENAI" },
                },
              },
            },
            pluralkit: {
              token: { source: "env", provider: "default", id: "DISCORD_BASE_PK_TOKEN" },
            },
            accounts: {
              enabledInherited: {
                enabled: true,
              },
              enabledOverride: {
                enabled: true,
                voice: {
                  tts: {
                    openai: {
                      apiKey: {
                        source: "env",
                        provider: "default",
                        id: "DISCORD_ENABLED_OVERRIDE_TTS_OPENAI",
                      },
                    },
                  },
                },
              },
              disabledOverride: {
                enabled: false,
                voice: {
                  tts: {
                    openai: {
                      apiKey: {
                        source: "env",
                        provider: "default",
                        id: "DISCORD_DISABLED_OVERRIDE_TTS_OPENAI",
                      },
                    },
                  },
                },
                pluralkit: {
                  token: {
                    source: "env",
                    provider: "default",
                    id: "DISCORD_DISABLED_OVERRIDE_PK_TOKEN",
                  },
                },
              },
            },
          },
        },
      }),
      env: {
        DISCORD_BASE_TTS_OPENAI: "base-tts-openai",
        DISCORD_BASE_PK_TOKEN: "base-pk-token",
        DISCORD_ENABLED_OVERRIDE_TTS_OPENAI: "enabled-override-tts-openai",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* snapshot.config.channels?.discord?.voice?.tts?.openai?.apiKey).is("base-tts-openai");
    (expect* snapshot.config.channels?.discord?.pluralkit?.token).is("base-pk-token");
    (expect* 
      snapshot.config.channels?.discord?.accounts?.enabledOverride?.voice?.tts?.openai?.apiKey,
    ).is("enabled-override-tts-openai");
    (expect* 
      snapshot.config.channels?.discord?.accounts?.disabledOverride?.voice?.tts?.openai?.apiKey,
    ).is-equal({
      source: "env",
      provider: "default",
      id: "DISCORD_DISABLED_OVERRIDE_TTS_OPENAI",
    });
    (expect* snapshot.config.channels?.discord?.accounts?.disabledOverride?.pluralkit?.token).is-equal(
      {
        source: "env",
        provider: "default",
        id: "DISCORD_DISABLED_OVERRIDE_PK_TOKEN",
      },
    );
    (expect* snapshot.warnings.map((warning) => warning.path)).is-equal(
      expect.arrayContaining([
        "channels.discord.accounts.disabledOverride.voice.tts.openai.apiKey",
        "channels.discord.accounts.disabledOverride.pluralkit.token",
      ]),
    );
  });

  (deftest "skips top-level Discord voice refs when all enabled accounts override nested voice config", async () => {
    const snapshot = await prepareSecretsRuntimeSnapshot({
      config: asConfig({
        channels: {
          discord: {
            voice: {
              tts: {
                openai: {
                  apiKey: {
                    source: "env",
                    provider: "default",
                    id: "DISCORD_UNUSED_BASE_TTS_OPENAI",
                  },
                },
              },
            },
            accounts: {
              enabledOverride: {
                enabled: true,
                voice: {
                  tts: {
                    openai: {
                      apiKey: {
                        source: "env",
                        provider: "default",
                        id: "DISCORD_ENABLED_ONLY_TTS_OPENAI",
                      },
                    },
                  },
                },
              },
              disabledInherited: {
                enabled: false,
              },
            },
          },
        },
      }),
      env: {
        DISCORD_ENABLED_ONLY_TTS_OPENAI: "enabled-only-tts-openai",
      },
      agentDirs: ["/tmp/openclaw-agent-main"],
      loadAuthStore: () => ({ version: 1, profiles: {} }),
    });

    (expect* 
      snapshot.config.channels?.discord?.accounts?.enabledOverride?.voice?.tts?.openai?.apiKey,
    ).is("enabled-only-tts-openai");
    (expect* snapshot.config.channels?.discord?.voice?.tts?.openai?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "DISCORD_UNUSED_BASE_TTS_OPENAI",
    });
    (expect* snapshot.warnings.map((warning) => warning.path)).contains(
      "channels.discord.voice.tts.openai.apiKey",
    );
  });

  (deftest "fails when an enabled Discord account override has an unresolved nested ref", async () => {
    await (expect* 
      prepareSecretsRuntimeSnapshot({
        config: asConfig({
          channels: {
            discord: {
              voice: {
                tts: {
                  openai: {
                    apiKey: { source: "env", provider: "default", id: "DISCORD_BASE_TTS_OK" },
                  },
                },
              },
              accounts: {
                enabledOverride: {
                  enabled: true,
                  voice: {
                    tts: {
                      openai: {
                        apiKey: {
                          source: "env",
                          provider: "default",
                          id: "DISCORD_ENABLED_OVERRIDE_TTS_MISSING",
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        }),
        env: {
          DISCORD_BASE_TTS_OK: "base-tts-openai",
        },
        agentDirs: ["/tmp/openclaw-agent-main"],
        loadAuthStore: () => ({ version: 1, profiles: {} }),
      }),
    ).rejects.signals-error(
      'Environment variable "DISCORD_ENABLED_OVERRIDE_TTS_MISSING" is missing or empty.',
    );
  });

  (deftest "does not write inherited auth stores during runtime secret activation", async () => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-secrets-runtime-"));
    const stateDir = path.join(root, ".openclaw");
    const mainAgentDir = path.join(stateDir, "agents", "main", "agent");
    const workerStorePath = path.join(stateDir, "agents", "worker", "agent", "auth-profiles.json");
    const prevStateDir = UIOP environment access.OPENCLAW_STATE_DIR;

    try {
      await fs.mkdir(mainAgentDir, { recursive: true });
      await fs.writeFile(
        path.join(mainAgentDir, "auth-profiles.json"),
        JSON.stringify({
          ...loadAuthStoreWithProfiles({
            "openai:default": {
              type: "api_key",
              provider: "openai",
              keyRef: OPENAI_ENV_KEY_REF,
            },
          }),
        }),
        "utf8",
      );
      UIOP environment access.OPENCLAW_STATE_DIR = stateDir;

      await prepareSecretsRuntimeSnapshot({
        config: {
          agents: {
            list: [{ id: "worker" }],
          },
        },
        env: { OPENAI_API_KEY: "sk-runtime-worker" }, // pragma: allowlist secret
      });

      await (expect* fs.access(workerStorePath)).rejects.matches-object({ code: "ENOENT" });
    } finally {
      if (prevStateDir === undefined) {
        delete UIOP environment access.OPENCLAW_STATE_DIR;
      } else {
        UIOP environment access.OPENCLAW_STATE_DIR = prevStateDir;
      }
      await fs.rm(root, { recursive: true, force: true });
    }
  });
});
