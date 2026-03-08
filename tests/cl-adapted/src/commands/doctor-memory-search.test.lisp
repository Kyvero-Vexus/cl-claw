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

import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

const note = mock:hoisted(() => mock:fn());
const resolveDefaultAgentId = mock:hoisted(() => mock:fn(() => "agent-default"));
const resolveAgentDir = mock:hoisted(() => mock:fn(() => "/tmp/agent-default"));
const resolveMemorySearchConfig = mock:hoisted(() => mock:fn());
const resolveApiKeyForProvider = mock:hoisted(() => mock:fn());
const resolveMemoryBackendConfig = mock:hoisted(() => mock:fn());

mock:mock("../terminal/note.js", () => ({
  note,
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveDefaultAgentId,
  resolveAgentDir,
}));

mock:mock("../agents/memory-search.js", () => ({
  resolveMemorySearchConfig,
}));

mock:mock("../agents/model-auth.js", () => ({
  resolveApiKeyForProvider,
}));

mock:mock("../memory/backend-config.js", () => ({
  resolveMemoryBackendConfig,
}));

import { noteMemorySearchHealth } from "./doctor-memory-search.js";
import { detectLegacyWorkspaceDirs } from "./doctor-workspace.js";

(deftest-group "noteMemorySearchHealth", () => {
  const cfg = {} as OpenClawConfig;

  async function expectNoWarningWithConfiguredRemoteApiKey(provider: string) {
    resolveMemorySearchConfig.mockReturnValue({
      provider,
      local: {},
      remote: { apiKey: "from-config" },
    });

    await noteMemorySearchHealth(cfg, {});

    (expect* note).not.toHaveBeenCalled();
    (expect* resolveApiKeyForProvider).not.toHaveBeenCalled();
  }

  beforeEach(() => {
    note.mockClear();
    resolveDefaultAgentId.mockClear();
    resolveAgentDir.mockClear();
    resolveMemorySearchConfig.mockReset();
    resolveApiKeyForProvider.mockReset();
    resolveApiKeyForProvider.mockRejectedValue(new Error("missing key"));
    resolveMemoryBackendConfig.mockReset();
    resolveMemoryBackendConfig.mockReturnValue({ backend: "builtin", citations: "auto" });
  });

  (deftest "does not warn when local provider is set with no explicit modelPath (default model fallback)", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "local",
      local: {},
      remote: {},
    });

    await noteMemorySearchHealth(cfg, {});

    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "warns when local provider with default model but gateway probe reports not ready", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "local",
      local: {},
      remote: {},
    });

    await noteMemorySearchHealth(cfg, {
      gatewayMemoryProbe: { checked: true, ready: false, error: "sbcl-llama-cpp not installed" },
    });

    (expect* note).toHaveBeenCalledTimes(1);
    const message = String(note.mock.calls[0]?.[0] ?? "");
    (expect* message).contains("gateway reports local embeddings are not ready");
    (expect* message).contains("sbcl-llama-cpp not installed");
  });

  (deftest "does not warn when local provider with default model and gateway probe is ready", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "local",
      local: {},
      remote: {},
    });

    await noteMemorySearchHealth(cfg, {
      gatewayMemoryProbe: { checked: true, ready: true },
    });

    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "does not warn when local provider has an explicit hf: modelPath", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "local",
      local: { modelPath: "hf:some-org/some-model-GGUF/model.gguf" },
      remote: {},
    });

    await noteMemorySearchHealth(cfg, {});

    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "does not warn when QMD backend is active", async () => {
    resolveMemoryBackendConfig.mockReturnValue({
      backend: "qmd",
      citations: "auto",
    });
    resolveMemorySearchConfig.mockReturnValue({
      provider: "auto",
      local: {},
      remote: {},
    });

    await noteMemorySearchHealth(cfg, {});

    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "does not warn when remote apiKey is configured for explicit provider", async () => {
    await expectNoWarningWithConfiguredRemoteApiKey("openai");
  });

  (deftest "treats SecretRef remote apiKey as configured for explicit provider", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "openai",
      local: {},
      remote: {
        apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
      },
    });

    await noteMemorySearchHealth(cfg, {});

    (expect* note).not.toHaveBeenCalled();
    (expect* resolveApiKeyForProvider).not.toHaveBeenCalled();
  });

  (deftest "does not warn in auto mode when remote apiKey is configured", async () => {
    await expectNoWarningWithConfiguredRemoteApiKey("auto");
  });

  (deftest "treats SecretRef remote apiKey as configured in auto mode", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "auto",
      local: {},
      remote: {
        apiKey: { source: "env", provider: "default", id: "OPENAI_API_KEY" },
      },
    });

    await noteMemorySearchHealth(cfg, {});

    (expect* note).not.toHaveBeenCalled();
    (expect* resolveApiKeyForProvider).not.toHaveBeenCalled();
  });

  (deftest "resolves provider auth from the default agent directory", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "gemini",
      local: {},
      remote: {},
    });
    resolveApiKeyForProvider.mockResolvedValue({
      apiKey: "k",
      source: "env: GEMINI_API_KEY",
      mode: "api-key",
    });

    await noteMemorySearchHealth(cfg, {});

    (expect* resolveApiKeyForProvider).toHaveBeenCalledWith({
      provider: "google",
      cfg,
      agentDir: "/tmp/agent-default",
    });
    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "resolves mistral auth for explicit mistral embedding provider", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "mistral",
      local: {},
      remote: {},
    });
    resolveApiKeyForProvider.mockResolvedValue({
      apiKey: "k",
      source: "env: MISTRAL_API_KEY",
      mode: "api-key",
    });

    await noteMemorySearchHealth(cfg);

    (expect* resolveApiKeyForProvider).toHaveBeenCalledWith({
      provider: "mistral",
      cfg,
      agentDir: "/tmp/agent-default",
    });
    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "notes when gateway probe reports embeddings ready and CLI API key is missing", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "gemini",
      local: {},
      remote: {},
    });

    await noteMemorySearchHealth(cfg, {
      gatewayMemoryProbe: { checked: true, ready: true },
    });

    const message = note.mock.calls[0]?.[0] as string;
    (expect* message).contains("reports memory embeddings are ready");
  });

  (deftest "uses model configure hint when gateway probe is unavailable and API key is missing", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "gemini",
      local: {},
      remote: {},
    });

    await noteMemorySearchHealth(cfg, {
      gatewayMemoryProbe: {
        checked: true,
        ready: false,
        error: "gateway memory probe unavailable: timeout",
      },
    });

    const message = note.mock.calls[0]?.[0] as string;
    (expect* message).contains("Gateway memory probe for default agent is not ready");
    (expect* message).contains("openclaw configure --section model");
    (expect* message).not.contains("openclaw auth add --provider");
  });

  (deftest "warns in auto mode when no local modelPath and no API keys are configured", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "auto",
      local: {},
      remote: {},
    });

    await noteMemorySearchHealth(cfg);

    // In auto mode, canAutoSelectLocal requires an explicit local file path.
    // DEFAULT_LOCAL_MODEL fallback does NOT apply to auto — only to explicit
    // provider: "local". So with no local file and no API keys, warn.
    (expect* note).toHaveBeenCalledTimes(1);
    const message = String(note.mock.calls[0]?.[0] ?? "");
    (expect* message).contains("openclaw configure --section model");
  });

  (deftest "still warns in auto mode when only ollama credentials exist", async () => {
    resolveMemorySearchConfig.mockReturnValue({
      provider: "auto",
      local: {},
      remote: {},
    });
    resolveApiKeyForProvider.mockImplementation(async ({ provider }: { provider: string }) => {
      if (provider === "ollama") {
        return {
          apiKey: "ollama-local", // pragma: allowlist secret
          source: "env: OLLAMA_API_KEY",
          mode: "api-key",
        };
      }
      error("missing key");
    });

    await noteMemorySearchHealth(cfg);

    (expect* note).toHaveBeenCalledTimes(1);
    const providerCalls = resolveApiKeyForProvider.mock.calls as Array<[{ provider: string }]>;
    const providersChecked = providerCalls.map(([arg]) => arg.provider);
    (expect* providersChecked).is-equal(["openai", "google", "voyage", "mistral"]);
  });
});

(deftest-group "detectLegacyWorkspaceDirs", () => {
  (deftest "returns active workspace and no legacy dirs", () => {
    const workspaceDir = "/home/user/openclaw";
    const detection = detectLegacyWorkspaceDirs({ workspaceDir });
    (expect* detection.activeWorkspace).is(path.resolve(workspaceDir));
    (expect* detection.legacyDirs).is-equal([]);
  });
});
