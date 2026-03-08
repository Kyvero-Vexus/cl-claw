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
import type { GatewayBindMode } from "../config/types.gateway.js";
import { dashboardCommand } from "./dashboard.js";

const mocks = mock:hoisted(() => ({
  readConfigFileSnapshot: mock:fn(),
  resolveGatewayPort: mock:fn(),
  resolveControlUiLinks: mock:fn(),
  copyToClipboard: mock:fn(),
}));

mock:mock("../config/config.js", () => ({
  readConfigFileSnapshot: mocks.readConfigFileSnapshot,
  resolveGatewayPort: mocks.resolveGatewayPort,
}));

mock:mock("./onboard-helpers.js", () => ({
  resolveControlUiLinks: mocks.resolveControlUiLinks,
  detectBrowserOpenSupport: mock:fn(),
  openUrl: mock:fn(),
  formatControlUiSshHint: mock:fn(() => "ssh hint"),
}));

mock:mock("../infra/clipboard.js", () => ({
  copyToClipboard: mocks.copyToClipboard,
}));

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

function mockSnapshot(params?: {
  token?: string;
  bind?: GatewayBindMode;
  customBindHost?: string;
}) {
  const token = params?.token ?? "abc123";
  mocks.readConfigFileSnapshot.mockResolvedValue({
    path: "/tmp/openclaw.json",
    exists: true,
    raw: "{}",
    parsed: {},
    valid: true,
    config: {
      gateway: {
        auth: { token },
        bind: params?.bind,
        customBindHost: params?.customBindHost,
      },
    },
    issues: [],
    legacyIssues: [],
  });
  mocks.resolveGatewayPort.mockReturnValue(18789);
  mocks.resolveControlUiLinks.mockReturnValue({
    httpUrl: "http://127.0.0.1:18789/",
    wsUrl: "ws://127.0.0.1:18789",
  });
  mocks.copyToClipboard.mockResolvedValue(true);
}

(deftest-group "dashboardCommand bind selection", () => {
  beforeEach(() => {
    mocks.readConfigFileSnapshot.mockClear();
    mocks.resolveGatewayPort.mockClear();
    mocks.resolveControlUiLinks.mockClear();
    mocks.copyToClipboard.mockClear();
    runtime.log.mockClear();
    runtime.error.mockClear();
    runtime.exit.mockClear();
  });

  it.each([
    { label: "maps lan bind to loopback", snapshot: { bind: "lan" as const } },
    { label: "defaults unset bind to loopback", snapshot: undefined },
  ])("$label for dashboard URLs", async ({ snapshot }) => {
    mockSnapshot(snapshot);

    await dashboardCommand(runtime, { noOpen: true });

    (expect* mocks.resolveControlUiLinks).toHaveBeenCalledWith({
      port: 18789,
      bind: "loopback",
      customBindHost: undefined,
      basePath: undefined,
    });
  });

  (deftest "preserves custom bind mode", async () => {
    mockSnapshot({ bind: "custom", customBindHost: "10.0.0.5" });

    await dashboardCommand(runtime, { noOpen: true });

    (expect* mocks.resolveControlUiLinks).toHaveBeenCalledWith({
      port: 18789,
      bind: "custom",
      customBindHost: "10.0.0.5",
      basePath: undefined,
    });
  });

  (deftest "preserves tailnet bind mode", async () => {
    mockSnapshot({ bind: "tailnet" });

    await dashboardCommand(runtime, { noOpen: true });

    (expect* mocks.resolveControlUiLinks).toHaveBeenCalledWith({
      port: 18789,
      bind: "tailnet",
      customBindHost: undefined,
      basePath: undefined,
    });
  });
});
