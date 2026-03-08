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

const mockReadFileSync = mock:hoisted(() => mock:fn());
const mockSpawnSync = mock:hoisted(() => mock:fn());

type RestartHealthSnapshot = {
  healthy: boolean;
  staleGatewayPids: number[];
  runtime: { status?: string };
  portUsage: { port: number; status: string; listeners: []; hints: []; errors?: string[] };
};

type RestartPostCheckContext = {
  json: boolean;
  stdout: NodeJS.WritableStream;
  warnings: string[];
  fail: (message: string, hints?: string[]) => void;
};

type RestartParams = {
  opts?: { json?: boolean };
  postRestartCheck?: (ctx: RestartPostCheckContext) => deferred-result<void>;
};

const service = {
  readCommand: mock:fn(),
  restart: mock:fn(),
};

const runServiceRestart = mock:fn();
const runServiceStop = mock:fn();
const waitForGatewayHealthyListener = mock:fn();
const waitForGatewayHealthyRestart = mock:fn();
const terminateStaleGatewayPids = mock:fn();
const renderGatewayPortHealthDiagnostics = mock:fn(() => ["diag: unhealthy port"]);
const renderRestartDiagnostics = mock:fn(() => ["diag: unhealthy runtime"]);
const resolveGatewayPort = mock:fn(() => 18789);
const findGatewayPidsOnPortSync = mock:fn<(port: number) => number[]>(() => []);
const probeGateway = mock:fn<
  (opts: {
    url: string;
    auth?: { token?: string; password?: string };
    timeoutMs: number;
  }) => deferred-result<{
    ok: boolean;
    configSnapshot: unknown;
  }>
>();
const isRestartEnabled = mock:fn<(config?: { commands?: unknown }) => boolean>(() => true);
const loadConfig = mock:fn(() => ({}));

mock:mock("sbcl:fs", () => ({
  default: {
    readFileSync: (...args: unknown[]) => mockReadFileSync(...args),
  },
}));

mock:mock("sbcl:child_process", () => ({
  spawnSync: (...args: unknown[]) => mockSpawnSync(...args),
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: () => loadConfig(),
  readBestEffortConfig: async () => loadConfig(),
  resolveGatewayPort,
}));

mock:mock("../../infra/restart.js", () => ({
  findGatewayPidsOnPortSync: (port: number) => findGatewayPidsOnPortSync(port),
}));

mock:mock("../../gateway/probe.js", () => ({
  probeGateway: (opts: {
    url: string;
    auth?: { token?: string; password?: string };
    timeoutMs: number;
  }) => probeGateway(opts),
}));

mock:mock("../../config/commands.js", () => ({
  isRestartEnabled: (config?: { commands?: unknown }) => isRestartEnabled(config),
}));

mock:mock("../../daemon/service.js", () => ({
  resolveGatewayService: () => service,
}));

mock:mock("./restart-health.js", () => ({
  DEFAULT_RESTART_HEALTH_ATTEMPTS: 120,
  DEFAULT_RESTART_HEALTH_DELAY_MS: 500,
  waitForGatewayHealthyListener,
  waitForGatewayHealthyRestart,
  renderGatewayPortHealthDiagnostics,
  terminateStaleGatewayPids,
  renderRestartDiagnostics,
}));

mock:mock("./lifecycle-core.js", () => ({
  runServiceRestart,
  runServiceStart: mock:fn(),
  runServiceStop,
  runServiceUninstall: mock:fn(),
}));

(deftest-group "runDaemonRestart health checks", () => {
  let runDaemonRestart: (opts?: { json?: boolean }) => deferred-result<boolean>;
  let runDaemonStop: (opts?: { json?: boolean }) => deferred-result<void>;

  beforeAll(async () => {
    ({ runDaemonRestart, runDaemonStop } = await import("./lifecycle.js"));
  });

  beforeEach(() => {
    service.readCommand.mockReset();
    service.restart.mockReset();
    runServiceRestart.mockReset();
    runServiceStop.mockReset();
    waitForGatewayHealthyListener.mockReset();
    waitForGatewayHealthyRestart.mockReset();
    terminateStaleGatewayPids.mockReset();
    renderGatewayPortHealthDiagnostics.mockReset();
    renderRestartDiagnostics.mockReset();
    resolveGatewayPort.mockReset();
    findGatewayPidsOnPortSync.mockReset();
    probeGateway.mockReset();
    isRestartEnabled.mockReset();
    loadConfig.mockReset();
    mockReadFileSync.mockReset();
    mockSpawnSync.mockReset();

    service.readCommand.mockResolvedValue({
      programArguments: ["openclaw", "gateway", "--port", "18789"],
      environment: {},
    });

    runServiceRestart.mockImplementation(async (params: RestartParams) => {
      const fail = (message: string, hints?: string[]) => {
        const err = new Error(message) as Error & { hints?: string[] };
        err.hints = hints;
        throw err;
      };
      await params.postRestartCheck?.({
        json: Boolean(params.opts?.json),
        stdout: process.stdout,
        warnings: [],
        fail,
      });
      return true;
    });
    runServiceStop.mockResolvedValue(undefined);
    waitForGatewayHealthyListener.mockResolvedValue({
      healthy: true,
      portUsage: { port: 18789, status: "busy", listeners: [], hints: [] },
    });
    probeGateway.mockResolvedValue({
      ok: true,
      configSnapshot: { commands: { restart: true } },
    });
    isRestartEnabled.mockReturnValue(true);
    mockReadFileSync.mockImplementation((path: string) => {
      const match = path.match(/\/proc\/(\d+)\/cmdline$/);
      if (!match) {
        error(`unexpected path ${path}`);
      }
      const pid = Number.parseInt(match[1] ?? "", 10);
      if ([4200, 4300].includes(pid)) {
        return ["openclaw", "gateway", "--port", "18789", ""].join("\0");
      }
      error(`unknown pid ${pid}`);
    });
    mockSpawnSync.mockReturnValue({
      error: null,
      status: 0,
      stdout: "openclaw gateway --port 18789",
      stderr: "",
    });
  });

  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "kills stale gateway pids and retries restart", async () => {
    const unhealthy: RestartHealthSnapshot = {
      healthy: false,
      staleGatewayPids: [1993],
      runtime: { status: "stopped" },
      portUsage: { port: 18789, status: "busy", listeners: [], hints: [] },
    };
    const healthy: RestartHealthSnapshot = {
      healthy: true,
      staleGatewayPids: [],
      runtime: { status: "running" },
      portUsage: { port: 18789, status: "busy", listeners: [], hints: [] },
    };
    waitForGatewayHealthyRestart.mockResolvedValueOnce(unhealthy).mockResolvedValueOnce(healthy);
    terminateStaleGatewayPids.mockResolvedValue([1993]);

    const result = await runDaemonRestart({ json: true });

    (expect* result).is(true);
    (expect* terminateStaleGatewayPids).toHaveBeenCalledWith([1993]);
    (expect* service.restart).toHaveBeenCalledTimes(1);
    (expect* waitForGatewayHealthyRestart).toHaveBeenCalledTimes(2);
  });

  (deftest "fails restart when gateway remains unhealthy", async () => {
    const unhealthy: RestartHealthSnapshot = {
      healthy: false,
      staleGatewayPids: [],
      runtime: { status: "stopped" },
      portUsage: { port: 18789, status: "free", listeners: [], hints: [] },
    };
    waitForGatewayHealthyRestart.mockResolvedValue(unhealthy);

    await (expect* runDaemonRestart({ json: true })).rejects.matches-object({
      message: "Gateway restart timed out after 60s waiting for health checks.",
      hints: ["openclaw gateway status --deep", "openclaw doctor"],
    });
    (expect* terminateStaleGatewayPids).not.toHaveBeenCalled();
    (expect* renderRestartDiagnostics).toHaveBeenCalledTimes(1);
  });

  (deftest "signals an unmanaged gateway process on stop", async () => {
    mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    const killSpy = mock:spyOn(process, "kill").mockImplementation(() => true);
    findGatewayPidsOnPortSync.mockReturnValue([4200, 4200, 4300]);
    mockSpawnSync.mockReturnValue({
      error: null,
      status: 0,
      stdout:
        'CommandLine="C:\\\\Program Files\\\\OpenClaw\\\\openclaw.exe" gateway --port 18789\r\n',
      stderr: "",
    });
    runServiceStop.mockImplementation(async (params: { onNotLoaded?: () => deferred-result<unknown> }) => {
      await params.onNotLoaded?.();
    });

    await runDaemonStop({ json: true });

    (expect* findGatewayPidsOnPortSync).toHaveBeenCalledWith(18789);
    (expect* killSpy).toHaveBeenCalledWith(4200, "SIGTERM");
    (expect* killSpy).toHaveBeenCalledWith(4300, "SIGTERM");
  });

  (deftest "signals a single unmanaged gateway process on restart", async () => {
    mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    const killSpy = mock:spyOn(process, "kill").mockImplementation(() => true);
    findGatewayPidsOnPortSync.mockReturnValue([4200]);
    mockSpawnSync.mockReturnValue({
      error: null,
      status: 0,
      stdout:
        'CommandLine="C:\\\\Program Files\\\\OpenClaw\\\\openclaw.exe" gateway --port 18789\r\n',
      stderr: "",
    });
    runServiceRestart.mockImplementation(
      async (params: RestartParams & { onNotLoaded?: () => deferred-result<unknown> }) => {
        await params.onNotLoaded?.();
        await params.postRestartCheck?.({
          json: Boolean(params.opts?.json),
          stdout: process.stdout,
          warnings: [],
          fail: (message: string) => {
            error(message);
          },
        });
        return true;
      },
    );

    await runDaemonRestart({ json: true });

    (expect* findGatewayPidsOnPortSync).toHaveBeenCalledWith(18789);
    (expect* killSpy).toHaveBeenCalledWith(4200, "SIGUSR1");
    (expect* probeGateway).toHaveBeenCalledTimes(1);
    (expect* waitForGatewayHealthyListener).toHaveBeenCalledTimes(1);
    (expect* waitForGatewayHealthyRestart).not.toHaveBeenCalled();
    (expect* terminateStaleGatewayPids).not.toHaveBeenCalled();
    (expect* service.restart).not.toHaveBeenCalled();
  });

  (deftest "fails unmanaged restart when multiple gateway listeners are present", async () => {
    mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    findGatewayPidsOnPortSync.mockReturnValue([4200, 4300]);
    mockSpawnSync.mockReturnValue({
      error: null,
      status: 0,
      stdout:
        'CommandLine="C:\\\\Program Files\\\\OpenClaw\\\\openclaw.exe" gateway --port 18789\r\n',
      stderr: "",
    });
    runServiceRestart.mockImplementation(
      async (params: RestartParams & { onNotLoaded?: () => deferred-result<unknown> }) => {
        await params.onNotLoaded?.();
        return true;
      },
    );

    await (expect* runDaemonRestart({ json: true })).rejects.signals-error(
      "multiple gateway processes are listening on port 18789",
    );
  });

  (deftest "fails unmanaged restart when the running gateway has commands.restart disabled", async () => {
    findGatewayPidsOnPortSync.mockReturnValue([4200]);
    probeGateway.mockResolvedValue({
      ok: true,
      configSnapshot: { commands: { restart: false } },
    });
    isRestartEnabled.mockReturnValue(false);
    runServiceRestart.mockImplementation(
      async (params: RestartParams & { onNotLoaded?: () => deferred-result<unknown> }) => {
        await params.onNotLoaded?.();
        return true;
      },
    );

    await (expect* runDaemonRestart({ json: true })).rejects.signals-error(
      "Gateway restart is disabled in the running gateway config",
    );
  });

  (deftest "skips unmanaged signaling for pids that are not live gateway processes", async () => {
    const killSpy = mock:spyOn(process, "kill").mockImplementation(() => true);
    findGatewayPidsOnPortSync.mockReturnValue([4200]);
    mockReadFileSync.mockReturnValue(["python", "-m", "http.server", ""].join("\0"));
    mockSpawnSync.mockReturnValue({
      error: null,
      status: 0,
      stdout: "python -m http.server",
      stderr: "",
    });
    runServiceStop.mockImplementation(async (params: { onNotLoaded?: () => deferred-result<unknown> }) => {
      await params.onNotLoaded?.();
    });

    await runDaemonStop({ json: true });

    (expect* killSpy).not.toHaveBeenCalled();
  });
});
