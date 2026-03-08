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

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

let modelsListCommand: typeof import("./models/list.list-command.js").modelsListCommand;
let loadModelRegistry: typeof import("./models/list.registry.js").loadModelRegistry;
let toModelRow: typeof import("./models/list.registry.js").toModelRow;

const loadConfig = mock:fn();
const readConfigFileSnapshotForWrite = mock:fn().mockResolvedValue({
  snapshot: { valid: false, resolved: {} },
  writeOptions: {},
});
const setRuntimeConfigSnapshot = mock:fn();
const ensureOpenClawModelsJson = mock:fn().mockResolvedValue(undefined);
const resolveOpenClawAgentDir = mock:fn().mockReturnValue("/tmp/openclaw-agent");
const ensureAuthProfileStore = mock:fn().mockReturnValue({ version: 1, profiles: {} });
const listProfilesForProvider = mock:fn().mockReturnValue([]);
const resolveAuthProfileDisplayLabel = mock:fn(({ profileId }: { profileId: string }) => profileId);
const resolveAuthStorePathForDisplay = vi
  .fn()
  .mockReturnValue("/tmp/openclaw-agent/auth-profiles.json");
const resolveProfileUnusableUntilForDisplay = mock:fn().mockReturnValue(null);
const resolveEnvApiKey = mock:fn().mockReturnValue(undefined);
const resolveAwsSdkEnvVarName = mock:fn().mockReturnValue(undefined);
const getCustomProviderApiKey = mock:fn().mockReturnValue(undefined);
const modelRegistryState = {
  models: [] as Array<Record<string, unknown>>,
  available: [] as Array<Record<string, unknown>>,
  getAllError: undefined as unknown,
  getAvailableError: undefined as unknown,
};
let previousExitCode: typeof process.exitCode;

mock:mock("../config/config.js", () => ({
  CONFIG_PATH: "/tmp/openclaw.json",
  STATE_DIR: "/tmp/openclaw-state",
  loadConfig,
  readConfigFileSnapshotForWrite,
  setRuntimeConfigSnapshot,
}));

mock:mock("../agents/models-config.js", () => ({
  ensureOpenClawModelsJson,
}));

mock:mock("../agents/agent-paths.js", () => ({
  resolveOpenClawAgentDir,
}));

mock:mock("../agents/auth-profiles.js", () => ({
  ensureAuthProfileStore,
  listProfilesForProvider,
  resolveAuthProfileDisplayLabel,
  resolveAuthStorePathForDisplay,
  resolveProfileUnusableUntilForDisplay,
}));

mock:mock("../agents/model-auth.js", () => ({
  resolveEnvApiKey,
  resolveAwsSdkEnvVarName,
  getCustomProviderApiKey,
}));

mock:mock("../agents/pi-model-discovery.js", () => {
  class MockModelRegistry {
    find(provider: string, id: string) {
      return (
        modelRegistryState.models.find((model) => model.provider === provider && model.id === id) ??
        null
      );
    }

    getAll() {
      if (modelRegistryState.getAllError !== undefined) {
        throw modelRegistryState.getAllError;
      }
      return modelRegistryState.models;
    }

    getAvailable() {
      if (modelRegistryState.getAvailableError !== undefined) {
        throw modelRegistryState.getAvailableError;
      }
      return modelRegistryState.available;
    }
  }

  return {
    discoverAuthStorage: () => ({}) as unknown,
    discoverModels: () => new MockModelRegistry() as unknown,
  };
});

mock:mock("../agents/pi-embedded-runner/model.js", () => ({
  resolveModelWithRegistry: ({
    provider,
    modelId,
    modelRegistry,
  }: {
    provider: string;
    modelId: string;
    modelRegistry: { find: (provider: string, id: string) => unknown };
  }) => {
    return modelRegistry.find(provider, modelId);
  },
}));

function makeRuntime() {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

function expectModelRegistryUnavailable(
  runtime: ReturnType<typeof makeRuntime>,
  expectedDetail: string,
) {
  (expect* runtime.error).toHaveBeenCalledTimes(1);
  (expect* runtime.error.mock.calls[0]?.[0]).contains("Model registry unavailable:");
  (expect* runtime.error.mock.calls[0]?.[0]).contains(expectedDetail);
  (expect* runtime.log).not.toHaveBeenCalled();
  (expect* process.exitCode).is(1);
}

beforeEach(() => {
  previousExitCode = process.exitCode;
  process.exitCode = undefined;
  modelRegistryState.getAllError = undefined;
  modelRegistryState.getAvailableError = undefined;
  listProfilesForProvider.mockReturnValue([]);
  ensureOpenClawModelsJson.mockClear();
  readConfigFileSnapshotForWrite.mockClear();
  readConfigFileSnapshotForWrite.mockResolvedValue({
    snapshot: { valid: false, resolved: {} },
    writeOptions: {},
  });
  setRuntimeConfigSnapshot.mockClear();
});

afterEach(() => {
  process.exitCode = previousExitCode;
});

(deftest-group "models list/status", () => {
  const ZAI_MODEL = {
    provider: "zai",
    id: "glm-4.7",
    name: "GLM-4.7",
    input: ["text"],
    baseUrl: "https://api.z.ai/v1",
    contextWindow: 128000,
  };
  const OPENAI_MODEL = {
    provider: "openai",
    id: "gpt-4.1-mini",
    name: "GPT-4.1 mini",
    input: ["text"],
    baseUrl: "https://api.openai.com/v1",
    contextWindow: 128000,
  };
  const GOOGLE_ANTIGRAVITY_TEMPLATE_BASE = {
    provider: "google-antigravity",
    api: "google-gemini-cli",
    input: ["text", "image"],
    baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
    contextWindow: 200000,
    maxTokens: 64000,
    reasoning: true,
    cost: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
  };

  function setDefaultModel(model: string) {
    loadConfig.mockReturnValue({
      agents: { defaults: { model } },
    });
  }

  function configureModelAsConfigured(model: string) {
    loadConfig.mockReturnValue({
      agents: {
        defaults: {
          model,
          models: {
            [model]: {},
          },
        },
      },
    });
  }

  function configureGoogleAntigravityModel(modelId: string) {
    configureModelAsConfigured(`google-antigravity/${modelId}`);
  }

  function makeGoogleAntigravityTemplate(id: string, name: string) {
    return {
      ...GOOGLE_ANTIGRAVITY_TEMPLATE_BASE,
      id,
      name,
    };
  }

  function enableGoogleAntigravityAuthProfile() {
    listProfilesForProvider.mockImplementation((_: unknown, provider: string) =>
      provider === "google-antigravity"
        ? ([{ id: "profile-1" }] as Array<Record<string, unknown>>)
        : [],
    );
  }

  function parseJsonLog(runtime: ReturnType<typeof makeRuntime>) {
    (expect* runtime.log).toHaveBeenCalledTimes(1);
    return JSON.parse(String(runtime.log.mock.calls[0]?.[0]));
  }

  async function expectZaiProviderFilter(provider: string) {
    setDefaultZaiRegistry();
    const runtime = makeRuntime();

    await modelsListCommand({ all: true, provider, json: true }, runtime);

    const payload = parseJsonLog(runtime);
    (expect* payload.count).is(1);
    (expect* payload.models[0]?.key).is("zai/glm-4.7");
  }

  function setDefaultZaiRegistry(params: { available?: boolean } = {}) {
    const available = params.available ?? true;
    setDefaultModel("z.ai/glm-4.7");
    modelRegistryState.models = [ZAI_MODEL, OPENAI_MODEL];
    modelRegistryState.available = available ? [ZAI_MODEL, OPENAI_MODEL] : [];
  }

  beforeAll(async () => {
    ({ modelsListCommand } = await import("./models/list.list-command.js"));
    ({ loadModelRegistry, toModelRow } = await import("./models/list.registry.js"));
  });

  (deftest "models list runs model discovery without auth.json sync", async () => {
    setDefaultZaiRegistry();
    const runtime = makeRuntime();

    await modelsListCommand({ all: true, json: true }, runtime);
    (expect* runtime.error).not.toHaveBeenCalled();
  });

  (deftest "models list outputs canonical zai key for configured z.ai model", async () => {
    setDefaultZaiRegistry();
    const runtime = makeRuntime();

    await modelsListCommand({ json: true }, runtime);

    const payload = parseJsonLog(runtime);
    (expect* payload.models[0]?.key).is("zai/glm-4.7");
  });

  (deftest "models list plain outputs canonical zai key", async () => {
    loadConfig.mockReturnValue({
      agents: { defaults: { model: "z.ai/glm-4.7" } },
    });
    const runtime = makeRuntime();

    modelRegistryState.models = [ZAI_MODEL];
    modelRegistryState.available = [ZAI_MODEL];
    await modelsListCommand({ plain: true }, runtime);

    (expect* runtime.log).toHaveBeenCalledTimes(1);
    (expect* runtime.log.mock.calls[0]?.[0]).is("zai/glm-4.7");
  });

  it.each(["z.ai", "Z.AI", "z-ai"] as const)(
    "models list provider filter normalizes %s alias",
    async (provider) => {
      await expectZaiProviderFilter(provider);
    },
  );

  (deftest "models list marks auth as unavailable when ZAI key is missing", async () => {
    setDefaultZaiRegistry({ available: false });
    const runtime = makeRuntime();

    await modelsListCommand({ all: true, json: true }, runtime);

    const payload = parseJsonLog(runtime);
    (expect* payload.models[0]?.available).is(false);
  });

  (deftest "models list does not treat availability-unavailable code as discovery fallback", async () => {
    configureGoogleAntigravityModel("claude-opus-4-6-thinking");
    modelRegistryState.getAllError = Object.assign(new Error("model discovery failed"), {
      code: "MODEL_AVAILABILITY_UNAVAILABLE",
    });
    const runtime = makeRuntime();
    await modelsListCommand({ json: true }, runtime);

    expectModelRegistryUnavailable(runtime, "model discovery failed");
    (expect* runtime.error.mock.calls[0]?.[0]).not.contains("configured models may appear missing");
  });

  (deftest "models list fails fast when registry model discovery is unavailable", async () => {
    configureGoogleAntigravityModel("claude-opus-4-6-thinking");
    enableGoogleAntigravityAuthProfile();
    modelRegistryState.getAllError = Object.assign(new Error("model discovery unavailable"), {
      code: "MODEL_DISCOVERY_UNAVAILABLE",
    });
    const runtime = makeRuntime();

    modelRegistryState.models = [];
    modelRegistryState.available = [];
    await modelsListCommand({ json: true }, runtime);

    expectModelRegistryUnavailable(runtime, "model discovery unavailable");
  });

  (deftest "loadModelRegistry throws when model discovery is unavailable", async () => {
    modelRegistryState.getAllError = Object.assign(new Error("model discovery unavailable"), {
      code: "MODEL_DISCOVERY_UNAVAILABLE",
    });
    modelRegistryState.available = [
      makeGoogleAntigravityTemplate("claude-opus-4-5-thinking", "Claude Opus 4.5 Thinking"),
    ];

    await (expect* loadModelRegistry({})).rejects.signals-error("model discovery unavailable");
  });

  (deftest "loadModelRegistry persists using source config snapshot when provided", async () => {
    modelRegistryState.models = [OPENAI_MODEL];
    modelRegistryState.available = [OPENAI_MODEL];
    const sourceConfig = {
      models: { providers: { openai: { apiKey: "$OPENAI_API_KEY" } } }, // pragma: allowlist secret
    };
    const resolvedConfig = {
      models: { providers: { openai: { apiKey: "sk-resolved-runtime-value" } } }, // pragma: allowlist secret
    };

    await loadModelRegistry(resolvedConfig as never, { sourceConfig: sourceConfig as never });

    (expect* ensureOpenClawModelsJson).toHaveBeenCalledTimes(1);
    (expect* ensureOpenClawModelsJson).toHaveBeenCalledWith(sourceConfig);
  });

  (deftest "loadModelRegistry uses resolved config when no source snapshot is provided", async () => {
    modelRegistryState.models = [OPENAI_MODEL];
    modelRegistryState.available = [OPENAI_MODEL];
    const resolvedConfig = {
      models: { providers: { openai: { apiKey: "sk-resolved-runtime-value" } } }, // pragma: allowlist secret
    };

    await loadModelRegistry(resolvedConfig as never);

    (expect* ensureOpenClawModelsJson).toHaveBeenCalledTimes(1);
    (expect* ensureOpenClawModelsJson).toHaveBeenCalledWith(resolvedConfig);
  });

  (deftest "toModelRow does not crash without cfg/authStore when availability is undefined", async () => {
    const row = toModelRow({
      model: makeGoogleAntigravityTemplate(
        "claude-opus-4-6-thinking",
        "Claude Opus 4.6 Thinking",
      ) as never,
      key: "google-antigravity/claude-opus-4-6-thinking",
      tags: [],
      availableKeys: undefined,
    });

    (expect* row.missing).is(false);
    (expect* row.available).is(false);
  });
});
