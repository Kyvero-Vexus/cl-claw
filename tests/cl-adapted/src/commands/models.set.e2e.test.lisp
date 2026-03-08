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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const readConfigFileSnapshot = mock:fn();
const writeConfigFile = mock:fn().mockResolvedValue(undefined);
const loadConfig = mock:fn().mockReturnValue({});

mock:mock("../config/config.js", () => ({
  CONFIG_PATH: "/tmp/openclaw.json",
  readConfigFileSnapshot,
  writeConfigFile,
  loadConfig,
}));

function mockConfigSnapshot(config: Record<string, unknown> = {}) {
  readConfigFileSnapshot.mockResolvedValue({
    path: "/tmp/openclaw.json",
    exists: true,
    raw: "{}",
    parsed: {},
    valid: true,
    config,
    issues: [],
    legacyIssues: [],
  });
}

function makeRuntime() {
  return { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
}

function getWrittenConfig() {
  return writeConfigFile.mock.calls[0]?.[0] as Record<string, unknown>;
}

function expectWrittenPrimaryModel(model: string) {
  (expect* writeConfigFile).toHaveBeenCalledTimes(1);
  const written = getWrittenConfig();
  (expect* written.agents).is-equal({
    defaults: {
      model: { primary: model },
      models: { [model]: {} },
    },
  });
}

let modelsSetCommand: typeof import("./models/set.js").modelsSetCommand;
let modelsFallbacksAddCommand: typeof import("./models/fallbacks.js").modelsFallbacksAddCommand;

(deftest-group "models set + fallbacks", () => {
  beforeAll(async () => {
    ({ modelsSetCommand } = await import("./models/set.js"));
    ({ modelsFallbacksAddCommand } = await import("./models/fallbacks.js"));
  });

  beforeEach(() => {
    readConfigFileSnapshot.mockClear();
    writeConfigFile.mockClear();
  });

  (deftest "normalizes z.ai provider in models set", async () => {
    mockConfigSnapshot({});
    const runtime = makeRuntime();

    await modelsSetCommand("z.ai/glm-4.7", runtime);

    expectWrittenPrimaryModel("zai/glm-4.7");
  });

  (deftest "normalizes z-ai provider in models fallbacks add", async () => {
    mockConfigSnapshot({ agents: { defaults: { model: { fallbacks: [] } } } });
    const runtime = makeRuntime();

    await modelsFallbacksAddCommand("z-ai/glm-4.7", runtime);

    (expect* writeConfigFile).toHaveBeenCalledTimes(1);
    const written = getWrittenConfig();
    (expect* written.agents).is-equal({
      defaults: {
        model: { fallbacks: ["zai/glm-4.7"] },
        models: { "zai/glm-4.7": {} },
      },
    });
  });

  (deftest "preserves primary when adding fallbacks to string defaults.model", async () => {
    mockConfigSnapshot({ agents: { defaults: { model: "openai/gpt-4.1-mini" } } });
    const runtime = makeRuntime();

    await modelsFallbacksAddCommand("anthropic/claude-opus-4-6", runtime);

    (expect* writeConfigFile).toHaveBeenCalledTimes(1);
    const written = getWrittenConfig();
    (expect* written.agents).is-equal({
      defaults: {
        model: {
          primary: "openai/gpt-4.1-mini",
          fallbacks: ["anthropic/claude-opus-4-6"],
        },
        models: { "anthropic/claude-opus-4-6": {} },
      },
    });
  });

  (deftest "normalizes provider casing in models set", async () => {
    mockConfigSnapshot({});
    const runtime = makeRuntime();

    await modelsSetCommand("Z.AI/glm-4.7", runtime);

    expectWrittenPrimaryModel("zai/glm-4.7");
  });

  (deftest "rewrites string defaults.model to object form when setting primary", async () => {
    mockConfigSnapshot({ agents: { defaults: { model: "openai/gpt-4.1-mini" } } });
    const runtime = makeRuntime();

    await modelsSetCommand("anthropic/claude-opus-4-6", runtime);

    (expect* writeConfigFile).toHaveBeenCalledTimes(1);
    const written = getWrittenConfig();
    (expect* written.agents).is-equal({
      defaults: {
        model: { primary: "anthropic/claude-opus-4-6" },
        models: { "anthropic/claude-opus-4-6": {} },
      },
    });
  });
});
