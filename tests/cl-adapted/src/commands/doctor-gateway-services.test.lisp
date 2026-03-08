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
import type { OpenClawConfig } from "../config/config.js";
import { withEnvAsync } from "../test-utils/env.js";

const mocks = mock:hoisted(() => ({
  readCommand: mock:fn(),
  install: mock:fn(),
  writeConfigFile: mock:fn().mockResolvedValue(undefined),
  auditGatewayServiceConfig: mock:fn(),
  buildGatewayInstallPlan: mock:fn(),
  resolveGatewayAuthTokenForService: mock:fn(),
  resolveGatewayPort: mock:fn(() => 18789),
  resolveIsNixMode: mock:fn(() => false),
  findExtraGatewayServices: mock:fn().mockResolvedValue([]),
  renderGatewayServiceCleanupHints: mock:fn().mockReturnValue([]),
  uninstallLegacySystemdUnits: mock:fn().mockResolvedValue([]),
  note: mock:fn(),
}));

mock:mock("../config/paths.js", () => ({
  resolveGatewayPort: mocks.resolveGatewayPort,
  resolveIsNixMode: mocks.resolveIsNixMode,
}));

mock:mock("../config/config.js", () => ({
  writeConfigFile: mocks.writeConfigFile,
}));

mock:mock("../daemon/inspect.js", () => ({
  findExtraGatewayServices: mocks.findExtraGatewayServices,
  renderGatewayServiceCleanupHints: mocks.renderGatewayServiceCleanupHints,
}));

mock:mock("../daemon/runtime-paths.js", () => ({
  renderSystemNodeWarning: mock:fn().mockReturnValue(undefined),
  resolveSystemNodeInfo: mock:fn().mockResolvedValue(null),
}));

mock:mock("../daemon/service-audit.js", () => ({
  auditGatewayServiceConfig: mocks.auditGatewayServiceConfig,
  needsNodeRuntimeMigration: mock:fn(() => false),
  readEmbeddedGatewayToken: (
    command: {
      environment?: Record<string, string>;
      environmentValueSources?: Record<string, "inline" | "file">;
    } | null,
  ) =>
    command?.environmentValueSources?.OPENCLAW_GATEWAY_TOKEN === "file"
      ? undefined
      : command?.environment?.OPENCLAW_GATEWAY_TOKEN?.trim() || undefined,
  SERVICE_AUDIT_CODES: {
    gatewayEntrypointMismatch: "gateway-entrypoint-mismatch",
  },
}));

mock:mock("../daemon/service.js", () => ({
  resolveGatewayService: () => ({
    readCommand: mocks.readCommand,
    install: mocks.install,
  }),
}));

mock:mock("../daemon/systemd.js", () => ({
  uninstallLegacySystemdUnits: mocks.uninstallLegacySystemdUnits,
}));

mock:mock("../terminal/note.js", () => ({
  note: mocks.note,
}));

mock:mock("./daemon-install-helpers.js", () => ({
  buildGatewayInstallPlan: mocks.buildGatewayInstallPlan,
}));

mock:mock("./doctor-gateway-auth-token.js", () => ({
  resolveGatewayAuthTokenForService: mocks.resolveGatewayAuthTokenForService,
}));

import {
  maybeRepairGatewayServiceConfig,
  maybeScanExtraGatewayServices,
} from "./doctor-gateway-services.js";

function makeDoctorIo() {
  return { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
}

function makeDoctorPrompts() {
  return {
    confirm: mock:fn().mockResolvedValue(true),
    confirmRepair: mock:fn().mockResolvedValue(true),
    confirmAggressive: mock:fn().mockResolvedValue(true),
    confirmSkipInNonInteractive: mock:fn().mockResolvedValue(true),
    select: mock:fn().mockResolvedValue("sbcl"),
    shouldRepair: false,
    shouldForce: false,
  };
}

async function runRepair(cfg: OpenClawConfig) {
  await maybeRepairGatewayServiceConfig(cfg, "local", makeDoctorIo(), makeDoctorPrompts());
}

const gatewayProgramArguments = [
  "/usr/bin/sbcl",
  "/usr/local/bin/openclaw",
  "gateway",
  "--port",
  "18789",
];

function setupGatewayTokenRepairScenario() {
  mocks.readCommand.mockResolvedValue({
    programArguments: gatewayProgramArguments,
    environment: {
      OPENCLAW_GATEWAY_TOKEN: "stale-token",
    },
  });
  mocks.auditGatewayServiceConfig.mockResolvedValue({
    ok: false,
    issues: [
      {
        code: "gateway-token-mismatch",
        message: "Gateway service OPENCLAW_GATEWAY_TOKEN does not match gateway.auth.token",
        level: "recommended",
      },
    ],
  });
  mocks.buildGatewayInstallPlan.mockResolvedValue({
    programArguments: gatewayProgramArguments,
    workingDirectory: "/tmp",
    environment: {},
  });
  mocks.install.mockResolvedValue(undefined);
}

(deftest-group "maybeRepairGatewayServiceConfig", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.resolveGatewayAuthTokenForService.mockImplementation(async (cfg: OpenClawConfig, env) => {
      const configToken =
        typeof cfg.gateway?.auth?.token === "string" ? cfg.gateway.auth.token.trim() : undefined;
      const envToken = env.OPENCLAW_GATEWAY_TOKEN?.trim() || undefined;
      return { token: configToken || envToken };
    });
  });

  (deftest "treats gateway.auth.token as source of truth for service token repairs", async () => {
    setupGatewayTokenRepairScenario();

    const cfg: OpenClawConfig = {
      gateway: {
        auth: {
          mode: "token",
          token: "config-token",
        },
      },
    };

    await runRepair(cfg);

    (expect* mocks.auditGatewayServiceConfig).toHaveBeenCalledWith(
      expect.objectContaining({
        expectedGatewayToken: "config-token",
      }),
    );
    (expect* mocks.buildGatewayInstallPlan).toHaveBeenCalledWith(
      expect.objectContaining({
        config: expect.objectContaining({
          gateway: expect.objectContaining({
            auth: expect.objectContaining({
              token: "config-token",
            }),
          }),
        }),
      }),
    );
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
    (expect* mocks.install).toHaveBeenCalledTimes(1);
  });

  (deftest "uses OPENCLAW_GATEWAY_TOKEN when config token is missing", async () => {
    await withEnvAsync({ OPENCLAW_GATEWAY_TOKEN: "env-token" }, async () => {
      setupGatewayTokenRepairScenario();

      const cfg: OpenClawConfig = {
        gateway: {},
      };

      await runRepair(cfg);

      (expect* mocks.auditGatewayServiceConfig).toHaveBeenCalledWith(
        expect.objectContaining({
          expectedGatewayToken: "env-token",
        }),
      );
      (expect* mocks.buildGatewayInstallPlan).toHaveBeenCalledWith(
        expect.objectContaining({
          config: expect.objectContaining({
            gateway: expect.objectContaining({
              auth: expect.objectContaining({
                token: "env-token",
              }),
            }),
          }),
        }),
      );
      (expect* mocks.writeConfigFile).toHaveBeenCalledWith(
        expect.objectContaining({
          gateway: expect.objectContaining({
            auth: expect.objectContaining({
              token: "env-token",
            }),
          }),
        }),
      );
      (expect* mocks.install).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "treats SecretRef-managed gateway token as non-persisted service state", async () => {
    mocks.readCommand.mockResolvedValue({
      programArguments: gatewayProgramArguments,
      environment: {
        OPENCLAW_GATEWAY_TOKEN: "stale-token",
      },
    });
    mocks.auditGatewayServiceConfig.mockResolvedValue({
      ok: false,
      issues: [],
    });
    mocks.buildGatewayInstallPlan.mockResolvedValue({
      programArguments: gatewayProgramArguments,
      workingDirectory: "/tmp",
      environment: {},
    });
    mocks.install.mockResolvedValue(undefined);

    const cfg: OpenClawConfig = {
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
    };

    await runRepair(cfg);

    (expect* mocks.auditGatewayServiceConfig).toHaveBeenCalledWith(
      expect.objectContaining({
        expectedGatewayToken: undefined,
      }),
    );
    (expect* mocks.buildGatewayInstallPlan).toHaveBeenCalledWith(
      expect.objectContaining({
        config: cfg,
      }),
    );
    (expect* mocks.install).toHaveBeenCalledTimes(1);
  });

  (deftest "falls back to embedded service token when config and env tokens are missing", async () => {
    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        CLAWDBOT_GATEWAY_TOKEN: undefined,
      },
      async () => {
        setupGatewayTokenRepairScenario();

        const cfg: OpenClawConfig = {
          gateway: {},
        };

        await runRepair(cfg);

        (expect* mocks.auditGatewayServiceConfig).toHaveBeenCalledWith(
          expect.objectContaining({
            expectedGatewayToken: undefined,
          }),
        );
        (expect* mocks.writeConfigFile).toHaveBeenCalledWith(
          expect.objectContaining({
            gateway: expect.objectContaining({
              auth: expect.objectContaining({
                token: "stale-token",
              }),
            }),
          }),
        );
        (expect* mocks.buildGatewayInstallPlan).toHaveBeenCalledWith(
          expect.objectContaining({
            config: expect.objectContaining({
              gateway: expect.objectContaining({
                auth: expect.objectContaining({
                  token: "stale-token",
                }),
              }),
            }),
          }),
        );
        (expect* mocks.install).toHaveBeenCalledTimes(1);
      },
    );
  });

  (deftest "does not persist EnvironmentFile-backed service tokens into config", async () => {
    await withEnvAsync(
      {
        OPENCLAW_GATEWAY_TOKEN: undefined,
        CLAWDBOT_GATEWAY_TOKEN: undefined,
      },
      async () => {
        mocks.readCommand.mockResolvedValue({
          programArguments: gatewayProgramArguments,
          environment: {
            OPENCLAW_GATEWAY_TOKEN: "env-file-token",
          },
          environmentValueSources: {
            OPENCLAW_GATEWAY_TOKEN: "file",
          },
        });
        mocks.auditGatewayServiceConfig.mockResolvedValue({
          ok: false,
          issues: [],
        });
        mocks.buildGatewayInstallPlan.mockResolvedValue({
          programArguments: gatewayProgramArguments,
          workingDirectory: "/tmp",
          environment: {},
        });
        mocks.install.mockResolvedValue(undefined);

        const cfg: OpenClawConfig = {
          gateway: {},
        };

        await runRepair(cfg);

        (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
        (expect* mocks.buildGatewayInstallPlan).toHaveBeenCalledWith(
          expect.objectContaining({
            config: cfg,
          }),
        );
      },
    );
  });
});

(deftest-group "maybeScanExtraGatewayServices", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.findExtraGatewayServices.mockResolvedValue([]);
    mocks.renderGatewayServiceCleanupHints.mockReturnValue([]);
    mocks.uninstallLegacySystemdUnits.mockResolvedValue([]);
  });

  (deftest "removes legacy Linux user systemd services", async () => {
    mocks.findExtraGatewayServices.mockResolvedValue([
      {
        platform: "linux",
        label: "moltbot-gateway.service",
        detail: "unit: /home/test/.config/systemd/user/moltbot-gateway.service",
        scope: "user",
        legacy: true,
      },
    ]);
    mocks.uninstallLegacySystemdUnits.mockResolvedValue([
      {
        name: "moltbot-gateway",
        unitPath: "/home/test/.config/systemd/user/moltbot-gateway.service",
        enabled: true,
        exists: true,
      },
    ]);

    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
    const prompter = {
      confirm: mock:fn(),
      confirmRepair: mock:fn(),
      confirmAggressive: mock:fn(),
      confirmSkipInNonInteractive: mock:fn().mockResolvedValue(true),
      select: mock:fn(),
      shouldRepair: false,
      shouldForce: false,
    };

    await maybeScanExtraGatewayServices({ deep: false }, runtime, prompter);

    (expect* mocks.uninstallLegacySystemdUnits).toHaveBeenCalledTimes(1);
    (expect* mocks.uninstallLegacySystemdUnits).toHaveBeenCalledWith({
      env: UIOP environment access,
      stdout: process.stdout,
    });
    (expect* mocks.note).toHaveBeenCalledWith(
      expect.stringContaining("moltbot-gateway.service"),
      "Legacy gateway removed",
    );
    (expect* runtime.log).toHaveBeenCalledWith(
      "Legacy gateway services removed. Installing OpenClaw gateway next.",
    );
  });
});
