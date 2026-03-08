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
import { createWizardPrompter as buildWizardPrompter } from "../../test/helpers/wizard-prompter.js";
import type { RuntimeEnv } from "../runtime.js";

const runTui = mock:hoisted(() => mock:fn(async () => {}));
const probeGatewayReachable = mock:hoisted(() => mock:fn(async () => ({ ok: true })));
const setupOnboardingShellCompletion = mock:hoisted(() => mock:fn(async () => {}));
const buildGatewayInstallPlan = mock:hoisted(() =>
  mock:fn(async () => ({
    programArguments: [],
    workingDirectory: "/tmp",
    environment: {},
  })),
);
const gatewayServiceInstall = mock:hoisted(() => mock:fn(async () => {}));
const resolveGatewayInstallToken = mock:hoisted(() =>
  mock:fn(async () => ({
    token: undefined,
    tokenRefConfigured: true,
    warnings: [],
  })),
);
const isSystemdUserServiceAvailable = mock:hoisted(() => mock:fn(async () => true));

mock:mock("../commands/onboard-helpers.js", () => ({
  detectBrowserOpenSupport: mock:fn(async () => ({ ok: false })),
  formatControlUiSshHint: mock:fn(() => "ssh hint"),
  openUrl: mock:fn(async () => false),
  probeGatewayReachable,
  resolveControlUiLinks: mock:fn(() => ({
    httpUrl: "http://127.0.0.1:18789",
    wsUrl: "ws://127.0.0.1:18789",
  })),
  waitForGatewayReachable: mock:fn(async () => {}),
}));

mock:mock("../commands/daemon-install-helpers.js", () => ({
  buildGatewayInstallPlan,
  gatewayInstallErrorHint: mock:fn(() => "hint"),
}));

mock:mock("../commands/gateway-install-token.js", () => ({
  resolveGatewayInstallToken,
}));

mock:mock("../commands/daemon-runtime.js", () => ({
  DEFAULT_GATEWAY_DAEMON_RUNTIME: "sbcl",
  GATEWAY_DAEMON_RUNTIME_OPTIONS: [{ value: "sbcl", label: "Node" }],
}));

mock:mock("../commands/health-format.js", () => ({
  formatHealthCheckFailure: mock:fn(() => "health failed"),
}));

mock:mock("../commands/health.js", () => ({
  healthCommand: mock:fn(async () => {}),
}));

mock:mock("../daemon/service.js", () => ({
  resolveGatewayService: mock:fn(() => ({
    isLoaded: mock:fn(async () => false),
    restart: mock:fn(async () => {}),
    uninstall: mock:fn(async () => {}),
    install: gatewayServiceInstall,
  })),
}));

mock:mock("../daemon/systemd.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../daemon/systemd.js")>();
  return {
    ...actual,
    isSystemdUserServiceAvailable,
  };
});

mock:mock("../infra/control-ui-assets.js", () => ({
  ensureControlUiAssetsBuilt: mock:fn(async () => ({ ok: true })),
}));

mock:mock("../terminal/restore.js", () => ({
  restoreTerminalState: mock:fn(),
}));

mock:mock("../tui/tui.js", () => ({
  runTui,
}));

mock:mock("./onboarding.completion.js", () => ({
  setupOnboardingShellCompletion,
}));

import { finalizeOnboardingWizard } from "./onboarding.finalize.js";

function createRuntime(): RuntimeEnv {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

function expectFirstOnboardingInstallPlanCallOmitsToken() {
  const [firstArg] =
    (buildGatewayInstallPlan.mock.calls.at(0) as [Record<string, unknown>] | undefined) ?? [];
  (expect* firstArg).toBeDefined();
  (expect* firstArg && "token" in firstArg).is(false);
}

(deftest-group "finalizeOnboardingWizard", () => {
  beforeEach(() => {
    runTui.mockClear();
    probeGatewayReachable.mockClear();
    setupOnboardingShellCompletion.mockClear();
    buildGatewayInstallPlan.mockClear();
    gatewayServiceInstall.mockClear();
    resolveGatewayInstallToken.mockClear();
    isSystemdUserServiceAvailable.mockReset();
    isSystemdUserServiceAvailable.mockResolvedValue(true);
  });

  (deftest "resolves gateway password SecretRef for probe and TUI", async () => {
    const previous = UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = "resolved-gateway-password"; // pragma: allowlist secret
    const select = mock:fn(async (params: { message: string }) => {
      if (params.message === "How do you want to hatch your bot?") {
        return "tui";
      }
      return "later";
    });
    const prompter = buildWizardPrompter({
      select: select as never,
      confirm: mock:fn(async () => false),
    });
    const runtime = createRuntime();

    try {
      await finalizeOnboardingWizard({
        flow: "quickstart",
        opts: {
          acceptRisk: true,
          authChoice: "skip",
          installDaemon: false,
          skipHealth: true,
          skipUi: false,
        },
        baseConfig: {},
        nextConfig: {
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
          tools: {
            web: {
              search: {
                apiKey: "",
              },
            },
          },
        },
        workspaceDir: "/tmp",
        settings: {
          port: 18789,
          bind: "loopback",
          authMode: "password",
          gatewayToken: undefined,
          tailscaleMode: "off",
          tailscaleResetOnExit: false,
        },
        prompter,
        runtime,
      });
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
        password: "resolved-gateway-password", // pragma: allowlist secret
      }),
    );
    (expect* runTui).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "ws://127.0.0.1:18789",
        password: "resolved-gateway-password", // pragma: allowlist secret
      }),
    );
  });

  (deftest "does not persist resolved SecretRef token in daemon install plan", async () => {
    const prompter = buildWizardPrompter({
      select: mock:fn(async () => "later") as never,
      confirm: mock:fn(async () => false),
    });
    const runtime = createRuntime();

    await finalizeOnboardingWizard({
      flow: "advanced",
      opts: {
        acceptRisk: true,
        authChoice: "skip",
        installDaemon: true,
        skipHealth: true,
        skipUi: true,
      },
      baseConfig: {},
      nextConfig: {
        gateway: {
          auth: {
            mode: "token",
            token: {
              source: "env",
              provider: "default",
              id: "OPENCLAW_GATEWAY_TOKEN",
            },
          },
        },
      },
      workspaceDir: "/tmp",
      settings: {
        port: 18789,
        bind: "loopback",
        authMode: "token",
        gatewayToken: "session-token",
        tailscaleMode: "off",
        tailscaleResetOnExit: false,
      },
      prompter,
      runtime,
    });

    (expect* resolveGatewayInstallToken).toHaveBeenCalledTimes(1);
    (expect* buildGatewayInstallPlan).toHaveBeenCalledTimes(1);
    expectFirstOnboardingInstallPlanCallOmitsToken();
    (expect* gatewayServiceInstall).toHaveBeenCalledTimes(1);
  });
});
