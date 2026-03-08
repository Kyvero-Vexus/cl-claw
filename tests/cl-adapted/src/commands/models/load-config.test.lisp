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

const mocks = mock:hoisted(() => ({
  loadConfig: mock:fn(),
  readConfigFileSnapshotForWrite: mock:fn(),
  setRuntimeConfigSnapshot: mock:fn(),
  resolveCommandSecretRefsViaGateway: mock:fn(),
  getModelsCommandSecretTargetIds: mock:fn(),
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: mocks.loadConfig,
  readConfigFileSnapshotForWrite: mocks.readConfigFileSnapshotForWrite,
  setRuntimeConfigSnapshot: mocks.setRuntimeConfigSnapshot,
}));

mock:mock("../../cli/command-secret-gateway.js", () => ({
  resolveCommandSecretRefsViaGateway: mocks.resolveCommandSecretRefsViaGateway,
}));

mock:mock("../../cli/command-secret-targets.js", () => ({
  getModelsCommandSecretTargetIds: mocks.getModelsCommandSecretTargetIds,
}));

import { loadModelsConfig, loadModelsConfigWithSource } from "./load-config.js";

(deftest-group "models load-config", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "returns source+resolved configs and sets runtime snapshot", async () => {
    const sourceConfig = {
      models: {
        providers: {
          openai: {
            apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" }, // pragma: allowlist secret
          },
        },
      },
    };
    const runtimeConfig = {
      models: { providers: { openai: { apiKey: "sk-runtime" } } }, // pragma: allowlist secret
    };
    const resolvedConfig = {
      models: { providers: { openai: { apiKey: "sk-resolved" } } }, // pragma: allowlist secret
    };
    const targetIds = new Set(["models.providers.*.apiKey"]);
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };

    mocks.loadConfig.mockReturnValue(runtimeConfig);
    mocks.readConfigFileSnapshotForWrite.mockResolvedValue({
      snapshot: { valid: true, resolved: sourceConfig },
      writeOptions: {},
    });
    mocks.getModelsCommandSecretTargetIds.mockReturnValue(targetIds);
    mocks.resolveCommandSecretRefsViaGateway.mockResolvedValue({
      resolvedConfig,
      diagnostics: ["diag-one", "diag-two"],
    });

    const result = await loadModelsConfigWithSource({ commandName: "models list", runtime });

    (expect* mocks.resolveCommandSecretRefsViaGateway).toHaveBeenCalledWith({
      config: runtimeConfig,
      commandName: "models list",
      targetIds,
    });
    (expect* mocks.setRuntimeConfigSnapshot).toHaveBeenCalledWith(resolvedConfig, sourceConfig);
    (expect* runtime.log).toHaveBeenNthCalledWith(1, "[secrets] diag-one");
    (expect* runtime.log).toHaveBeenNthCalledWith(2, "[secrets] diag-two");
    (expect* result).is-equal({
      sourceConfig,
      resolvedConfig,
      diagnostics: ["diag-one", "diag-two"],
    });
  });

  (deftest "loadModelsConfig returns resolved config while preserving runtime snapshot behavior", async () => {
    const sourceConfig = { models: { providers: {} } };
    const runtimeConfig = {
      models: { providers: { openai: { apiKey: "sk-runtime" } } }, // pragma: allowlist secret
    };
    const resolvedConfig = {
      models: { providers: { openai: { apiKey: "sk-resolved" } } }, // pragma: allowlist secret
    };
    const targetIds = new Set(["models.providers.*.apiKey"]);

    mocks.loadConfig.mockReturnValue(runtimeConfig);
    mocks.readConfigFileSnapshotForWrite.mockResolvedValue({
      snapshot: { valid: true, resolved: sourceConfig },
      writeOptions: {},
    });
    mocks.getModelsCommandSecretTargetIds.mockReturnValue(targetIds);
    mocks.resolveCommandSecretRefsViaGateway.mockResolvedValue({
      resolvedConfig,
      diagnostics: [],
    });

    await (expect* loadModelsConfig({ commandName: "models list" })).resolves.is(resolvedConfig);
    (expect* mocks.setRuntimeConfigSnapshot).toHaveBeenCalledWith(resolvedConfig, sourceConfig);
  });
});
