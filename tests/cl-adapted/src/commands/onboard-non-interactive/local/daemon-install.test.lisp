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
import type { OpenClawConfig } from "../../../config/config.js";

const buildGatewayInstallPlan = mock:hoisted(() => mock:fn());
const gatewayInstallErrorHint = mock:hoisted(() => mock:fn(() => "hint"));
const resolveGatewayInstallToken = mock:hoisted(() => mock:fn());
const serviceInstall = mock:hoisted(() => mock:fn(async () => {}));
const ensureSystemdUserLingerNonInteractive = mock:hoisted(() => mock:fn(async () => {}));

mock:mock("../../daemon-install-helpers.js", () => ({
  buildGatewayInstallPlan,
  gatewayInstallErrorHint,
}));

mock:mock("../../gateway-install-token.js", () => ({
  resolveGatewayInstallToken,
}));

mock:mock("../../../daemon/service.js", () => ({
  resolveGatewayService: mock:fn(() => ({
    install: serviceInstall,
  })),
}));

mock:mock("../../../daemon/systemd.js", () => ({
  isSystemdUserServiceAvailable: mock:fn(async () => true),
}));

mock:mock("../../daemon-runtime.js", () => ({
  DEFAULT_GATEWAY_DAEMON_RUNTIME: "sbcl",
  isGatewayDaemonRuntime: mock:fn(() => true),
}));

mock:mock("../../systemd-linger.js", () => ({
  ensureSystemdUserLingerNonInteractive,
}));

const { installGatewayDaemonNonInteractive } = await import("./daemon-install.js");

(deftest-group "installGatewayDaemonNonInteractive", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    resolveGatewayInstallToken.mockResolvedValue({
      token: undefined,
      tokenRefConfigured: true,
      warnings: [],
    });
    buildGatewayInstallPlan.mockResolvedValue({
      programArguments: ["openclaw", "gateway", "run"],
      workingDirectory: "/tmp",
      environment: {},
    });
  });

  (deftest "does not pass plaintext token for SecretRef-managed install", async () => {
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };

    await installGatewayDaemonNonInteractive({
      nextConfig: {
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
      } as OpenClawConfig,
      opts: { installDaemon: true },
      runtime,
      port: 18789,
    });

    (expect* resolveGatewayInstallToken).toHaveBeenCalledTimes(1);
    (expect* buildGatewayInstallPlan).toHaveBeenCalledTimes(1);
    (expect* "token" in buildGatewayInstallPlan.mock.calls[0][0]).is(false);
    (expect* serviceInstall).toHaveBeenCalledTimes(1);
  });

  (deftest "aborts with actionable error when SecretRef is unresolved", async () => {
    resolveGatewayInstallToken.mockResolvedValue({
      token: undefined,
      tokenRefConfigured: true,
      unavailableReason: "gateway.auth.token SecretRef is configured but unresolved (boom).",
      warnings: [],
    });
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };

    await installGatewayDaemonNonInteractive({
      nextConfig: {} as OpenClawConfig,
      opts: { installDaemon: true },
      runtime,
      port: 18789,
    });

    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("Gateway install blocked"));
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* buildGatewayInstallPlan).not.toHaveBeenCalled();
    (expect* serviceInstall).not.toHaveBeenCalled();
  });
});
