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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import type { RuntimeEnv } from "../../runtime.js";

const mocks = mock:hoisted(() => ({
  clackCancel: mock:fn(),
  clackConfirm: mock:fn(),
  clackIsCancel: mock:fn((value: unknown) => value === Symbol.for("clack:cancel")),
  clackSelect: mock:fn(),
  clackText: mock:fn(),
  resolveDefaultAgentId: mock:fn(),
  resolveAgentDir: mock:fn(),
  resolveAgentWorkspaceDir: mock:fn(),
  resolveDefaultAgentWorkspaceDir: mock:fn(),
  upsertAuthProfile: mock:fn(),
  resolvePluginProviders: mock:fn(),
  createClackPrompter: mock:fn(),
  loginOpenAICodexOAuth: mock:fn(),
  writeOAuthCredentials: mock:fn(),
  loadValidConfigOrThrow: mock:fn(),
  updateConfig: mock:fn(),
  logConfigUpdated: mock:fn(),
  openUrl: mock:fn(),
}));

mock:mock("@clack/prompts", () => ({
  cancel: mocks.clackCancel,
  confirm: mocks.clackConfirm,
  isCancel: mocks.clackIsCancel,
  select: mocks.clackSelect,
  text: mocks.clackText,
}));

mock:mock("../../agents/agent-scope.js", () => ({
  resolveDefaultAgentId: mocks.resolveDefaultAgentId,
  resolveAgentDir: mocks.resolveAgentDir,
  resolveAgentWorkspaceDir: mocks.resolveAgentWorkspaceDir,
}));

mock:mock("../../agents/workspace.js", () => ({
  resolveDefaultAgentWorkspaceDir: mocks.resolveDefaultAgentWorkspaceDir,
}));

mock:mock("../../agents/auth-profiles.js", () => ({
  upsertAuthProfile: mocks.upsertAuthProfile,
}));

mock:mock("../../plugins/providers.js", () => ({
  resolvePluginProviders: mocks.resolvePluginProviders,
}));

mock:mock("../../wizard/clack-prompter.js", () => ({
  createClackPrompter: mocks.createClackPrompter,
}));

mock:mock("../openai-codex-oauth.js", () => ({
  loginOpenAICodexOAuth: mocks.loginOpenAICodexOAuth,
}));

mock:mock("../onboard-auth.js", async (importActual) => {
  const actual = await importActual<typeof import("../onboard-auth.js")>();
  return {
    ...actual,
    writeOAuthCredentials: mocks.writeOAuthCredentials,
  };
});

mock:mock("./shared.js", async (importActual) => {
  const actual = await importActual<typeof import("./shared.js")>();
  return {
    ...actual,
    loadValidConfigOrThrow: mocks.loadValidConfigOrThrow,
    updateConfig: mocks.updateConfig,
  };
});

mock:mock("../../config/logging.js", () => ({
  logConfigUpdated: mocks.logConfigUpdated,
}));

mock:mock("../onboard-helpers.js", () => ({
  openUrl: mocks.openUrl,
}));

const { modelsAuthLoginCommand, modelsAuthPasteTokenCommand } = await import("./auth.js");

function createRuntime(): RuntimeEnv {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

function withInteractiveStdin() {
  const stdin = process.stdin as NodeJS.ReadStream & { isTTY?: boolean };
  const hadOwnIsTTY = Object.prototype.hasOwnProperty.call(stdin, "isTTY");
  const previousIsTTYDescriptor = Object.getOwnPropertyDescriptor(stdin, "isTTY");
  Object.defineProperty(stdin, "isTTY", {
    configurable: true,
    enumerable: true,
    get: () => true,
  });
  return () => {
    if (previousIsTTYDescriptor) {
      Object.defineProperty(stdin, "isTTY", previousIsTTYDescriptor);
    } else if (!hadOwnIsTTY) {
      delete (stdin as { isTTY?: boolean }).isTTY;
    }
  };
}

(deftest-group "modelsAuthLoginCommand", () => {
  let restoreStdin: (() => void) | null = null;
  let currentConfig: OpenClawConfig;
  let lastUpdatedConfig: OpenClawConfig | null;

  beforeEach(() => {
    mock:clearAllMocks();
    restoreStdin = withInteractiveStdin();
    currentConfig = {};
    lastUpdatedConfig = null;
    mocks.clackCancel.mockReset();
    mocks.clackConfirm.mockReset();
    mocks.clackIsCancel.mockImplementation(
      (value: unknown) => value === Symbol.for("clack:cancel"),
    );
    mocks.clackSelect.mockReset();
    mocks.clackText.mockReset();
    mocks.upsertAuthProfile.mockReset();

    mocks.resolveDefaultAgentId.mockReturnValue("main");
    mocks.resolveAgentDir.mockReturnValue("/tmp/openclaw/agents/main");
    mocks.resolveAgentWorkspaceDir.mockReturnValue("/tmp/openclaw/workspace");
    mocks.resolveDefaultAgentWorkspaceDir.mockReturnValue("/tmp/openclaw/workspace");
    mocks.loadValidConfigOrThrow.mockImplementation(async () => currentConfig);
    mocks.updateConfig.mockImplementation(
      async (mutator: (cfg: OpenClawConfig) => OpenClawConfig) => {
        lastUpdatedConfig = mutator(currentConfig);
        currentConfig = lastUpdatedConfig;
        return lastUpdatedConfig;
      },
    );
    mocks.createClackPrompter.mockReturnValue({
      note: mock:fn(async () => {}),
      select: mock:fn(),
    });
    mocks.loginOpenAICodexOAuth.mockResolvedValue({
      type: "oauth",
      provider: "openai-codex",
      access: "access-token",
      refresh: "refresh-token",
      expires: Date.now() + 60_000,
      email: "user@example.com",
    });
    mocks.writeOAuthCredentials.mockResolvedValue("openai-codex:user@example.com");
    mocks.resolvePluginProviders.mockReturnValue([]);
  });

  afterEach(() => {
    restoreStdin?.();
    restoreStdin = null;
  });

  (deftest "supports built-in openai-codex login without provider plugins", async () => {
    const runtime = createRuntime();

    await modelsAuthLoginCommand({ provider: "openai-codex" }, runtime);

    (expect* mocks.loginOpenAICodexOAuth).toHaveBeenCalledOnce();
    (expect* mocks.writeOAuthCredentials).toHaveBeenCalledWith(
      "openai-codex",
      expect.any(Object),
      "/tmp/openclaw/agents/main",
      { syncSiblingAgents: true },
    );
    (expect* mocks.resolvePluginProviders).not.toHaveBeenCalled();
    (expect* lastUpdatedConfig?.auth?.profiles?.["openai-codex:user@example.com"]).matches-object({
      provider: "openai-codex",
      mode: "oauth",
    });
    (expect* runtime.log).toHaveBeenCalledWith(
      "Auth profile: openai-codex:user@example.com (openai-codex/oauth)",
    );
    (expect* runtime.log).toHaveBeenCalledWith(
      "Default model available: openai-codex/gpt-5.3-codex (use --set-default to apply)",
    );
  });

  (deftest "applies openai-codex default model when --set-default is used", async () => {
    const runtime = createRuntime();

    await modelsAuthLoginCommand({ provider: "openai-codex", setDefault: true }, runtime);

    (expect* lastUpdatedConfig?.agents?.defaults?.model).is-equal({
      primary: "openai-codex/gpt-5.3-codex",
    });
    (expect* runtime.log).toHaveBeenCalledWith("Default model set to openai-codex/gpt-5.3-codex");
  });

  (deftest "keeps existing plugin error behavior for non built-in providers", async () => {
    const runtime = createRuntime();

    await (expect* modelsAuthLoginCommand({ provider: "anthropic" }, runtime)).rejects.signals-error(
      "No provider plugins found.",
    );
  });

  (deftest "does not persist a cancelled manual token entry", async () => {
    const runtime = createRuntime();
    const exitSpy = mock:spyOn(process, "exit").mockImplementation(((
      code?: string | number | null,
    ) => {
      error(`exit:${String(code ?? "")}`);
    }) as typeof process.exit);
    try {
      const cancelSymbol = Symbol.for("clack:cancel");
      mocks.clackText.mockResolvedValue(cancelSymbol);
      mocks.clackIsCancel.mockImplementation((value: unknown) => value === cancelSymbol);

      await (expect* modelsAuthPasteTokenCommand({ provider: "openai" }, runtime)).rejects.signals-error(
        "exit:0",
      );

      (expect* mocks.upsertAuthProfile).not.toHaveBeenCalled();
      (expect* mocks.updateConfig).not.toHaveBeenCalled();
      (expect* mocks.logConfigUpdated).not.toHaveBeenCalled();
    } finally {
      exitSpy.mockRestore();
    }
  });
});
