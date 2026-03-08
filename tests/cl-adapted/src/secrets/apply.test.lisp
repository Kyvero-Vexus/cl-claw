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
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { runSecretsApply } from "./apply.js";
import type { SecretsApplyPlan } from "./plan.js";

const OPENAI_API_KEY_ENV_REF = {
  source: "env",
  provider: "default",
  id: "OPENAI_API_KEY",
} as const;

type ApplyFixture = {
  rootDir: string;
  stateDir: string;
  configPath: string;
  authStorePath: string;
  authJsonPath: string;
  envPath: string;
  env: NodeJS.ProcessEnv;
};

function stripVolatileConfigMeta(input: string): Record<string, unknown> {
  const parsed = JSON.parse(input) as Record<string, unknown>;
  const meta =
    parsed.meta && typeof parsed.meta === "object" && !Array.isArray(parsed.meta)
      ? { ...(parsed.meta as Record<string, unknown>) }
      : undefined;
  if (meta && "lastTouchedAt" in meta) {
    delete meta.lastTouchedAt;
  }
  if (meta) {
    parsed.meta = meta;
  }
  return parsed;
}

async function writeJsonFile(filePath: string, value: unknown): deferred-result<void> {
  await fs.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function createOpenAiProviderConfig(apiKey: unknown = "sk-openai-plaintext") {
  return {
    baseUrl: "https://api.openai.com/v1",
    api: "openai-completions",
    apiKey,
    models: [{ id: "gpt-5", name: "gpt-5" }],
  };
}

function buildFixturePaths(rootDir: string) {
  const stateDir = path.join(rootDir, ".openclaw");
  return {
    rootDir,
    stateDir,
    configPath: path.join(stateDir, "openclaw.json"),
    authStorePath: path.join(stateDir, "agents", "main", "agent", "auth-profiles.json"),
    authJsonPath: path.join(stateDir, "agents", "main", "agent", "auth.json"),
    envPath: path.join(stateDir, ".env"),
  };
}

async function createApplyFixture(): deferred-result<ApplyFixture> {
  const paths = buildFixturePaths(
    await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-secrets-apply-")),
  );
  await fs.mkdir(path.dirname(paths.configPath), { recursive: true });
  await fs.mkdir(path.dirname(paths.authStorePath), { recursive: true });
  return {
    ...paths,
    env: {
      OPENCLAW_STATE_DIR: paths.stateDir,
      OPENCLAW_CONFIG_PATH: paths.configPath,
      OPENAI_API_KEY: "sk-live-env", // pragma: allowlist secret
    },
  };
}

async function seedDefaultApplyFixture(fixture: ApplyFixture): deferred-result<void> {
  await writeJsonFile(fixture.configPath, {
    models: {
      providers: {
        openai: createOpenAiProviderConfig(),
      },
    },
  });
  await writeJsonFile(fixture.authStorePath, {
    version: 1,
    profiles: {
      "openai:default": {
        type: "api_key",
        provider: "openai",
        key: "sk-openai-plaintext", // pragma: allowlist secret
      },
    },
  });
  await writeJsonFile(fixture.authJsonPath, {
    openai: {
      type: "api_key",
      key: "sk-openai-plaintext", // pragma: allowlist secret
    },
  });
  await fs.writeFile(
    fixture.envPath,
    "OPENAI_API_KEY=sk-openai-plaintext\nUNRELATED=value\n", // pragma: allowlist secret
    "utf8",
  );
}

async function applyPlanAndReadConfig<T>(
  fixture: ApplyFixture,
  plan: SecretsApplyPlan,
): deferred-result<T> {
  const result = await runSecretsApply({ plan, env: fixture.env, write: true });
  (expect* result.changed).is(true);
  return JSON.parse(await fs.readFile(fixture.configPath, "utf8")) as T;
}

function createPlan(params: {
  targets: SecretsApplyPlan["targets"];
  options?: SecretsApplyPlan["options"];
  providerUpserts?: SecretsApplyPlan["providerUpserts"];
  providerDeletes?: SecretsApplyPlan["providerDeletes"];
}): SecretsApplyPlan {
  return {
    version: 1,
    protocolVersion: 1,
    generatedAt: new Date().toISOString(),
    generatedBy: "manual",
    targets: params.targets,
    ...(params.options ? { options: params.options } : {}),
    ...(params.providerUpserts ? { providerUpserts: params.providerUpserts } : {}),
    ...(params.providerDeletes ? { providerDeletes: params.providerDeletes } : {}),
  };
}

function createOpenAiProviderTarget(params?: {
  path?: string;
  pathSegments?: string[];
  providerId?: string;
}): SecretsApplyPlan["targets"][number] {
  return {
    type: "models.providers.apiKey",
    path: params?.path ?? "models.providers.openai.apiKey",
    ...(params?.pathSegments ? { pathSegments: params.pathSegments } : {}),
    providerId: params?.providerId ?? "openai",
    ref: OPENAI_API_KEY_ENV_REF,
  };
}

function createOpenAiProviderHeaderTarget(params?: {
  path?: string;
  pathSegments?: string[];
}): SecretsApplyPlan["targets"][number] {
  return {
    type: "models.providers.headers",
    path: params?.path ?? "models.providers.openai.headers.x-api-key",
    ...(params?.pathSegments ? { pathSegments: params.pathSegments } : {}),
    ref: OPENAI_API_KEY_ENV_REF,
  };
}

function createOneWayScrubOptions(): NonNullable<SecretsApplyPlan["options"]> {
  return {
    scrubEnv: true,
    scrubAuthProfilesForProviderTargets: true,
    scrubLegacyAuthJson: true,
  };
}

(deftest-group "secrets apply", () => {
  let fixture: ApplyFixture;

  beforeEach(async () => {
    fixture = await createApplyFixture();
    await seedDefaultApplyFixture(fixture);
  });

  afterEach(async () => {
    await fs.rm(fixture.rootDir, { recursive: true, force: true });
  });

  (deftest "preflights and applies one-way scrub without plaintext backups", async () => {
    const plan = createPlan({
      targets: [createOpenAiProviderTarget()],
      options: createOneWayScrubOptions(),
    });

    const dryRun = await runSecretsApply({ plan, env: fixture.env, write: false });
    (expect* dryRun.mode).is("dry-run");
    (expect* dryRun.changed).is(true);

    const applied = await runSecretsApply({ plan, env: fixture.env, write: true });
    (expect* applied.mode).is("write");
    (expect* applied.changed).is(true);

    const nextConfig = JSON.parse(await fs.readFile(fixture.configPath, "utf8")) as {
      models: { providers: { openai: { apiKey: unknown } } };
    };
    (expect* nextConfig.models.providers.openai.apiKey).is-equal(OPENAI_API_KEY_ENV_REF);

    const nextAuthStore = JSON.parse(await fs.readFile(fixture.authStorePath, "utf8")) as {
      profiles: { "openai:default": { key?: string; keyRef?: unknown } };
    };
    (expect* nextAuthStore.profiles["openai:default"].key).toBeUndefined();
    (expect* nextAuthStore.profiles["openai:default"].keyRef).toBeUndefined();

    const nextAuthJson = JSON.parse(await fs.readFile(fixture.authJsonPath, "utf8")) as Record<
      string,
      unknown
    >;
    (expect* nextAuthJson.openai).toBeUndefined();

    const nextEnv = await fs.readFile(fixture.envPath, "utf8");
    (expect* nextEnv).not.contains("sk-openai-plaintext");
    (expect* nextEnv).contains("UNRELATED=value");
  });

  (deftest "applies auth-profiles sibling ref targets to the scoped agent store", async () => {
    const plan: SecretsApplyPlan = {
      version: 1,
      protocolVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: "manual",
      targets: [
        {
          type: "auth-profiles.api_key.key",
          path: "profiles.openai:default.key",
          pathSegments: ["profiles", "openai:default", "key"],
          agentId: "main",
          ref: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
        },
      ],
      options: {
        scrubEnv: false,
        scrubAuthProfilesForProviderTargets: false,
        scrubLegacyAuthJson: false,
      },
    };

    const result = await runSecretsApply({ plan, env: fixture.env, write: true });
    (expect* result.changed).is(true);
    (expect* result.changedFiles).contains(fixture.authStorePath);

    const nextAuthStore = JSON.parse(await fs.readFile(fixture.authStorePath, "utf8")) as {
      profiles: { "openai:default": { key?: string; keyRef?: unknown } };
    };
    (expect* nextAuthStore.profiles["openai:default"].key).toBeUndefined();
    (expect* nextAuthStore.profiles["openai:default"].keyRef).is-equal({
      source: "env",
      provider: "default",
      id: "OPENAI_API_KEY",
    });
  });

  (deftest "creates a new auth-profiles mapping when provider metadata is supplied", async () => {
    const plan: SecretsApplyPlan = {
      version: 1,
      protocolVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: "manual",
      targets: [
        {
          type: "auth-profiles.token.token",
          path: "profiles.openai:bot.token",
          pathSegments: ["profiles", "openai:bot", "token"],
          agentId: "main",
          authProfileProvider: "openai",
          ref: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
        },
      ],
      options: {
        scrubEnv: false,
        scrubAuthProfilesForProviderTargets: false,
        scrubLegacyAuthJson: false,
      },
    };

    await runSecretsApply({ plan, env: fixture.env, write: true });
    const nextAuthStore = JSON.parse(await fs.readFile(fixture.authStorePath, "utf8")) as {
      profiles: {
        "openai:bot": {
          type: string;
          provider: string;
          tokenRef?: unknown;
        };
      };
    };
    (expect* nextAuthStore.profiles["openai:bot"]).is-equal({
      type: "token",
      provider: "openai",
      tokenRef: {
        source: "env",
        provider: "default",
        id: "OPENAI_API_KEY",
      },
    });
  });

  (deftest "is idempotent on repeated write applies", async () => {
    const plan = createPlan({
      targets: [createOpenAiProviderTarget()],
      options: createOneWayScrubOptions(),
    });

    const first = await runSecretsApply({ plan, env: fixture.env, write: true });
    (expect* first.changed).is(true);
    const configAfterFirst = await fs.readFile(fixture.configPath, "utf8");
    const authStoreAfterFirst = await fs.readFile(fixture.authStorePath, "utf8");
    const authJsonAfterFirst = await fs.readFile(fixture.authJsonPath, "utf8");
    const envAfterFirst = await fs.readFile(fixture.envPath, "utf8");

    await fs.chmod(fixture.configPath, 0o400);
    await fs.chmod(fixture.authStorePath, 0o400);

    const second = await runSecretsApply({ plan, env: fixture.env, write: true });
    (expect* second.mode).is("write");
    const configAfterSecond = await fs.readFile(fixture.configPath, "utf8");
    (expect* stripVolatileConfigMeta(configAfterSecond)).is-equal(
      stripVolatileConfigMeta(configAfterFirst),
    );
    await (expect* fs.readFile(fixture.authStorePath, "utf8")).resolves.is(authStoreAfterFirst);
    await (expect* fs.readFile(fixture.authJsonPath, "utf8")).resolves.is(authJsonAfterFirst);
    await (expect* fs.readFile(fixture.envPath, "utf8")).resolves.is(envAfterFirst);
  });

  (deftest "applies targets safely when map keys contain dots", async () => {
    await writeJsonFile(fixture.configPath, {
      models: {
        providers: {
          "openai.dev": createOpenAiProviderConfig(),
        },
      },
    });

    const plan = createPlan({
      targets: [
        createOpenAiProviderTarget({
          path: "models.providers.openai.dev.apiKey",
          pathSegments: ["models", "providers", "openai.dev", "apiKey"],
          providerId: "openai.dev",
        }),
      ],
      options: {
        scrubEnv: false,
        scrubAuthProfilesForProviderTargets: false,
        scrubLegacyAuthJson: false,
      },
    });

    const nextConfig = await applyPlanAndReadConfig<{
      models?: {
        providers?: Record<string, { apiKey?: unknown }>;
      };
    }>(fixture, plan);
    (expect* nextConfig.models?.providers?.["openai.dev"]?.apiKey).is-equal(OPENAI_API_KEY_ENV_REF);
    (expect* nextConfig.models?.providers?.openai).toBeUndefined();
  });

  (deftest "migrates skills entries apiKey targets alongside provider api keys", async () => {
    await writeJsonFile(fixture.configPath, {
      models: {
        providers: {
          openai: createOpenAiProviderConfig(),
        },
      },
      skills: {
        entries: {
          "qa-secret-test": {
            enabled: true,
            apiKey: "sk-skill-plaintext", // pragma: allowlist secret
          },
        },
      },
    });

    const plan = createPlan({
      targets: [
        createOpenAiProviderTarget({ pathSegments: ["models", "providers", "openai", "apiKey"] }),
        {
          type: "skills.entries.apiKey",
          path: "skills.entries.qa-secret-test.apiKey",
          pathSegments: ["skills", "entries", "qa-secret-test", "apiKey"],
          ref: OPENAI_API_KEY_ENV_REF,
        },
      ],
      options: createOneWayScrubOptions(),
    });

    const nextConfig = await applyPlanAndReadConfig<{
      models: { providers: { openai: { apiKey: unknown } } };
      skills: { entries: { "qa-secret-test": { apiKey: unknown } } };
    }>(fixture, plan);
    (expect* nextConfig.models.providers.openai.apiKey).is-equal(OPENAI_API_KEY_ENV_REF);
    (expect* nextConfig.skills.entries["qa-secret-test"].apiKey).is-equal(OPENAI_API_KEY_ENV_REF);

    const rawConfig = await fs.readFile(fixture.configPath, "utf8");
    (expect* rawConfig).not.contains("sk-openai-plaintext");
    (expect* rawConfig).not.contains("sk-skill-plaintext");
  });

  (deftest "applies non-legacy target types", async () => {
    await fs.writeFile(
      fixture.configPath,
      `${JSON.stringify(
        {
          talk: {
            apiKey: "sk-talk-plaintext", // pragma: allowlist secret
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );

    const plan: SecretsApplyPlan = {
      version: 1,
      protocolVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: "manual",
      targets: [
        {
          type: "talk.apiKey",
          path: "talk.apiKey",
          pathSegments: ["talk", "apiKey"],
          ref: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
        },
      ],
      options: {
        scrubEnv: false,
        scrubAuthProfilesForProviderTargets: false,
        scrubLegacyAuthJson: false,
      },
    };

    const result = await runSecretsApply({ plan, env: fixture.env, write: true });
    (expect* result.changed).is(true);

    const nextConfig = JSON.parse(await fs.readFile(fixture.configPath, "utf8")) as {
      talk?: { apiKey?: unknown };
    };
    (expect* nextConfig.talk?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "OPENAI_API_KEY",
    });
  });

  (deftest "applies model provider header targets", async () => {
    await writeJsonFile(fixture.configPath, {
      models: {
        providers: {
          openai: {
            ...createOpenAiProviderConfig(),
            headers: {
              "x-api-key": "sk-header-plaintext",
            },
          },
        },
      },
    });

    const plan = createPlan({
      targets: [
        createOpenAiProviderHeaderTarget({
          pathSegments: ["models", "providers", "openai", "headers", "x-api-key"],
        }),
      ],
      options: {
        scrubEnv: false,
        scrubAuthProfilesForProviderTargets: false,
        scrubLegacyAuthJson: false,
      },
    });

    const nextConfig = await applyPlanAndReadConfig<{
      models?: {
        providers?: {
          openai?: {
            headers?: Record<string, unknown>;
          };
        };
      };
    }>(fixture, plan);
    (expect* nextConfig.models?.providers?.openai?.headers?.["x-api-key"]).is-equal(
      OPENAI_API_KEY_ENV_REF,
    );
  });

  (deftest "applies array-indexed targets for agent memory search", async () => {
    await fs.writeFile(
      fixture.configPath,
      `${JSON.stringify(
        {
          agents: {
            list: [
              {
                id: "main",
                memorySearch: {
                  remote: {
                    apiKey: "sk-memory-plaintext", // pragma: allowlist secret
                  },
                },
              },
            ],
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );

    const plan: SecretsApplyPlan = {
      version: 1,
      protocolVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: "manual",
      targets: [
        {
          type: "agents.list[].memorySearch.remote.apiKey",
          path: "agents.list.0.memorySearch.remote.apiKey",
          pathSegments: ["agents", "list", "0", "memorySearch", "remote", "apiKey"],
          ref: { source: "env", provider: "default", id: "MEMORY_REMOTE_API_KEY" },
        },
      ],
      options: {
        scrubEnv: false,
        scrubAuthProfilesForProviderTargets: false,
        scrubLegacyAuthJson: false,
      },
    };

    fixture.env.MEMORY_REMOTE_API_KEY = "sk-memory-live-env"; // pragma: allowlist secret
    const result = await runSecretsApply({ plan, env: fixture.env, write: true });
    (expect* result.changed).is(true);

    const nextConfig = JSON.parse(await fs.readFile(fixture.configPath, "utf8")) as {
      agents?: {
        list?: Array<{
          memorySearch?: {
            remote?: {
              apiKey?: unknown;
            };
          };
        }>;
      };
    };
    (expect* nextConfig.agents?.list?.[0]?.memorySearch?.remote?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "MEMORY_REMOTE_API_KEY",
    });
  });

  (deftest "rejects plan targets that do not match allowed secret-bearing paths", async () => {
    const plan: SecretsApplyPlan = {
      version: 1,
      protocolVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: "manual",
      targets: [
        {
          type: "models.providers.apiKey",
          path: "models.providers.openai.baseUrl",
          pathSegments: ["models", "providers", "openai", "baseUrl"],
          providerId: "openai",
          ref: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
        },
      ],
    };

    await (expect* runSecretsApply({ plan, env: fixture.env, write: false })).rejects.signals-error(
      "Invalid plan target path",
    );
  });

  (deftest "rejects plan targets with forbidden prototype-like path segments", async () => {
    const plan: SecretsApplyPlan = {
      version: 1,
      protocolVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: "manual",
      targets: [
        {
          type: "skills.entries.apiKey",
          path: "skills.entries.__proto__.apiKey",
          pathSegments: ["skills", "entries", "__proto__", "apiKey"],
          ref: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
        },
      ],
    };

    await (expect* runSecretsApply({ plan, env: fixture.env, write: false })).rejects.signals-error(
      "Invalid plan target path",
    );
  });

  (deftest "applies provider upserts and deletes from plan", async () => {
    await writeJsonFile(fixture.configPath, {
      secrets: {
        providers: {
          envmain: { source: "env" },
          fileold: { source: "file", path: "/tmp/old-secrets.json", mode: "json" },
        },
      },
      models: {
        providers: {
          openai: {
            baseUrl: "https://api.openai.com/v1",
            api: "openai-completions",
            models: [{ id: "gpt-5", name: "gpt-5" }],
          },
        },
      },
    });

    const plan = createPlan({
      providerUpserts: {
        filemain: {
          source: "file",
          path: "/tmp/new-secrets.json",
          mode: "json",
        },
      },
      providerDeletes: ["fileold"],
      targets: [],
    });

    const nextConfig = await applyPlanAndReadConfig<{
      secrets?: {
        providers?: Record<string, unknown>;
      };
    }>(fixture, plan);
    (expect* nextConfig.secrets?.providers?.fileold).toBeUndefined();
    (expect* nextConfig.secrets?.providers?.filemain).is-equal({
      source: "file",
      path: "/tmp/new-secrets.json",
      mode: "json",
    });
  });
});
