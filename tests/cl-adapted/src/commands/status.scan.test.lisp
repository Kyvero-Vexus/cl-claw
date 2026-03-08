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

import { describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  readBestEffortConfig: mock:fn(),
  resolveCommandSecretRefsViaGateway: mock:fn(),
  buildChannelsTable: mock:fn(),
  getUpdateCheckResult: mock:fn(),
  getAgentLocalStatuses: mock:fn(),
  getStatusSummary: mock:fn(),
  buildGatewayConnectionDetails: mock:fn(),
  probeGateway: mock:fn(),
  resolveGatewayProbeAuthResolution: mock:fn(),
}));

mock:mock("../cli/progress.js", () => ({
  withProgress: mock:fn(async (_opts, run) => await run({ setLabel: mock:fn(), tick: mock:fn() })),
}));

mock:mock("../config/config.js", () => ({
  readBestEffortConfig: mocks.readBestEffortConfig,
}));

mock:mock("../cli/command-secret-gateway.js", () => ({
  resolveCommandSecretRefsViaGateway: mocks.resolveCommandSecretRefsViaGateway,
}));

mock:mock("./status-all/channels.js", () => ({
  buildChannelsTable: mocks.buildChannelsTable,
}));

mock:mock("./status.update.js", () => ({
  getUpdateCheckResult: mocks.getUpdateCheckResult,
}));

mock:mock("./status.agent-local.js", () => ({
  getAgentLocalStatuses: mocks.getAgentLocalStatuses,
}));

mock:mock("./status.summary.js", () => ({
  getStatusSummary: mocks.getStatusSummary,
}));

mock:mock("../infra/os-summary.js", () => ({
  resolveOsSummary: mock:fn(() => ({ label: "test-os" })),
}));

mock:mock("../infra/tailscale.js", () => ({
  getTailnetHostname: mock:fn(),
}));

mock:mock("../gateway/call.js", () => ({
  buildGatewayConnectionDetails: mocks.buildGatewayConnectionDetails,
  callGateway: mock:fn(),
}));

mock:mock("../gateway/probe.js", () => ({
  probeGateway: mocks.probeGateway,
}));

mock:mock("./status.gateway-probe.js", () => ({
  pickGatewaySelfPresence: mock:fn(() => null),
  resolveGatewayProbeAuthResolution: mocks.resolveGatewayProbeAuthResolution,
}));

mock:mock("../memory/index.js", () => ({
  getMemorySearchManager: mock:fn(),
}));

mock:mock("../process/exec.js", () => ({
  runExec: mock:fn(),
}));

import { scanStatus } from "./status.scan.js";

(deftest-group "scanStatus", () => {
  (deftest "passes sourceConfig into buildChannelsTable for summary-mode status output", async () => {
    mocks.readBestEffortConfig.mockResolvedValue({
      marker: "source",
      session: {},
      plugins: { enabled: false },
      gateway: {},
    });
    mocks.resolveCommandSecretRefsViaGateway.mockResolvedValue({
      resolvedConfig: {
        marker: "resolved",
        session: {},
        plugins: { enabled: false },
        gateway: {},
      },
      diagnostics: [],
    });
    mocks.getUpdateCheckResult.mockResolvedValue({
      installKind: "git",
      git: null,
      registry: null,
    });
    mocks.getAgentLocalStatuses.mockResolvedValue({
      defaultId: "main",
      agents: [],
    });
    mocks.getStatusSummary.mockResolvedValue({
      linkChannel: { linked: false },
      sessions: { count: 0, paths: [], defaults: {}, recent: [] },
    });
    mocks.buildGatewayConnectionDetails.mockReturnValue({
      url: "ws://127.0.0.1:18789",
      urlSource: "default",
    });
    mocks.resolveGatewayProbeAuthResolution.mockReturnValue({
      auth: {},
      warning: undefined,
    });
    mocks.probeGateway.mockResolvedValue({
      ok: false,
      url: "ws://127.0.0.1:18789",
      connectLatencyMs: null,
      error: "timeout",
      close: null,
      health: null,
      status: null,
      presence: null,
      configSnapshot: null,
    });
    mocks.buildChannelsTable.mockResolvedValue({
      rows: [],
      details: [],
    });

    await scanStatus({ json: false }, {} as never);

    (expect* mocks.buildChannelsTable).toHaveBeenCalledWith(
      expect.objectContaining({ marker: "resolved" }),
      expect.objectContaining({
        sourceConfig: expect.objectContaining({ marker: "source" }),
      }),
    );
  });
});
