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
import { captureFullEnv } from "../../test-utils/env.js";
import type { DaemonActionResponse } from "./response.js";

const loadConfigMock = mock:hoisted(() => mock:fn());
const readConfigFileSnapshotMock = mock:hoisted(() => mock:fn());
const resolveGatewayPortMock = mock:hoisted(() => mock:fn(() => 18789));
const writeConfigFileMock = mock:hoisted(() => mock:fn());
const resolveIsNixModeMock = mock:hoisted(() => mock:fn(() => false));
const resolveSecretInputRefMock = mock:hoisted(() =>
  mock:fn((): { ref: unknown } => ({ ref: undefined })),
);
const resolveGatewayAuthMock = mock:hoisted(() =>
  mock:fn(() => ({
    mode: "token",
    token: undefined,
    password: undefined,
    allowTailscale: false,
  })),
);
const resolveSecretRefValuesMock = mock:hoisted(() => mock:fn());
const randomTokenMock = mock:hoisted(() => mock:fn(() => "generated-token"));
const buildGatewayInstallPlanMock = mock:hoisted(() =>
  mock:fn(async () => ({
    programArguments: ["openclaw", "gateway", "run"],
    workingDirectory: "/tmp",
    environment: {},
  })),
);
const parsePortMock = mock:hoisted(() => mock:fn(() => null));
const isGatewayDaemonRuntimeMock = mock:hoisted(() => mock:fn(() => true));
const installDaemonServiceAndEmitMock = mock:hoisted(() => mock:fn(async () => {}));

const actionState = mock:hoisted(() => ({
  warnings: [] as string[],
  emitted: [] as DaemonActionResponse[],
  failed: [] as Array<{ message: string; hints?: string[] }>,
}));

const service = mock:hoisted(() => ({
  label: "Gateway",
  loadedText: "loaded",
  notLoadedText: "not loaded",
  isLoaded: mock:fn(async () => false),
  install: mock:fn(async () => {}),
  uninstall: mock:fn(async () => {}),
  restart: mock:fn(async () => {}),
  stop: mock:fn(async () => {}),
  readCommand: mock:fn(async () => null),
  readRuntime: mock:fn(async () => ({ status: "stopped" as const })),
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: loadConfigMock,
  readBestEffortConfig: loadConfigMock,
  readConfigFileSnapshot: readConfigFileSnapshotMock,
  resolveGatewayPort: resolveGatewayPortMock,
  writeConfigFile: writeConfigFileMock,
}));

mock:mock("../../config/paths.js", () => ({
  resolveIsNixMode: resolveIsNixModeMock,
}));

mock:mock("../../config/types.secrets.js", () => ({
  resolveSecretInputRef: resolveSecretInputRefMock,
}));

mock:mock("../../gateway/auth.js", () => ({
  resolveGatewayAuth: resolveGatewayAuthMock,
}));

mock:mock("../../secrets/resolve.js", () => ({
  resolveSecretRefValues: resolveSecretRefValuesMock,
}));

mock:mock("../../commands/onboard-helpers.js", () => ({
  randomToken: randomTokenMock,
}));

mock:mock("../../commands/daemon-install-helpers.js", () => ({
  buildGatewayInstallPlan: buildGatewayInstallPlanMock,
}));

mock:mock("./shared.js", () => ({
  parsePort: parsePortMock,
}));

mock:mock("../../commands/daemon-runtime.js", () => ({
  DEFAULT_GATEWAY_DAEMON_RUNTIME: "sbcl",
  isGatewayDaemonRuntime: isGatewayDaemonRuntimeMock,
}));

mock:mock("../../daemon/service.js", () => ({
  resolveGatewayService: () => service,
}));

mock:mock("./response.js", () => ({
  buildDaemonServiceSnapshot: mock:fn(),
  createDaemonActionContext: mock:fn(() => ({
    stdout: process.stdout,
    warnings: actionState.warnings,
    emit: (payload: DaemonActionResponse) => {
      actionState.emitted.push(payload);
    },
    fail: (message: string, hints?: string[]) => {
      actionState.failed.push({ message, hints });
    },
  })),
  installDaemonServiceAndEmit: installDaemonServiceAndEmitMock,
}));

const runtimeLogs: string[] = [];
mock:mock("../../runtime.js", () => ({
  defaultRuntime: {
    log: (message: string) => runtimeLogs.push(message),
    error: mock:fn(),
    exit: mock:fn(),
  },
}));

function expectFirstInstallPlanCallOmitsToken() {
  const [firstArg] =
    (buildGatewayInstallPlanMock.mock.calls.at(0) as [Record<string, unknown>] | undefined) ?? [];
  (expect* firstArg).toBeDefined();
  (expect* firstArg && "token" in firstArg).is(false);
}

const { runDaemonInstall } = await import("./install.js");
const envSnapshot = captureFullEnv();

(deftest-group "runDaemonInstall", () => {
  beforeEach(() => {
    loadConfigMock.mockReset();
    readConfigFileSnapshotMock.mockReset();
    resolveGatewayPortMock.mockClear();
    writeConfigFileMock.mockReset();
    resolveIsNixModeMock.mockReset();
    resolveSecretInputRefMock.mockReset();
    resolveGatewayAuthMock.mockReset();
    resolveSecretRefValuesMock.mockReset();
    randomTokenMock.mockReset();
    buildGatewayInstallPlanMock.mockReset();
    parsePortMock.mockReset();
    isGatewayDaemonRuntimeMock.mockReset();
    installDaemonServiceAndEmitMock.mockReset();
    service.isLoaded.mockReset();
    runtimeLogs.length = 0;
    actionState.warnings.length = 0;
    actionState.emitted.length = 0;
    actionState.failed.length = 0;

    loadConfigMock.mockReturnValue({ gateway: { auth: { mode: "token" } } });
    readConfigFileSnapshotMock.mockResolvedValue({ exists: false, valid: true, config: {} });
    resolveGatewayPortMock.mockReturnValue(18789);
    resolveIsNixModeMock.mockReturnValue(false);
    resolveSecretInputRefMock.mockReturnValue({ ref: undefined });
    resolveGatewayAuthMock.mockReturnValue({
      mode: "token",
      token: undefined,
      password: undefined,
      allowTailscale: false,
    });
    resolveSecretRefValuesMock.mockResolvedValue(new Map());
    randomTokenMock.mockReturnValue("generated-token");
    buildGatewayInstallPlanMock.mockResolvedValue({
      programArguments: ["openclaw", "gateway", "run"],
      workingDirectory: "/tmp",
      environment: {},
    });
    parsePortMock.mockReturnValue(null);
    isGatewayDaemonRuntimeMock.mockReturnValue(true);
    installDaemonServiceAndEmitMock.mockResolvedValue(undefined);
    service.isLoaded.mockResolvedValue(false);
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.CLAWDBOT_GATEWAY_TOKEN;
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  (deftest "fails install when token auth requires an unresolved token SecretRef", async () => {
    resolveSecretInputRefMock.mockReturnValue({
      ref: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
    });
    resolveSecretRefValuesMock.mockRejectedValue(new Error("secret unavailable"));

    await runDaemonInstall({ json: true });

    (expect* actionState.failed[0]?.message).contains("gateway.auth.token SecretRef is configured");
    (expect* actionState.failed[0]?.message).contains("unresolved");
    (expect* buildGatewayInstallPlanMock).not.toHaveBeenCalled();
    (expect* installDaemonServiceAndEmitMock).not.toHaveBeenCalled();
  });

  (deftest "validates token SecretRef but does not serialize resolved token into service env", async () => {
    resolveSecretInputRefMock.mockReturnValue({
      ref: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
    });
    resolveSecretRefValuesMock.mockResolvedValue(
      new Map([["env:default:OPENCLAW_GATEWAY_TOKEN", "resolved-from-secretref"]]),
    );

    await runDaemonInstall({ json: true });

    (expect* actionState.failed).is-equal([]);
    (expect* buildGatewayInstallPlanMock).toHaveBeenCalledTimes(1);
    expectFirstInstallPlanCallOmitsToken();
    (expect* writeConfigFileMock).not.toHaveBeenCalled();
    (expect* 
      actionState.warnings.some((warning) =>
        warning.includes("gateway.auth.token is SecretRef-managed"),
      ),
    ).is(true);
  });

  (deftest "does not treat env-template gateway.auth.token as plaintext during install", async () => {
    loadConfigMock.mockReturnValue({
      gateway: { auth: { mode: "token", token: "${OPENCLAW_GATEWAY_TOKEN}" } },
    });
    resolveSecretInputRefMock.mockReturnValue({
      ref: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
    });
    resolveSecretRefValuesMock.mockResolvedValue(
      new Map([["env:default:OPENCLAW_GATEWAY_TOKEN", "resolved-from-secretref"]]),
    );

    await runDaemonInstall({ json: true });

    (expect* actionState.failed).is-equal([]);
    (expect* resolveSecretRefValuesMock).toHaveBeenCalledTimes(1);
    (expect* buildGatewayInstallPlanMock).toHaveBeenCalledTimes(1);
    expectFirstInstallPlanCallOmitsToken();
  });

  (deftest "auto-mints and persists token when no source exists", async () => {
    randomTokenMock.mockReturnValue("minted-token");
    readConfigFileSnapshotMock.mockResolvedValue({
      exists: true,
      valid: true,
      config: { gateway: { auth: { mode: "token" } } },
    });

    await runDaemonInstall({ json: true });

    (expect* actionState.failed).is-equal([]);
    (expect* writeConfigFileMock).toHaveBeenCalledTimes(1);
    const writtenConfig = writeConfigFileMock.mock.calls[0]?.[0] as {
      gateway?: { auth?: { token?: string } };
    };
    (expect* writtenConfig.gateway?.auth?.token).is("minted-token");
    (expect* buildGatewayInstallPlanMock).toHaveBeenCalledWith(
      expect.objectContaining({ port: 18789 }),
    );
    expectFirstInstallPlanCallOmitsToken();
    (expect* installDaemonServiceAndEmitMock).toHaveBeenCalledTimes(1);
    (expect* actionState.warnings.some((warning) => warning.includes("Auto-generated"))).is(true);
  });

  (deftest "continues Linux install when service probe hits a non-fatal systemd bus failure", async () => {
    service.isLoaded.mockRejectedValueOnce(
      new Error("systemctl is-enabled unavailable: Failed to connect to bus"),
    );

    await runDaemonInstall({ json: true });

    (expect* actionState.failed).is-equal([]);
    (expect* installDaemonServiceAndEmitMock).toHaveBeenCalledTimes(1);
  });

  (deftest "fails install when service probe reports an unrelated error", async () => {
    service.isLoaded.mockRejectedValueOnce(
      new Error("systemctl is-enabled unavailable: read-only file system"),
    );

    await runDaemonInstall({ json: true });

    (expect* actionState.failed[0]?.message).contains("Gateway service check failed");
    (expect* actionState.failed[0]?.message).contains("read-only file system");
    (expect* installDaemonServiceAndEmitMock).not.toHaveBeenCalled();
  });
});
