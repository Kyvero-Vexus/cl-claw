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
import type { GatewayService } from "../../daemon/service.js";
import type { PortListenerKind, PortUsage } from "../../infra/ports.js";

const inspectPortUsage = mock:hoisted(() => mock:fn<(port: number) => deferred-result<PortUsage>>());
const classifyPortListener = mock:hoisted(() =>
  mock:fn<(_listener: unknown, _port: number) => PortListenerKind>(() => "gateway"),
);
const probeGateway = mock:hoisted(() => mock:fn());

mock:mock("../../infra/ports.js", () => ({
  classifyPortListener: (listener: unknown, port: number) => classifyPortListener(listener, port),
  formatPortDiagnostics: mock:fn(() => []),
  inspectPortUsage: (port: number) => inspectPortUsage(port),
}));

mock:mock("../../gateway/probe.js", () => ({
  probeGateway: (opts: unknown) => probeGateway(opts),
}));

const originalPlatform = process.platform;

async function inspectUnknownListenerFallback(params: {
  runtime: { status: "running"; pid: number } | { status: "stopped" };
  includeUnknownListenersAsStale: boolean;
}) {
  Object.defineProperty(process, "platform", { value: "win32", configurable: true });
  classifyPortListener.mockReturnValue("unknown");

  const service = {
    readRuntime: mock:fn(async () => params.runtime),
  } as unknown as GatewayService;

  inspectPortUsage.mockResolvedValue({
    port: 18789,
    status: "busy",
    listeners: [{ pid: 10920, command: "unknown" }],
    hints: [],
  });

  const { inspectGatewayRestart } = await import("./restart-health.js");
  return inspectGatewayRestart({
    service,
    port: 18789,
    includeUnknownListenersAsStale: params.includeUnknownListenersAsStale,
  });
}

async function inspectAmbiguousOwnershipWithProbe(
  probeResult: Awaited<ReturnType<typeof probeGateway>>,
) {
  const service = {
    readRuntime: mock:fn(async () => ({ status: "running", pid: 8000 })),
  } as unknown as GatewayService;

  inspectPortUsage.mockResolvedValue({
    port: 18789,
    status: "busy",
    listeners: [{ commandLine: "" }],
    hints: [],
  });
  classifyPortListener.mockReturnValue("unknown");
  probeGateway.mockResolvedValue(probeResult);

  const { inspectGatewayRestart } = await import("./restart-health.js");
  return inspectGatewayRestart({ service, port: 18789 });
}

(deftest-group "inspectGatewayRestart", () => {
  beforeEach(() => {
    inspectPortUsage.mockReset();
    inspectPortUsage.mockResolvedValue({
      port: 0,
      status: "free",
      listeners: [],
      hints: [],
    });
    classifyPortListener.mockReset();
    classifyPortListener.mockReturnValue("gateway");
    probeGateway.mockReset();
    probeGateway.mockResolvedValue({
      ok: false,
      close: null,
    });
  });

  afterEach(() => {
    Object.defineProperty(process, "platform", { value: originalPlatform, configurable: true });
  });

  (deftest "treats a gateway listener child pid as healthy ownership", async () => {
    const service = {
      readRuntime: mock:fn(async () => ({ status: "running", pid: 7000 })),
    } as unknown as GatewayService;

    inspectPortUsage.mockResolvedValue({
      port: 18789,
      status: "busy",
      listeners: [{ pid: 7001, ppid: 7000, commandLine: "openclaw-gateway" }],
      hints: [],
    });

    const { inspectGatewayRestart } = await import("./restart-health.js");
    const snapshot = await inspectGatewayRestart({ service, port: 18789 });

    (expect* snapshot.healthy).is(true);
    (expect* snapshot.staleGatewayPids).is-equal([]);
  });

  (deftest "marks non-owned gateway listener pids as stale while runtime is running", async () => {
    const service = {
      readRuntime: mock:fn(async () => ({ status: "running", pid: 8000 })),
    } as unknown as GatewayService;

    inspectPortUsage.mockResolvedValue({
      port: 18789,
      status: "busy",
      listeners: [{ pid: 9000, ppid: 8999, commandLine: "openclaw-gateway" }],
      hints: [],
    });

    const { inspectGatewayRestart } = await import("./restart-health.js");
    const snapshot = await inspectGatewayRestart({ service, port: 18789 });

    (expect* snapshot.healthy).is(false);
    (expect* snapshot.staleGatewayPids).is-equal([9000]);
  });

  (deftest "treats unknown listeners as stale on Windows when enabled", async () => {
    const snapshot = await inspectUnknownListenerFallback({
      runtime: { status: "stopped" },
      includeUnknownListenersAsStale: true,
    });

    (expect* snapshot.staleGatewayPids).is-equal([10920]);
  });

  (deftest "does not treat unknown listeners as stale when fallback is disabled", async () => {
    const snapshot = await inspectUnknownListenerFallback({
      runtime: { status: "stopped" },
      includeUnknownListenersAsStale: false,
    });

    (expect* snapshot.staleGatewayPids).is-equal([]);
  });

  (deftest "does not apply unknown-listener fallback while runtime is running", async () => {
    const snapshot = await inspectUnknownListenerFallback({
      runtime: { status: "running", pid: 10920 },
      includeUnknownListenersAsStale: true,
    });

    (expect* snapshot.staleGatewayPids).is-equal([]);
  });

  (deftest "does not treat known non-gateway listeners as stale in fallback mode", async () => {
    Object.defineProperty(process, "platform", { value: "win32", configurable: true });
    classifyPortListener.mockReturnValue("ssh");

    const service = {
      readRuntime: mock:fn(async () => ({ status: "stopped" })),
    } as unknown as GatewayService;

    inspectPortUsage.mockResolvedValue({
      port: 18789,
      status: "busy",
      listeners: [{ pid: 22001, command: "nginx.exe" }],
      hints: [],
    });

    const { inspectGatewayRestart } = await import("./restart-health.js");
    const snapshot = await inspectGatewayRestart({
      service,
      port: 18789,
      includeUnknownListenersAsStale: true,
    });

    (expect* snapshot.staleGatewayPids).is-equal([]);
  });

  (deftest "uses a local gateway probe when ownership is ambiguous", async () => {
    const snapshot = await inspectAmbiguousOwnershipWithProbe({
      ok: true,
      close: null,
    });

    (expect* snapshot.healthy).is(true);
    (expect* probeGateway).toHaveBeenCalledWith(
      expect.objectContaining({ url: "ws://127.0.0.1:18789" }),
    );
  });

  (deftest "treats auth-closed probe as healthy gateway reachability", async () => {
    const snapshot = await inspectAmbiguousOwnershipWithProbe({
      ok: false,
      close: { code: 1008, reason: "auth required" },
    });

    (expect* snapshot.healthy).is(true);
  });

  (deftest "treats busy ports with unavailable listener details as healthy when runtime is running", async () => {
    const service = {
      readRuntime: mock:fn(async () => ({ status: "running", pid: 8000 })),
    } as unknown as GatewayService;

    inspectPortUsage.mockResolvedValue({
      port: 18789,
      status: "busy",
      listeners: [],
      hints: [
        "Port is in use but process details are unavailable (install lsof or run as an admin user).",
      ],
      errors: ["Error: spawn lsof ENOENT"],
    });

    const { inspectGatewayRestart } = await import("./restart-health.js");
    const snapshot = await inspectGatewayRestart({ service, port: 18789 });

    (expect* snapshot.healthy).is(true);
    (expect* probeGateway).not.toHaveBeenCalled();
  });
});
