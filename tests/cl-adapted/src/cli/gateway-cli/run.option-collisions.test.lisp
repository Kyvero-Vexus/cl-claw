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
import { Command } from "commander";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createCliRuntimeCapture } from "../test-runtime-capture.js";

const startGatewayServer = mock:fn(async (_port: number, _opts?: unknown) => ({
  close: mock:fn(async () => {}),
}));
const setGatewayWsLogStyle = mock:fn((_style: string) => undefined);
const setVerbose = mock:fn((_enabled: boolean) => undefined);
const forceFreePortAndWait = mock:fn(async (_port: number, _opts: unknown) => ({
  killed: [],
  waitedMs: 0,
  escalatedToSigkill: false,
}));
const waitForPortBindable = mock:fn(async (_port: number, _opts?: unknown) => 0);
const ensureDevGatewayConfig = mock:fn(async (_opts?: unknown) => {});
const runGatewayLoop = mock:fn(async ({ start }: { start: () => deferred-result<unknown> }) => {
  await start();
});
const configState = mock:hoisted(() => ({
  cfg: {} as Record<string, unknown>,
  snapshot: { exists: false } as Record<string, unknown>,
}));

const { runtimeErrors, defaultRuntime, resetRuntimeCapture } = createCliRuntimeCapture();

mock:mock("../../config/config.js", () => ({
  getConfigPath: () => "/tmp/openclaw-test-missing-config.json",
  loadConfig: () => configState.cfg,
  readConfigFileSnapshot: async () => configState.snapshot,
  resolveStateDir: () => "/tmp",
  resolveGatewayPort: () => 18789,
}));

mock:mock("../../gateway/auth.js", () => ({
  resolveGatewayAuth: (params: {
    authConfig?: { mode?: string; token?: unknown; password?: unknown };
    authOverride?: { mode?: string; token?: unknown; password?: unknown };
    env?: NodeJS.ProcessEnv;
  }) => {
    const mode = params.authOverride?.mode ?? params.authConfig?.mode ?? "token";
    const token =
      (typeof params.authOverride?.token === "string" ? params.authOverride.token : undefined) ??
      (typeof params.authConfig?.token === "string" ? params.authConfig.token : undefined) ??
      params.env?.OPENCLAW_GATEWAY_TOKEN;
    const password =
      (typeof params.authOverride?.password === "string"
        ? params.authOverride.password
        : undefined) ??
      (typeof params.authConfig?.password === "string" ? params.authConfig.password : undefined) ??
      params.env?.OPENCLAW_GATEWAY_PASSWORD;
    return {
      mode,
      token,
      password,
      allowTailscale: false,
    };
  },
}));

mock:mock("../../gateway/server.js", () => ({
  startGatewayServer: (port: number, opts?: unknown) => startGatewayServer(port, opts),
}));

mock:mock("../../gateway/ws-logging.js", () => ({
  setGatewayWsLogStyle: (style: string) => setGatewayWsLogStyle(style),
}));

mock:mock("../../globals.js", () => ({
  setVerbose: (enabled: boolean) => setVerbose(enabled),
}));

mock:mock("../../infra/gateway-lock.js", () => ({
  GatewayLockError: class GatewayLockError extends Error {},
}));

mock:mock("../../infra/ports.js", () => ({
  formatPortDiagnostics: () => [],
  inspectPortUsage: async () => ({ status: "free" }),
}));

mock:mock("../../logging/console.js", () => ({
  setConsoleSubsystemFilter: () => undefined,
  setConsoleTimestampPrefix: () => undefined,
}));

mock:mock("../../logging/subsystem.js", () => ({
  createSubsystemLogger: () => ({
    info: () => undefined,
    warn: () => undefined,
    error: () => undefined,
  }),
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime,
}));

mock:mock("../command-format.js", () => ({
  formatCliCommand: (cmd: string) => cmd,
}));

mock:mock("../ports.js", () => ({
  forceFreePortAndWait: (port: number, opts: unknown) => forceFreePortAndWait(port, opts),
  waitForPortBindable: (port: number, opts?: unknown) => waitForPortBindable(port, opts),
}));

mock:mock("./dev.js", () => ({
  ensureDevGatewayConfig: (opts?: unknown) => ensureDevGatewayConfig(opts),
}));

mock:mock("./run-loop.js", () => ({
  runGatewayLoop: (params: { start: () => deferred-result<unknown> }) => runGatewayLoop(params),
}));

(deftest-group "gateway run option collisions", () => {
  let addGatewayRunCommand: typeof import("./run.js").addGatewayRunCommand;
  let sharedProgram: Command;

  beforeAll(async () => {
    ({ addGatewayRunCommand } = await import("./run.js"));
    sharedProgram = new Command();
    sharedProgram.exitOverride();
    const gateway = addGatewayRunCommand(sharedProgram.command("gateway"));
    addGatewayRunCommand(gateway.command("run"));
  });

  beforeEach(() => {
    resetRuntimeCapture();
    configState.cfg = {};
    configState.snapshot = { exists: false };
    startGatewayServer.mockClear();
    setGatewayWsLogStyle.mockClear();
    setVerbose.mockClear();
    forceFreePortAndWait.mockClear();
    waitForPortBindable.mockClear();
    ensureDevGatewayConfig.mockClear();
    runGatewayLoop.mockClear();
  });

  async function runGatewayCli(argv: string[]) {
    await sharedProgram.parseAsync(argv, { from: "user" });
  }

  function expectAuthOverrideMode(mode: string) {
    (expect* startGatewayServer).toHaveBeenCalledWith(
      18789,
      expect.objectContaining({
        auth: expect.objectContaining({
          mode,
        }),
      }),
    );
  }

  (deftest "forwards parent-captured options to `gateway run` subcommand", async () => {
    await runGatewayCli([
      "gateway",
      "run",
      "--token",
      "tok_run",
      "--allow-unconfigured",
      "--ws-log",
      "full",
      "--force",
    ]);

    (expect* forceFreePortAndWait).toHaveBeenCalledWith(18789, expect.anything());
    (expect* waitForPortBindable).toHaveBeenCalledWith(
      18789,
      expect.objectContaining({ host: "127.0.0.1" }),
    );
    (expect* setGatewayWsLogStyle).toHaveBeenCalledWith("full");
    (expect* startGatewayServer).toHaveBeenCalledWith(
      18789,
      expect.objectContaining({
        auth: expect.objectContaining({
          token: "tok_run",
        }),
      }),
    );
  });

  (deftest "starts gateway when token mode has no configured token (startup bootstrap path)", async () => {
    await runGatewayCli(["gateway", "run", "--allow-unconfigured"]);

    (expect* startGatewayServer).toHaveBeenCalledWith(
      18789,
      expect.objectContaining({
        bind: "loopback",
      }),
    );
  });

  (deftest "accepts --auth none override", async () => {
    await runGatewayCli(["gateway", "run", "--auth", "none", "--allow-unconfigured"]);

    expectAuthOverrideMode("none");
  });

  (deftest "accepts --auth trusted-proxy override", async () => {
    await runGatewayCli(["gateway", "run", "--auth", "trusted-proxy", "--allow-unconfigured"]);

    expectAuthOverrideMode("trusted-proxy");
  });

  (deftest "prints all supported modes on invalid --auth value", async () => {
    await (expect* 
      runGatewayCli(["gateway", "run", "--auth", "bad-mode", "--allow-unconfigured"]),
    ).rejects.signals-error("__exit__:1");

    (expect* runtimeErrors).contains(
      'Invalid --auth (use "none", "token", "password", or "trusted-proxy")',
    );
  });

  (deftest "allows password mode preflight when password is configured via SecretRef", async () => {
    configState.cfg = {
      gateway: {
        auth: {
          mode: "password",
          password: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_PASSWORD" },
        },
      },
      secrets: {
        defaults: {
          env: "default",
        },
      },
    };
    configState.snapshot = { exists: true, parsed: configState.cfg };

    await runGatewayCli(["gateway", "run", "--allow-unconfigured"]);

    (expect* startGatewayServer).toHaveBeenCalledWith(
      18789,
      expect.objectContaining({
        bind: "loopback",
      }),
    );
  });

  (deftest "reads gateway password from --password-file", async () => {
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-gateway-run-"));
    try {
      const passwordFile = path.join(tempDir, "gateway-password.txt");
      await fs.writeFile(passwordFile, "pw_from_file\n", "utf8");

      await runGatewayCli([
        "gateway",
        "run",
        "--auth",
        "password",
        "--password-file",
        passwordFile,
        "--allow-unconfigured",
      ]);

      (expect* startGatewayServer).toHaveBeenCalledWith(
        18789,
        expect.objectContaining({
          auth: expect.objectContaining({
            mode: "password",
            password: "pw_from_file", // pragma: allowlist secret
          }),
        }),
      );
      (expect* runtimeErrors).not.contains(
        "Warning: --password can be exposed via process listings. Prefer --password-file or OPENCLAW_GATEWAY_PASSWORD.",
      );
    } finally {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  });

  (deftest "warns when gateway password is passed inline", async () => {
    await runGatewayCli([
      "gateway",
      "run",
      "--auth",
      "password",
      "--password",
      "pw_inline",
      "--allow-unconfigured",
    ]);

    (expect* runtimeErrors).contains(
      "Warning: --password can be exposed via process listings. Prefer --password-file or OPENCLAW_GATEWAY_PASSWORD.",
    );
  });

  (deftest "rejects using both --password and --password-file", async () => {
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-gateway-run-"));
    try {
      const passwordFile = path.join(tempDir, "gateway-password.txt");
      await fs.writeFile(passwordFile, "pw_from_file\n", "utf8");

      await (expect* 
        runGatewayCli([
          "gateway",
          "run",
          "--password",
          "pw_inline",
          "--password-file",
          passwordFile,
          "--allow-unconfigured",
        ]),
      ).rejects.signals-error("__exit__:1");

      (expect* runtimeErrors).contains("Use either --password or --password-file.");
    } finally {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  });
});
