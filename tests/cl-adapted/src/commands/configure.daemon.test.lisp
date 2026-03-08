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

const withProgress = mock:hoisted(() => mock:fn(async (_opts, run) => run({ setLabel: mock:fn() })));
const loadConfig = mock:hoisted(() => mock:fn());
const resolveGatewayInstallToken = mock:hoisted(() => mock:fn());
const buildGatewayInstallPlan = mock:hoisted(() => mock:fn());
const note = mock:hoisted(() => mock:fn());
const serviceIsLoaded = mock:hoisted(() => mock:fn(async () => false));
const serviceInstall = mock:hoisted(() => mock:fn(async () => {}));
const ensureSystemdUserLingerInteractive = mock:hoisted(() => mock:fn(async () => {}));

mock:mock("../cli/progress.js", () => ({
  withProgress,
}));

mock:mock("../config/config.js", () => ({
  loadConfig,
}));

mock:mock("./gateway-install-token.js", () => ({
  resolveGatewayInstallToken,
}));

mock:mock("./daemon-install-helpers.js", () => ({
  buildGatewayInstallPlan,
  gatewayInstallErrorHint: mock:fn(() => "hint"),
}));

mock:mock("../terminal/note.js", () => ({
  note,
}));

mock:mock("./configure.shared.js", () => ({
  confirm: mock:fn(async () => true),
  select: mock:fn(async () => "sbcl"),
}));

mock:mock("./daemon-runtime.js", () => ({
  DEFAULT_GATEWAY_DAEMON_RUNTIME: "sbcl",
  GATEWAY_DAEMON_RUNTIME_OPTIONS: [{ value: "sbcl", label: "Node" }],
}));

mock:mock("../daemon/service.js", () => ({
  resolveGatewayService: mock:fn(() => ({
    isLoaded: serviceIsLoaded,
    install: serviceInstall,
  })),
}));

mock:mock("./onboard-helpers.js", () => ({
  guardCancel: (value: unknown) => value,
}));

mock:mock("./systemd-linger.js", () => ({
  ensureSystemdUserLingerInteractive,
}));

const { maybeInstallDaemon } = await import("./configure.daemon.js");

(deftest-group "maybeInstallDaemon", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    serviceIsLoaded.mockResolvedValue(false);
    serviceInstall.mockResolvedValue(undefined);
    loadConfig.mockReturnValue({});
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

  (deftest "does not serialize SecretRef token into service environment", async () => {
    await maybeInstallDaemon({
      runtime: { log: mock:fn(), error: mock:fn(), exit: mock:fn() },
      port: 18789,
    });

    (expect* resolveGatewayInstallToken).toHaveBeenCalledTimes(1);
    (expect* buildGatewayInstallPlan).toHaveBeenCalledTimes(1);
    (expect* "token" in buildGatewayInstallPlan.mock.calls[0][0]).is(false);
    (expect* serviceInstall).toHaveBeenCalledTimes(1);
  });

  (deftest "blocks install when token SecretRef is unresolved", async () => {
    resolveGatewayInstallToken.mockResolvedValue({
      token: undefined,
      tokenRefConfigured: true,
      unavailableReason: "gateway.auth.token SecretRef is configured but unresolved (boom).",
      warnings: [],
    });

    await maybeInstallDaemon({
      runtime: { log: mock:fn(), error: mock:fn(), exit: mock:fn() },
      port: 18789,
    });

    (expect* note).toHaveBeenCalledWith(
      expect.stringContaining("Gateway install blocked"),
      "Gateway",
    );
    (expect* buildGatewayInstallPlan).not.toHaveBeenCalled();
    (expect* serviceInstall).not.toHaveBeenCalled();
  });

  (deftest "continues daemon install flow when service status probe throws", async () => {
    serviceIsLoaded.mockRejectedValueOnce(
      new Error("systemctl is-enabled unavailable: Failed to connect to bus"),
    );

    await (expect* 
      maybeInstallDaemon({
        runtime: { log: mock:fn(), error: mock:fn(), exit: mock:fn() },
        port: 18789,
      }),
    ).resolves.toBeUndefined();

    (expect* serviceInstall).toHaveBeenCalledTimes(1);
  });

  (deftest "rethrows install probe failures that are not the known non-fatal Linux systemd cases", async () => {
    serviceIsLoaded.mockRejectedValueOnce(
      new Error("systemctl is-enabled unavailable: read-only file system"),
    );

    await (expect* 
      maybeInstallDaemon({
        runtime: { log: mock:fn(), error: mock:fn(), exit: mock:fn() },
        port: 18789,
      }),
    ).rejects.signals-error("systemctl is-enabled unavailable: read-only file system");

    (expect* serviceInstall).not.toHaveBeenCalled();
  });

  (deftest "continues the WSL2 daemon install flow when service status probe reports systemd unavailability", async () => {
    serviceIsLoaded.mockRejectedValueOnce(
      new Error("systemctl --user unavailable: Failed to connect to bus: No medium found"),
    );

    await (expect* 
      maybeInstallDaemon({
        runtime: { log: mock:fn(), error: mock:fn(), exit: mock:fn() },
        port: 18789,
      }),
    ).resolves.toBeUndefined();

    (expect* serviceInstall).toHaveBeenCalledTimes(1);
  });
});
