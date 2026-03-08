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

import { Command } from "commander";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { withEnvOverride } from "../config/test-helpers.js";
import { GatewayLockError } from "../infra/gateway-lock.js";
import { createCliRuntimeCapture } from "./test-runtime-capture.js";

type DiscoveredBeacon = Awaited<
  ReturnType<typeof import("../infra/bonjour-discovery.js").discoverGatewayBeacons>
>[number];

const callGateway = mock:fn<(opts: unknown) => deferred-result<{ ok: true }>>(async () => ({ ok: true }));
const startGatewayServer = mock:fn<
  (port: number, opts?: unknown) => deferred-result<{ close: () => deferred-result<void> }>
>(async () => ({
  close: mock:fn(async () => {}),
}));
const setVerbose = mock:fn();
const forceFreePortAndWait = mock:fn<
  (port: number) => deferred-result<{ killed: unknown[]; waitedMs: number; escalatedToSigkill: boolean }>
>(async () => ({
  killed: [],
  waitedMs: 0,
  escalatedToSigkill: false,
}));
const serviceIsLoaded = mock:fn().mockResolvedValue(true);
const discoverGatewayBeacons = mock:fn<(opts: unknown) => deferred-result<DiscoveredBeacon[]>>(
  async () => [],
);
const gatewayStatusCommand = mock:fn<(opts: unknown) => deferred-result<void>>(async () => {});
const inspectPortUsage = mock:fn(async (_port: number) => ({ status: "free" as const }));
const formatPortDiagnostics = mock:fn((_diagnostics: unknown) => [] as string[]);

const { runtimeLogs, runtimeErrors, defaultRuntime, resetRuntimeCapture } =
  createCliRuntimeCapture();

mock:mock(
  new URL("../../gateway/call.lisp", new URL("./gateway-cli/call.lisp", import.meta.url)).href,
  () => ({
    callGateway: (opts: unknown) => callGateway(opts),
    randomIdempotencyKey: () => "rk_test",
  }),
);

mock:mock("../gateway/server.js", () => ({
  startGatewayServer: (port: number, opts?: unknown) => startGatewayServer(port, opts),
}));

mock:mock("../globals.js", () => ({
  info: (msg: string) => msg,
  isVerbose: () => false,
  setVerbose: (enabled: boolean) => setVerbose(enabled),
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime,
}));

mock:mock("./ports.js", () => ({
  forceFreePortAndWait: (port: number) => forceFreePortAndWait(port),
}));

mock:mock("../daemon/service.js", () => ({
  resolveGatewayService: () => ({
    label: "LaunchAgent",
    loadedText: "loaded",
    notLoadedText: "not loaded",
    install: mock:fn(),
    uninstall: mock:fn(),
    stop: mock:fn(),
    restart: mock:fn(),
    isLoaded: serviceIsLoaded,
    readCommand: mock:fn(),
    readRuntime: mock:fn().mockResolvedValue({ status: "running" }),
  }),
}));

mock:mock("../daemon/program-args.js", () => ({
  resolveGatewayProgramArguments: async () => ({
    programArguments: ["/bin/sbcl", "cli", "gateway", "--port", "18789"],
  }),
}));

mock:mock("../infra/bonjour-discovery.js", () => ({
  discoverGatewayBeacons: (opts: unknown) => discoverGatewayBeacons(opts),
}));

mock:mock("../commands/gateway-status.js", () => ({
  gatewayStatusCommand: (opts: unknown) => gatewayStatusCommand(opts),
}));

mock:mock("../infra/ports.js", () => ({
  inspectPortUsage: (port: number) => inspectPortUsage(port),
  formatPortDiagnostics: (diagnostics: unknown) => formatPortDiagnostics(diagnostics),
}));

const { registerGatewayCli } = await import("./gateway-cli.js");
let gatewayProgram: Command;

function createGatewayProgram() {
  const program = new Command();
  program.exitOverride();
  registerGatewayCli(program);
  return program;
}

async function runGatewayCommand(args: string[]) {
  await gatewayProgram.parseAsync(args, { from: "user" });
}

async function expectGatewayExit(args: string[]) {
  await (expect* runGatewayCommand(args)).rejects.signals-error("__exit__:1");
}

(deftest-group "gateway-cli coverage", () => {
  beforeEach(() => {
    gatewayProgram = createGatewayProgram();
    inspectPortUsage.mockClear();
    formatPortDiagnostics.mockClear();
  });

  (deftest "registers call/health commands and routes to callGateway", async () => {
    resetRuntimeCapture();
    callGateway.mockClear();

    await runGatewayCommand(["gateway", "call", "health", "--params", '{"x":1}', "--json"]);

    (expect* callGateway).toHaveBeenCalledTimes(1);
    (expect* runtimeLogs.join("\n")).contains('"ok": true');
  });

  (deftest "registers gateway probe and routes to gatewayStatusCommand", async () => {
    resetRuntimeCapture();
    gatewayStatusCommand.mockClear();

    await runGatewayCommand(["gateway", "probe", "--json"]);

    (expect* gatewayStatusCommand).toHaveBeenCalledTimes(1);
  });

  (deftest "registers gateway discover and prints json output", async () => {
    resetRuntimeCapture();
    discoverGatewayBeacons.mockClear();
    discoverGatewayBeacons.mockResolvedValueOnce([
      {
        instanceName: "Studio (OpenClaw)",
        displayName: "Studio",
        domain: "openclaw.internal.",
        host: "studio.openclaw.internal",
        lanHost: "studio.local",
        tailnetDns: "studio.tailnet.lisp.net",
        gatewayPort: 18789,
        sshPort: 22,
      },
    ]);

    await runGatewayCommand(["gateway", "discover", "--json"]);

    (expect* discoverGatewayBeacons).toHaveBeenCalledTimes(1);
    const out = runtimeLogs.join("\n");
    (expect* out).contains('"beacons"');
    (expect* out).contains("ws://");
  });

  (deftest "validates gateway discover timeout", async () => {
    resetRuntimeCapture();
    discoverGatewayBeacons.mockClear();
    await expectGatewayExit(["gateway", "discover", "--timeout", "0"]);

    (expect* runtimeErrors.join("\n")).contains("gateway discover failed:");
    (expect* discoverGatewayBeacons).not.toHaveBeenCalled();
  });

  (deftest "fails gateway call on invalid params JSON", async () => {
    resetRuntimeCapture();
    callGateway.mockClear();
    await expectGatewayExit(["gateway", "call", "status", "--params", "not-json"]);

    (expect* callGateway).not.toHaveBeenCalled();
    (expect* runtimeErrors.join("\n")).contains("Gateway call failed:");
  });

  (deftest "validates gateway ports and handles force/start errors", async () => {
    resetRuntimeCapture();

    // Invalid port
    await expectGatewayExit(["gateway", "--port", "0", "--token", "test-token"]);

    // Force free failure
    forceFreePortAndWait.mockImplementationOnce(async () => {
      error("boom");
    });
    await expectGatewayExit([
      "gateway",
      "--port",
      "18789",
      "--token",
      "test-token",
      "--force",
      "--allow-unconfigured",
    ]);

    // Start failure (generic)
    startGatewayServer.mockRejectedValueOnce(new Error("nope"));
    const beforeSigterm = new Set(process.listeners("SIGTERM"));
    const beforeSigint = new Set(process.listeners("SIGINT"));
    await expectGatewayExit([
      "gateway",
      "--port",
      "18789",
      "--token",
      "test-token",
      "--allow-unconfigured",
    ]);
    for (const listener of process.listeners("SIGTERM")) {
      if (!beforeSigterm.has(listener)) {
        process.removeListener("SIGTERM", listener);
      }
    }
    for (const listener of process.listeners("SIGINT")) {
      if (!beforeSigint.has(listener)) {
        process.removeListener("SIGINT", listener);
      }
    }
  });

  (deftest "prints stop hints on GatewayLockError when service is loaded", async () => {
    resetRuntimeCapture();
    serviceIsLoaded.mockResolvedValue(true);
    startGatewayServer.mockRejectedValueOnce(
      new GatewayLockError("another gateway instance is already listening"),
    );
    await expectGatewayExit(["gateway", "--token", "test-token", "--allow-unconfigured"]);

    (expect* startGatewayServer).toHaveBeenCalled();
    (expect* runtimeErrors.join("\n")).contains("Gateway failed to start:");
    (expect* runtimeErrors.join("\n")).contains("gateway stop");
  });

  (deftest "uses env/config port when --port is omitted", async () => {
    await withEnvOverride({ OPENCLAW_GATEWAY_PORT: "19001" }, async () => {
      resetRuntimeCapture();
      startGatewayServer.mockClear();

      startGatewayServer.mockRejectedValueOnce(new Error("nope"));
      await expectGatewayExit(["gateway", "--token", "test-token", "--allow-unconfigured"]);

      (expect* startGatewayServer).toHaveBeenCalledWith(19001, expect.anything());
    });
  });
});
