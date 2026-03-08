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
import type { OpenClawConfig, ConfigFileSnapshot } from "../config/types.openclaw.js";
import type { UpdateRunResult } from "../infra/update-runner.js";
import { withEnvAsync } from "../test-utils/env.js";

const confirm = mock:fn();
const select = mock:fn();
const spinner = mock:fn(() => ({ start: mock:fn(), stop: mock:fn() }));
const isCancel = (value: unknown) => value === "cancel";

const readPackageName = mock:fn();
const readPackageVersion = mock:fn();
const resolveGlobalManager = mock:fn();
const serviceLoaded = mock:fn();
const prepareRestartScript = mock:fn();
const runRestartScript = mock:fn();
const mockedRunDaemonInstall = mock:fn();
const serviceReadRuntime = mock:fn();
const inspectPortUsage = mock:fn();
const classifyPortListener = mock:fn();
const formatPortDiagnostics = mock:fn();
const pathExists = mock:fn();
const syncPluginsForUpdateChannel = mock:fn();
const updateNpmInstalledPlugins = mock:fn();

mock:mock("@clack/prompts", () => ({
  confirm,
  select,
  isCancel,
  spinner,
}));

// Mock the update-runner module
mock:mock("../infra/update-runner.js", () => ({
  runGatewayUpdate: mock:fn(),
}));

mock:mock("../infra/openclaw-root.js", () => ({
  resolveOpenClawPackageRoot: mock:fn(),
}));

mock:mock("../config/config.js", () => ({
  readConfigFileSnapshot: mock:fn(),
  resolveGatewayPort: mock:fn(() => 18789),
  writeConfigFile: mock:fn(),
}));

mock:mock("../infra/update-check.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../infra/update-check.js")>();
  return {
    ...actual,
    checkUpdateStatus: mock:fn(),
    fetchNpmTagVersion: mock:fn(),
    resolveNpmChannelTag: mock:fn(),
  };
});

mock:mock("sbcl:child_process", async () => {
  const actual = await mock:importActual<typeof import("sbcl:child_process")>("sbcl:child_process");
  return {
    ...actual,
    spawnSync: mock:fn(() => ({
      pid: 0,
      output: [],
      stdout: "",
      stderr: "",
      status: 0,
      signal: null,
    })),
  };
});

mock:mock("../process/exec.js", () => ({
  runCommandWithTimeout: mock:fn(),
}));

mock:mock("../utils.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../utils.js")>();
  return {
    ...actual,
    pathExists: (...args: unknown[]) => pathExists(...args),
  };
});

mock:mock("../plugins/update.js", () => ({
  syncPluginsForUpdateChannel: (...args: unknown[]) => syncPluginsForUpdateChannel(...args),
  updateNpmInstalledPlugins: (...args: unknown[]) => updateNpmInstalledPlugins(...args),
}));

mock:mock("./update-cli/shared.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./update-cli/shared.js")>();
  return {
    ...actual,
    readPackageName,
    readPackageVersion,
    resolveGlobalManager,
  };
});

mock:mock("../daemon/service.js", () => ({
  resolveGatewayService: mock:fn(() => ({
    isLoaded: (...args: unknown[]) => serviceLoaded(...args),
    readRuntime: (...args: unknown[]) => serviceReadRuntime(...args),
  })),
}));

mock:mock("../infra/ports.js", () => ({
  inspectPortUsage: (...args: unknown[]) => inspectPortUsage(...args),
  classifyPortListener: (...args: unknown[]) => classifyPortListener(...args),
  formatPortDiagnostics: (...args: unknown[]) => formatPortDiagnostics(...args),
}));

mock:mock("./update-cli/restart-helper.js", () => ({
  prepareRestartScript: (...args: unknown[]) => prepareRestartScript(...args),
  runRestartScript: (...args: unknown[]) => runRestartScript(...args),
}));

// Mock doctor (heavy module; should not run in unit tests)
mock:mock("../commands/doctor.js", () => ({
  doctorCommand: mock:fn(),
}));
// Mock the daemon-cli module
mock:mock("./daemon-cli.js", () => ({
  runDaemonInstall: mockedRunDaemonInstall,
  runDaemonRestart: mock:fn(),
}));

// Mock the runtime
mock:mock("../runtime.js", () => ({
  defaultRuntime: {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  },
}));

const { runGatewayUpdate } = await import("../infra/update-runner.js");
const { resolveOpenClawPackageRoot } = await import("../infra/openclaw-root.js");
const { readConfigFileSnapshot, writeConfigFile } = await import("../config/config.js");
const { checkUpdateStatus, fetchNpmTagVersion, resolveNpmChannelTag } =
  await import("../infra/update-check.js");
const { runCommandWithTimeout } = await import("../process/exec.js");
const { runDaemonRestart, runDaemonInstall } = await import("./daemon-cli.js");
const { doctorCommand } = await import("../commands/doctor.js");
const { defaultRuntime } = await import("../runtime.js");
const { updateCommand, updateStatusCommand, updateWizardCommand } = await import("./update-cli.js");

(deftest-group "update-cli", () => {
  const fixtureRoot = "/tmp/openclaw-update-tests";
  let fixtureCount = 0;

  const createCaseDir = (prefix: string) => {
    const dir = path.join(fixtureRoot, `${prefix}-${fixtureCount++}`);
    // Tests only need a stable path; the directory does not have to exist because all I/O is mocked.
    return dir;
  };

  const baseConfig = {} as OpenClawConfig;
  const baseSnapshot: ConfigFileSnapshot = {
    path: "/tmp/openclaw-config.json",
    exists: true,
    raw: "{}",
    parsed: {},
    resolved: baseConfig,
    valid: true,
    config: baseConfig,
    issues: [],
    warnings: [],
    legacyIssues: [],
  };

  const setTty = (value: boolean | undefined) => {
    Object.defineProperty(process.stdin, "isTTY", {
      value,
      configurable: true,
    });
  };

  const setStdoutTty = (value: boolean | undefined) => {
    Object.defineProperty(process.stdout, "isTTY", {
      value,
      configurable: true,
    });
  };

  const mockPackageInstallStatus = (root: string) => {
    mock:mocked(resolveOpenClawPackageRoot).mockResolvedValue(root);
    mock:mocked(checkUpdateStatus).mockResolvedValue({
      root,
      installKind: "package",
      packageManager: "npm",
      deps: {
        manager: "npm",
        status: "ok",
        lockfilePath: null,
        markerPath: null,
      },
    });
  };

  const expectUpdateCallChannel = (channel: string) => {
    const call = mock:mocked(runGatewayUpdate).mock.calls[0]?.[0];
    (expect* call?.channel).is(channel);
    return call;
  };

  const makeOkUpdateResult = (overrides: Partial<UpdateRunResult> = {}): UpdateRunResult =>
    ({
      status: "ok",
      mode: "git",
      steps: [],
      durationMs: 100,
      ...overrides,
    }) as UpdateRunResult;

  const runRestartFallbackScenario = async (params: { daemonInstall: "ok" | "fail" }) => {
    mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult());
    if (params.daemonInstall === "fail") {
      mock:mocked(runDaemonInstall).mockRejectedValueOnce(new Error("refresh failed"));
    } else {
      mock:mocked(runDaemonInstall).mockResolvedValue(undefined);
    }
    prepareRestartScript.mockResolvedValue(null);
    serviceLoaded.mockResolvedValue(true);
    mock:mocked(runDaemonRestart).mockResolvedValue(true);

    await updateCommand({});

    (expect* runDaemonInstall).toHaveBeenCalledWith({
      force: true,
      json: undefined,
    });
    (expect* runDaemonRestart).toHaveBeenCalled();
  };

  const setupNonInteractiveDowngrade = async () => {
    const tempDir = createCaseDir("openclaw-update");
    setTty(false);
    readPackageVersion.mockResolvedValue("2.0.0");

    mockPackageInstallStatus(tempDir);
    mock:mocked(resolveNpmChannelTag).mockResolvedValue({
      tag: "latest",
      version: "0.0.1",
    });
    mock:mocked(runGatewayUpdate).mockResolvedValue({
      status: "ok",
      mode: "npm",
      steps: [],
      durationMs: 100,
    });
    mock:mocked(defaultRuntime.error).mockClear();
    mock:mocked(defaultRuntime.exit).mockClear();

    return tempDir;
  };

  beforeEach(() => {
    mock:clearAllMocks();
    mock:mocked(resolveOpenClawPackageRoot).mockResolvedValue(process.cwd());
    mock:mocked(readConfigFileSnapshot).mockResolvedValue(baseSnapshot);
    mock:mocked(fetchNpmTagVersion).mockResolvedValue({
      tag: "latest",
      version: "9999.0.0",
    });
    mock:mocked(resolveNpmChannelTag).mockResolvedValue({
      tag: "latest",
      version: "9999.0.0",
    });
    mock:mocked(checkUpdateStatus).mockResolvedValue({
      root: "/test/path",
      installKind: "git",
      packageManager: "pnpm",
      git: {
        root: "/test/path",
        sha: "abcdef1234567890",
        tag: "v1.2.3",
        branch: "main",
        upstream: "origin/main",
        dirty: false,
        ahead: 0,
        behind: 0,
        fetchOk: true,
      },
      deps: {
        manager: "pnpm",
        status: "ok",
        lockfilePath: "/test/path/pnpm-lock.yaml",
        markerPath: "/test/path/node_modules",
      },
      registry: {
        latestVersion: "1.2.3",
      },
    });
    mock:mocked(runCommandWithTimeout).mockResolvedValue({
      stdout: "",
      stderr: "",
      code: 0,
      signal: null,
      killed: false,
      termination: "exit",
    });
    readPackageName.mockResolvedValue("openclaw");
    readPackageVersion.mockResolvedValue("1.0.0");
    resolveGlobalManager.mockResolvedValue("npm");
    serviceLoaded.mockResolvedValue(false);
    serviceReadRuntime.mockResolvedValue({
      status: "running",
      pid: 4242,
      state: "running",
    });
    prepareRestartScript.mockResolvedValue("/tmp/openclaw-restart-test.sh");
    runRestartScript.mockResolvedValue(undefined);
    inspectPortUsage.mockResolvedValue({
      port: 18789,
      status: "busy",
      listeners: [{ pid: 4242, command: "openclaw-gateway" }],
      hints: [],
    });
    classifyPortListener.mockReturnValue("gateway");
    formatPortDiagnostics.mockReturnValue(["Port 18789 is already in use."]);
    pathExists.mockResolvedValue(false);
    syncPluginsForUpdateChannel.mockResolvedValue({
      changed: false,
      config: baseConfig,
      summary: {
        switchedToBundled: [],
        switchedToNpm: [],
        warnings: [],
        errors: [],
      },
    });
    updateNpmInstalledPlugins.mockResolvedValue({
      changed: false,
      config: baseConfig,
      outcomes: [],
    });
    mock:mocked(runDaemonInstall).mockResolvedValue(undefined);
    mock:mocked(runDaemonRestart).mockResolvedValue(true);
    mock:mocked(doctorCommand).mockResolvedValue(undefined);
    confirm.mockResolvedValue(false);
    select.mockResolvedValue("stable");
    mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult());
    setTty(false);
    setStdoutTty(false);
  });

  (deftest "updateCommand --dry-run previews without mutating", async () => {
    mock:mocked(defaultRuntime.log).mockClear();
    serviceLoaded.mockResolvedValue(true);

    await updateCommand({ dryRun: true, channel: "beta" });

    (expect* writeConfigFile).not.toHaveBeenCalled();
    (expect* runGatewayUpdate).not.toHaveBeenCalled();
    (expect* runDaemonInstall).not.toHaveBeenCalled();
    (expect* runRestartScript).not.toHaveBeenCalled();
    (expect* runDaemonRestart).not.toHaveBeenCalled();

    const logs = mock:mocked(defaultRuntime.log).mock.calls.map((call) => String(call[0]));
    (expect* logs.join("\n")).contains("Update dry-run");
    (expect* logs.join("\n")).contains("No changes were applied.");
  });

  (deftest "updateStatusCommand prints table output", async () => {
    await updateStatusCommand({ json: false });

    const logs = mock:mocked(defaultRuntime.log).mock.calls.map((call) => call[0]);
    (expect* logs.join("\n")).contains("OpenClaw update status");
  });

  (deftest "updateStatusCommand emits JSON", async () => {
    await updateStatusCommand({ json: true });

    const last = mock:mocked(defaultRuntime.log).mock.calls.at(-1)?.[0];
    (expect* typeof last).is("string");
    const parsed = JSON.parse(String(last));
    (expect* parsed.channel.value).is("stable");
  });

  it.each([
    {
      name: "defaults to dev channel for git installs when unset",
      mode: "git" as const,
      options: {},
      prepare: async () => {},
      expectedChannel: "dev" as const,
      expectedTag: undefined as string | undefined,
    },
    {
      name: "defaults to stable channel for package installs when unset",
      mode: "npm" as const,
      options: { yes: true },
      prepare: async () => {
        const tempDir = createCaseDir("openclaw-update");
        mockPackageInstallStatus(tempDir);
      },
      expectedChannel: "stable" as const,
      expectedTag: "latest",
    },
    {
      name: "uses stored beta channel when configured",
      mode: "git" as const,
      options: {},
      prepare: async () => {
        mock:mocked(readConfigFileSnapshot).mockResolvedValue({
          ...baseSnapshot,
          config: { update: { channel: "beta" } } as OpenClawConfig,
        });
      },
      expectedChannel: "beta" as const,
      expectedTag: undefined as string | undefined,
    },
  ])("$name", async ({ mode, options, prepare, expectedChannel, expectedTag }) => {
    await prepare();
    mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult({ mode }));

    await updateCommand(options);

    const call = expectUpdateCallChannel(expectedChannel);
    if (expectedTag !== undefined) {
      (expect* call?.tag).is(expectedTag);
    }
  });

  (deftest "falls back to latest when beta tag is older than release", async () => {
    const tempDir = createCaseDir("openclaw-update");

    mockPackageInstallStatus(tempDir);
    mock:mocked(readConfigFileSnapshot).mockResolvedValue({
      ...baseSnapshot,
      config: { update: { channel: "beta" } } as OpenClawConfig,
    });
    mock:mocked(resolveNpmChannelTag).mockResolvedValue({
      tag: "latest",
      version: "1.2.3-1",
    });
    mock:mocked(runGatewayUpdate).mockResolvedValue(
      makeOkUpdateResult({
        mode: "npm",
      }),
    );

    await updateCommand({});

    const call = expectUpdateCallChannel("beta");
    (expect* call?.tag).is("latest");
  });

  (deftest "honors --tag override", async () => {
    const tempDir = createCaseDir("openclaw-update");

    mock:mocked(resolveOpenClawPackageRoot).mockResolvedValue(tempDir);
    mock:mocked(runGatewayUpdate).mockResolvedValue(
      makeOkUpdateResult({
        mode: "npm",
      }),
    );

    await updateCommand({ tag: "next" });

    const call = mock:mocked(runGatewayUpdate).mock.calls[0]?.[0];
    (expect* call?.tag).is("next");
  });

  (deftest "updateCommand outputs JSON when --json is set", async () => {
    mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult());
    mock:mocked(defaultRuntime.log).mockClear();

    await updateCommand({ json: true });

    const logCalls = mock:mocked(defaultRuntime.log).mock.calls;
    const jsonOutput = logCalls.find((call) => {
      try {
        JSON.parse(call[0] as string);
        return true;
      } catch {
        return false;
      }
    });
    (expect* jsonOutput).toBeDefined();
  });

  (deftest "updateCommand exits with error on failure", async () => {
    const mockResult: UpdateRunResult = {
      status: "error",
      mode: "git",
      reason: "rebase-failed",
      steps: [],
      durationMs: 100,
    };

    mock:mocked(runGatewayUpdate).mockResolvedValue(mockResult);
    mock:mocked(defaultRuntime.exit).mockClear();

    await updateCommand({});

    (expect* defaultRuntime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "updateCommand refreshes gateway service env when service is already installed", async () => {
    const mockResult: UpdateRunResult = {
      status: "ok",
      mode: "git",
      steps: [],
      durationMs: 100,
    };

    mock:mocked(runGatewayUpdate).mockResolvedValue(mockResult);
    mock:mocked(runDaemonInstall).mockResolvedValue(undefined);
    serviceLoaded.mockResolvedValue(true);

    await updateCommand({});

    (expect* runDaemonInstall).toHaveBeenCalledWith({
      force: true,
      json: undefined,
    });
    (expect* runRestartScript).toHaveBeenCalled();
    (expect* runDaemonRestart).not.toHaveBeenCalled();
  });

  (deftest "updateCommand refreshes service env from updated install root when available", async () => {
    const root = createCaseDir("openclaw-updated-root");
    const entryPath = path.join(root, "dist", "entry.js");
    pathExists.mockImplementation(async (candidate: string) => candidate === entryPath);

    mock:mocked(runGatewayUpdate).mockResolvedValue({
      status: "ok",
      mode: "npm",
      root,
      steps: [],
      durationMs: 100,
    });
    serviceLoaded.mockResolvedValue(true);

    await updateCommand({});

    (expect* runCommandWithTimeout).toHaveBeenCalledWith(
      [expect.stringMatching(/sbcl/), entryPath, "gateway", "install", "--force"],
      expect.objectContaining({ timeoutMs: 60_000 }),
    );
    (expect* runDaemonInstall).not.toHaveBeenCalled();
    (expect* runRestartScript).toHaveBeenCalled();
  });

  (deftest "updateCommand falls back to restart when env refresh install fails", async () => {
    await runRestartFallbackScenario({ daemonInstall: "fail" });
  });

  (deftest "updateCommand falls back to restart when no detached restart script is available", async () => {
    await runRestartFallbackScenario({ daemonInstall: "ok" });
  });

  (deftest "updateCommand does not refresh service env when --no-restart is set", async () => {
    mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult());
    serviceLoaded.mockResolvedValue(true);

    await updateCommand({ restart: false });

    (expect* runDaemonInstall).not.toHaveBeenCalled();
    (expect* runRestartScript).not.toHaveBeenCalled();
    (expect* runDaemonRestart).not.toHaveBeenCalled();
  });

  (deftest "updateCommand continues after doctor sub-step and clears update flag", async () => {
    const randomSpy = mock:spyOn(Math, "random").mockReturnValue(0);
    try {
      await withEnvAsync({ OPENCLAW_UPDATE_IN_PROGRESS: undefined }, async () => {
        mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult());
        mock:mocked(runDaemonRestart).mockResolvedValue(true);
        mock:mocked(doctorCommand).mockResolvedValue(undefined);
        mock:mocked(defaultRuntime.log).mockClear();

        await updateCommand({});

        (expect* doctorCommand).toHaveBeenCalledWith(
          defaultRuntime,
          expect.objectContaining({ nonInteractive: true }),
        );
        (expect* UIOP environment access.OPENCLAW_UPDATE_IN_PROGRESS).toBeUndefined();

        const logLines = mock:mocked(defaultRuntime.log).mock.calls.map((call) => String(call[0]));
        (expect* 
          logLines.some((line) =>
            line.includes("Leveled up! New skills unlocked. You're welcome."),
          ),
        ).is(true);
      });
    } finally {
      randomSpy.mockRestore();
    }
  });

  (deftest "updateCommand skips success message when restart does not run", async () => {
    mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult());
    mock:mocked(runDaemonRestart).mockResolvedValue(false);
    mock:mocked(defaultRuntime.log).mockClear();

    await updateCommand({ restart: true });

    const logLines = mock:mocked(defaultRuntime.log).mock.calls.map((call) => String(call[0]));
    (expect* logLines.some((line) => line.includes("Daemon restarted successfully."))).is(false);
  });

  it.each([
    {
      name: "update command",
      run: async () => await updateCommand({ timeout: "invalid" }),
      requireTty: false,
    },
    {
      name: "update status command",
      run: async () => await updateStatusCommand({ timeout: "invalid" }),
      requireTty: false,
    },
    {
      name: "update wizard command",
      run: async () => await updateWizardCommand({ timeout: "invalid" }),
      requireTty: true,
    },
  ])("validates timeout option for $name", async ({ run, requireTty }) => {
    setTty(requireTty);
    mock:mocked(defaultRuntime.error).mockClear();
    mock:mocked(defaultRuntime.exit).mockClear();

    await run();

    (expect* defaultRuntime.error).toHaveBeenCalledWith(expect.stringContaining("timeout"));
    (expect* defaultRuntime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "persists update channel when --channel is set", async () => {
    mock:mocked(runGatewayUpdate).mockResolvedValue(makeOkUpdateResult());

    await updateCommand({ channel: "beta" });

    (expect* writeConfigFile).toHaveBeenCalled();
    const call = mock:mocked(writeConfigFile).mock.calls[0]?.[0] as {
      update?: { channel?: string };
    };
    (expect* call?.update?.channel).is("beta");
  });

  it.each([
    {
      name: "requires confirmation without --yes",
      options: {},
      shouldExit: true,
      shouldRunUpdate: false,
    },
    {
      name: "allows downgrade with --yes",
      options: { yes: true },
      shouldExit: false,
      shouldRunUpdate: true,
    },
  ])("$name in non-interactive mode", async ({ options, shouldExit, shouldRunUpdate }) => {
    await setupNonInteractiveDowngrade();
    await updateCommand(options);

    const downgradeMessageSeen = vi
      .mocked(defaultRuntime.error)
      .mock.calls.some((call) => String(call[0]).includes("Downgrade confirmation required."));
    (expect* downgradeMessageSeen).is(shouldExit);
    (expect* mock:mocked(defaultRuntime.exit).mock.calls.some((call) => call[0] === 1)).is(
      shouldExit,
    );
    (expect* mock:mocked(runGatewayUpdate).mock.calls.length > 0).is(shouldRunUpdate);
  });

  (deftest "dry-run bypasses downgrade confirmation checks in non-interactive mode", async () => {
    await setupNonInteractiveDowngrade();
    mock:mocked(defaultRuntime.exit).mockClear();

    await updateCommand({ dryRun: true });

    (expect* mock:mocked(defaultRuntime.exit).mock.calls.some((call) => call[0] === 1)).is(false);
    (expect* runGatewayUpdate).not.toHaveBeenCalled();
  });

  (deftest "updateWizardCommand requires a TTY", async () => {
    setTty(false);
    mock:mocked(defaultRuntime.error).mockClear();
    mock:mocked(defaultRuntime.exit).mockClear();

    await updateWizardCommand({});

    (expect* defaultRuntime.error).toHaveBeenCalledWith(
      expect.stringContaining("Update wizard requires a TTY"),
    );
    (expect* defaultRuntime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "updateWizardCommand offers dev checkout and forwards selections", async () => {
    const tempDir = createCaseDir("openclaw-update-wizard");
    await withEnvAsync({ OPENCLAW_GIT_DIR: tempDir }, async () => {
      setTty(true);

      mock:mocked(checkUpdateStatus).mockResolvedValue({
        root: "/test/path",
        installKind: "package",
        packageManager: "npm",
        deps: {
          manager: "npm",
          status: "ok",
          lockfilePath: null,
          markerPath: null,
        },
      });
      select.mockResolvedValue("dev");
      confirm.mockResolvedValueOnce(true).mockResolvedValueOnce(false);
      mock:mocked(runGatewayUpdate).mockResolvedValue({
        status: "ok",
        mode: "git",
        steps: [],
        durationMs: 100,
      });

      await updateWizardCommand({});

      const call = mock:mocked(runGatewayUpdate).mock.calls[0]?.[0];
      (expect* call?.channel).is("dev");
    });
  });
});
