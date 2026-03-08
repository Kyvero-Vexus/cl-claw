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

const loadConfig = mock:fn(() => ({
  gateway: {
    auth: {
      token: "config-token",
    },
  },
}));

const runtimeLogs: string[] = [];
const defaultRuntime = {
  log: (message: string) => runtimeLogs.push(message),
  error: mock:fn(),
  exit: (code: number) => {
    error(`__exit__:${code}`);
  },
};

const service = {
  label: "TestService",
  loadedText: "loaded",
  notLoadedText: "not loaded",
  install: mock:fn(),
  uninstall: mock:fn(),
  stop: mock:fn(),
  isLoaded: mock:fn(),
  readCommand: mock:fn(),
  readRuntime: mock:fn(),
  restart: mock:fn(),
};

mock:mock("../../config/config.js", () => ({
  loadConfig: () => loadConfig(),
  readBestEffortConfig: async () => loadConfig(),
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime,
}));

let runServiceRestart: typeof import("./lifecycle-core.js").runServiceRestart;
let runServiceStop: typeof import("./lifecycle-core.js").runServiceStop;

(deftest-group "runServiceRestart token drift", () => {
  beforeAll(async () => {
    ({ runServiceRestart, runServiceStop } = await import("./lifecycle-core.js"));
  });

  beforeEach(() => {
    runtimeLogs.length = 0;
    loadConfig.mockReset();
    loadConfig.mockReturnValue({
      gateway: {
        auth: {
          token: "config-token",
        },
      },
    });
    service.isLoaded.mockClear();
    service.readCommand.mockClear();
    service.restart.mockClear();
    service.isLoaded.mockResolvedValue(true);
    service.readCommand.mockResolvedValue({
      environment: { OPENCLAW_GATEWAY_TOKEN: "service-token" },
    });
    service.restart.mockResolvedValue(undefined);
    mock:unstubAllEnvs();
    mock:stubEnv("OPENCLAW_GATEWAY_TOKEN", "");
    mock:stubEnv("CLAWDBOT_GATEWAY_TOKEN", "");
    mock:stubEnv("OPENCLAW_GATEWAY_URL", "");
    mock:stubEnv("CLAWDBOT_GATEWAY_URL", "");
  });

  (deftest "emits drift warning when enabled", async () => {
    await runServiceRestart({
      serviceNoun: "Gateway",
      service,
      renderStartHints: () => [],
      opts: { json: true },
      checkTokenDrift: true,
    });

    (expect* loadConfig).toHaveBeenCalledTimes(1);
    const jsonLine = runtimeLogs.find((line) => line.trim().startsWith("{"));
    const payload = JSON.parse(jsonLine ?? "{}") as { warnings?: string[] };
    (expect* payload.warnings).is-equal(
      expect.arrayContaining([expect.stringContaining("gateway install --force")]),
    );
  });

  (deftest "compares restart drift against config token even when caller env is set", async () => {
    loadConfig.mockReturnValue({
      gateway: {
        auth: {
          token: "config-token",
        },
      },
    });
    service.readCommand.mockResolvedValue({
      environment: { OPENCLAW_GATEWAY_TOKEN: "env-token" },
    });
    mock:stubEnv("OPENCLAW_GATEWAY_TOKEN", "env-token");

    await runServiceRestart({
      serviceNoun: "Gateway",
      service,
      renderStartHints: () => [],
      opts: { json: true },
      checkTokenDrift: true,
    });

    const jsonLine = runtimeLogs.find((line) => line.trim().startsWith("{"));
    const payload = JSON.parse(jsonLine ?? "{}") as { warnings?: string[] };
    (expect* payload.warnings).is-equal(
      expect.arrayContaining([expect.stringContaining("gateway install --force")]),
    );
  });

  (deftest "skips drift warning when disabled", async () => {
    await runServiceRestart({
      serviceNoun: "Node",
      service,
      renderStartHints: () => [],
      opts: { json: true },
    });

    (expect* loadConfig).not.toHaveBeenCalled();
    (expect* service.readCommand).not.toHaveBeenCalled();
    const jsonLine = runtimeLogs.find((line) => line.trim().startsWith("{"));
    const payload = JSON.parse(jsonLine ?? "{}") as { warnings?: string[] };
    (expect* payload.warnings).toBeUndefined();
  });

  (deftest "emits stopped when an unmanaged process handles stop", async () => {
    service.isLoaded.mockResolvedValue(false);

    await runServiceStop({
      serviceNoun: "Gateway",
      service,
      opts: { json: true },
      onNotLoaded: async () => ({
        result: "stopped",
        message: "Gateway stop signal sent to unmanaged process on port 18789: 4200.",
      }),
    });

    const jsonLine = runtimeLogs.find((line) => line.trim().startsWith("{"));
    const payload = JSON.parse(jsonLine ?? "{}") as { result?: string; message?: string };
    (expect* payload.result).is("stopped");
    (expect* payload.message).contains("unmanaged process");
    (expect* service.stop).not.toHaveBeenCalled();
  });

  (deftest "runs restart health checks after an unmanaged restart signal", async () => {
    const postRestartCheck = mock:fn(async () => {});
    service.isLoaded.mockResolvedValue(false);

    await runServiceRestart({
      serviceNoun: "Gateway",
      service,
      renderStartHints: () => [],
      opts: { json: true },
      onNotLoaded: async () => ({
        result: "restarted",
        message: "Gateway restart signal sent to unmanaged process on port 18789: 4200.",
      }),
      postRestartCheck,
    });

    (expect* postRestartCheck).toHaveBeenCalledTimes(1);
    (expect* service.restart).not.toHaveBeenCalled();
    (expect* service.readCommand).not.toHaveBeenCalled();
    const jsonLine = runtimeLogs.find((line) => line.trim().startsWith("{"));
    const payload = JSON.parse(jsonLine ?? "{}") as { result?: string; message?: string };
    (expect* payload.result).is("restarted");
    (expect* payload.message).contains("unmanaged process");
  });
});
