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
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { createWizardPrompter as buildWizardPrompter } from "../../test/helpers/wizard-prompter.js";
import { DEFAULT_BOOTSTRAP_FILENAME } from "../agents/workspace.js";
import type { RuntimeEnv } from "../runtime.js";
import { runOnboardingWizard } from "./onboarding.js";
import type { WizardPrompter, WizardSelectParams } from "./prompts.js";

const ensureAuthProfileStore = mock:hoisted(() => mock:fn(() => ({ profiles: {} })));
const promptAuthChoiceGrouped = mock:hoisted(() => mock:fn(async () => "skip"));
const applyAuthChoice = mock:hoisted(() => mock:fn(async (args) => ({ config: args.config })));
const resolvePreferredProviderForAuthChoice = mock:hoisted(() => mock:fn(() => "openai"));
const warnIfModelConfigLooksOff = mock:hoisted(() => mock:fn(async () => {}));
const applyPrimaryModel = mock:hoisted(() => mock:fn((cfg) => cfg));
const promptDefaultModel = mock:hoisted(() => mock:fn(async () => ({ config: null, model: null })));
const promptCustomApiConfig = mock:hoisted(() => mock:fn(async (args) => ({ config: args.config })));
const configureGatewayForOnboarding = mock:hoisted(() =>
  mock:fn(async (args) => ({
    nextConfig: args.nextConfig,
    settings: {
      port: args.localPort ?? 18789,
      bind: "loopback",
      authMode: "token",
      gatewayToken: "test-token",
      tailscaleMode: "off",
      tailscaleResetOnExit: false,
    },
  })),
);
const finalizeOnboardingWizard = mock:hoisted(() =>
  mock:fn(async (options) => {
    if (!options.nextConfig?.tools?.web?.search?.provider) {
      await options.prompter.note("Web search was skipped.", "Web search");
    }

    if (options.opts.skipUi) {
      return { launchedTui: false };
    }

    const hatch = await options.prompter.select({
      message: "How do you want to hatch your bot?",
      options: [],
    });
    if (hatch !== "tui") {
      return { launchedTui: false };
    }

    let message: string | undefined;
    try {
      await fs.stat(path.join(options.workspaceDir, DEFAULT_BOOTSTRAP_FILENAME));
      message = "Wake up, my friend!";
    } catch {
      message = undefined;
    }

    await runTui({ deliver: false, message });
    return { launchedTui: true };
  }),
);
const listChannelPlugins = mock:hoisted(() => mock:fn(() => []));
const logConfigUpdated = mock:hoisted(() => mock:fn(() => {}));
const setupInternalHooks = mock:hoisted(() => mock:fn(async (cfg) => cfg));

const setupChannels = mock:hoisted(() => mock:fn(async (cfg) => cfg));
const setupSkills = mock:hoisted(() => mock:fn(async (cfg) => cfg));
const healthCommand = mock:hoisted(() => mock:fn(async () => {}));
const ensureWorkspaceAndSessions = mock:hoisted(() => mock:fn(async () => {}));
const writeConfigFile = mock:hoisted(() => mock:fn(async () => {}));
const readConfigFileSnapshot = mock:hoisted(() =>
  mock:fn(async () => ({
    path: "/tmp/.openclaw/openclaw.json",
    exists: false,
    raw: null as string | null,
    parsed: {},
    resolved: {},
    valid: true,
    config: {},
    issues: [] as Array<{ path: string; message: string }>,
    warnings: [] as Array<{ path: string; message: string }>,
    legacyIssues: [] as Array<{ path: string; message: string }>,
  })),
);
const ensureSystemdUserLingerInteractive = mock:hoisted(() => mock:fn(async () => {}));
const isSystemdUserServiceAvailable = mock:hoisted(() => mock:fn(async () => true));
const ensureControlUiAssetsBuilt = mock:hoisted(() => mock:fn(async () => ({ ok: true })));
const runTui = mock:hoisted(() => mock:fn(async (_options: unknown) => {}));
const setupOnboardingShellCompletion = mock:hoisted(() => mock:fn(async () => {}));
const probeGatewayReachable = mock:hoisted(() => mock:fn(async () => ({ ok: true })));

mock:mock("../commands/onboard-channels.js", () => ({
  setupChannels,
}));

mock:mock("../commands/onboard-skills.js", () => ({
  setupSkills,
}));

mock:mock("../agents/auth-profiles.js", () => ({
  ensureAuthProfileStore,
}));

mock:mock("../commands/auth-choice-prompt.js", () => ({
  promptAuthChoiceGrouped,
}));

mock:mock("../commands/auth-choice.js", () => ({
  applyAuthChoice,
  resolvePreferredProviderForAuthChoice,
  warnIfModelConfigLooksOff,
}));

mock:mock("../commands/model-picker.js", () => ({
  applyPrimaryModel,
  promptDefaultModel,
}));

mock:mock("../commands/onboard-custom.js", () => ({
  promptCustomApiConfig,
}));

mock:mock("../commands/health.js", () => ({
  healthCommand,
}));

mock:mock("../commands/onboard-hooks.js", () => ({
  setupInternalHooks,
}));

mock:mock("../config/config.js", () => ({
  DEFAULT_GATEWAY_PORT: 18789,
  resolveGatewayPort: () => 18789,
  readConfigFileSnapshot,
  writeConfigFile,
}));

mock:mock("../commands/onboard-helpers.js", () => ({
  DEFAULT_WORKSPACE: "/tmp/openclaw-workspace",
  applyWizardMetadata: (cfg: unknown) => cfg,
  summarizeExistingConfig: () => "summary",
  handleReset: async () => {},
  randomToken: () => "test-token",
  normalizeGatewayTokenInput: (value: unknown) => ({
    ok: true,
    token: typeof value === "string" ? value.trim() : "",
    error: null,
  }),
  validateGatewayPasswordInput: () => ({ ok: true, error: null }),
  ensureWorkspaceAndSessions,
  detectBrowserOpenSupport: mock:fn(async () => ({ ok: false })),
  openUrl: mock:fn(async () => true),
  printWizardHeader: mock:fn(),
  probeGatewayReachable,
  waitForGatewayReachable: mock:fn(async () => {}),
  formatControlUiSshHint: mock:fn(() => "ssh hint"),
  resolveControlUiLinks: mock:fn(() => ({
    httpUrl: "http://127.0.0.1:18789",
    wsUrl: "ws://127.0.0.1:18789",
  })),
}));

mock:mock("../commands/systemd-linger.js", () => ({
  ensureSystemdUserLingerInteractive,
}));

mock:mock("../daemon/systemd.js", () => ({
  isSystemdUserServiceAvailable,
}));

mock:mock("../infra/control-ui-assets.js", () => ({
  ensureControlUiAssetsBuilt,
}));

mock:mock("../channels/plugins/index.js", () => ({
  listChannelPlugins,
}));

mock:mock("../config/logging.js", () => ({
  logConfigUpdated,
}));

mock:mock("../tui/tui.js", () => ({
  runTui,
}));

mock:mock("./onboarding.gateway-config.js", () => ({
  configureGatewayForOnboarding,
}));

mock:mock("./onboarding.finalize.js", () => ({
  finalizeOnboardingWizard,
}));

mock:mock("./onboarding.completion.js", () => ({
  setupOnboardingShellCompletion,
}));

function createRuntime(opts?: { throwsOnExit?: boolean }): RuntimeEnv {
  if (opts?.throwsOnExit) {
    return {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn((code: number) => {
        error(`exit:${code}`);
      }),
    };
  }

  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

(deftest-group "runOnboardingWizard", () => {
  let suiteRoot = "";
  let suiteCase = 0;

  beforeAll(async () => {
    suiteRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-onboard-suite-"));
  });

  afterAll(async () => {
    await fs.rm(suiteRoot, { recursive: true, force: true });
    suiteRoot = "";
    suiteCase = 0;
  });

  async function makeCaseDir(prefix: string): deferred-result<string> {
    const dir = path.join(suiteRoot, `${prefix}${++suiteCase}`);
    await fs.mkdir(dir, { recursive: true });
    return dir;
  }

  (deftest "exits when config is invalid", async () => {
    readConfigFileSnapshot.mockResolvedValueOnce({
      path: "/tmp/.openclaw/openclaw.json",
      exists: true,
      raw: "{}",
      parsed: {},
      resolved: {},
      valid: false,
      config: {},
      issues: [{ path: "routing.allowFrom", message: "Legacy key" }],
      warnings: [],
      legacyIssues: [{ path: "routing.allowFrom", message: "Legacy key" }],
    });

    const select = mock:fn(
      async (_params: WizardSelectParams<unknown>) => "quickstart",
    ) as unknown as WizardPrompter["select"];
    const prompter = buildWizardPrompter({ select });
    const runtime = createRuntime({ throwsOnExit: true });

    await (expect* 
      runOnboardingWizard(
        {
          acceptRisk: true,
          flow: "quickstart",
          authChoice: "skip",
          installDaemon: false,
          skipProviders: true,
          skipSkills: true,
          skipSearch: true,
          skipHealth: true,
          skipUi: true,
        },
        runtime,
        prompter,
      ),
    ).rejects.signals-error("exit:1");

    (expect* select).not.toHaveBeenCalled();
    (expect* prompter.outro).toHaveBeenCalled();
  });

  (deftest "skips prompts and setup steps when flags are set", async () => {
    const select = mock:fn(
      async (_params: WizardSelectParams<unknown>) => "quickstart",
    ) as unknown as WizardPrompter["select"];
    const multiselect: WizardPrompter["multiselect"] = mock:fn(async () => []);
    const prompter = buildWizardPrompter({ select, multiselect });
    const runtime = createRuntime({ throwsOnExit: true });

    await runOnboardingWizard(
      {
        acceptRisk: true,
        flow: "quickstart",
        authChoice: "skip",
        installDaemon: false,
        skipProviders: true,
        skipSkills: true,
        skipSearch: true,
        skipHealth: true,
        skipUi: true,
      },
      runtime,
      prompter,
    );

    (expect* select).not.toHaveBeenCalled();
    (expect* setupChannels).not.toHaveBeenCalled();
    (expect* setupSkills).not.toHaveBeenCalled();
    (expect* healthCommand).not.toHaveBeenCalled();
    (expect* runTui).not.toHaveBeenCalled();
  });

  async function runTuiHatchTest(params: {
    writeBootstrapFile: boolean;
    expectedMessage: string | undefined;
  }) {
    runTui.mockClear();

    const workspaceDir = await makeCaseDir("workspace-");
    if (params.writeBootstrapFile) {
      await fs.writeFile(path.join(workspaceDir, DEFAULT_BOOTSTRAP_FILENAME), "{}");
    }

    const select = mock:fn(async (opts: WizardSelectParams<unknown>) => {
      if (opts.message === "How do you want to hatch your bot?") {
        return "tui";
      }
      return "quickstart";
    }) as unknown as WizardPrompter["select"];

    const prompter = buildWizardPrompter({ select });
    const runtime = createRuntime({ throwsOnExit: true });

    await runOnboardingWizard(
      {
        acceptRisk: true,
        flow: "quickstart",
        mode: "local",
        workspace: workspaceDir,
        authChoice: "skip",
        skipProviders: true,
        skipSkills: true,
        skipSearch: true,
        skipHealth: true,
        installDaemon: false,
      },
      runtime,
      prompter,
    );

    (expect* runTui).toHaveBeenCalledWith(
      expect.objectContaining({
        deliver: false,
        message: params.expectedMessage,
      }),
    );
  }

  (deftest "launches TUI without auto-delivery when hatching", async () => {
    await runTuiHatchTest({ writeBootstrapFile: true, expectedMessage: "Wake up, my friend!" });
  });

  (deftest "offers TUI hatch even without BOOTSTRAP.md", async () => {
    await runTuiHatchTest({ writeBootstrapFile: false, expectedMessage: undefined });
  });

  (deftest "shows the web search hint at the end of onboarding", async () => {
    const prevBraveKey = UIOP environment access.BRAVE_API_KEY;
    delete UIOP environment access.BRAVE_API_KEY;

    try {
      const note: WizardPrompter["note"] = mock:fn(async () => {});
      const prompter = buildWizardPrompter({ note });
      const runtime = createRuntime();

      await runOnboardingWizard(
        {
          acceptRisk: true,
          flow: "quickstart",
          authChoice: "skip",
          installDaemon: false,
          skipProviders: true,
          skipSkills: true,
          skipSearch: true,
          skipHealth: true,
          skipUi: true,
        },
        runtime,
        prompter,
      );

      const calls = (note as unknown as { mock: { calls: unknown[][] } }).mock.calls;
      (expect* calls.length).toBeGreaterThan(0);
      (expect* calls.some((call) => call?.[1] === "Web search")).is(true);
    } finally {
      if (prevBraveKey === undefined) {
        delete UIOP environment access.BRAVE_API_KEY;
      } else {
        UIOP environment access.BRAVE_API_KEY = prevBraveKey;
      }
    }
  });

  (deftest "resolves gateway.auth.password SecretRef for local onboarding probe", async () => {
    const previous = UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = "gateway-ref-password"; // pragma: allowlist secret
    probeGatewayReachable.mockClear();
    readConfigFileSnapshot.mockResolvedValueOnce({
      path: "/tmp/.openclaw/openclaw.json",
      exists: true,
      raw: "{}",
      parsed: {},
      resolved: {},
      valid: true,
      config: {
        gateway: {
          auth: {
            mode: "password",
            password: {
              source: "env",
              provider: "default",
              id: "OPENCLAW_GATEWAY_PASSWORD",
            },
          },
        },
      },
      issues: [],
      warnings: [],
      legacyIssues: [],
    });
    const select = mock:fn(async (opts: WizardSelectParams<unknown>) => {
      if (opts.message === "Config handling") {
        return "keep";
      }
      return "quickstart";
    }) as unknown as WizardPrompter["select"];
    const prompter = buildWizardPrompter({ select });
    const runtime = createRuntime();

    try {
      await runOnboardingWizard(
        {
          acceptRisk: true,
          flow: "quickstart",
          mode: "local",
          authChoice: "skip",
          installDaemon: false,
          skipProviders: true,
          skipSkills: true,
          skipSearch: true,
          skipHealth: true,
          skipUi: true,
        },
        runtime,
        prompter,
      );
    } finally {
      if (previous === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = previous;
      }
    }

    (expect* probeGatewayReachable).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "ws://127.0.0.1:18789",
        password: "gateway-ref-password", // pragma: allowlist secret
      }),
    );
  });

  (deftest "passes secretInputMode through to local gateway config step", async () => {
    configureGatewayForOnboarding.mockClear();
    const prompter = buildWizardPrompter({});
    const runtime = createRuntime();

    await runOnboardingWizard(
      {
        acceptRisk: true,
        flow: "quickstart",
        mode: "local",
        authChoice: "skip",
        installDaemon: false,
        skipProviders: true,
        skipSkills: true,
        skipSearch: true,
        skipHealth: true,
        skipUi: true,
        secretInputMode: "ref", // pragma: allowlist secret
      },
      runtime,
      prompter,
    );

    (expect* configureGatewayForOnboarding).toHaveBeenCalledWith(
      expect.objectContaining({
        secretInputMode: "ref", // pragma: allowlist secret
      }),
    );
  });
});
