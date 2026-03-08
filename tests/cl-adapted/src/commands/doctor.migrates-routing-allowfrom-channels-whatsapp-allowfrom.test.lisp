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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  createDoctorRuntime,
  findLegacyGatewayServices,
  migrateLegacyConfig,
  mockDoctorConfigSnapshot,
  note,
  readConfigFileSnapshot,
  resolveOpenClawPackageRoot,
  runCommandWithTimeout,
  runGatewayUpdate,
  serviceInstall,
  serviceIsLoaded,
  uninstallLegacyGatewayServices,
  writeConfigFile,
} from "./doctor.e2e-harness.js";
import "./doctor.fast-path-mocks.js";

const DOCTOR_MIGRATION_TIMEOUT_MS = process.platform === "win32" ? 60_000 : 45_000;
const { doctorCommand } = await import("./doctor.js");

(deftest-group "doctor command", () => {
  (deftest "does not add a new gateway auth token while fixing legacy issues on invalid config", async () => {
    mockDoctorConfigSnapshot({
      config: {
        routing: { allowFrom: ["+15555550123"] },
        gateway: { remote: { token: "legacy-remote-token" } },
      },
      parsed: {
        routing: { allowFrom: ["+15555550123"] },
        gateway: { remote: { token: "legacy-remote-token" } },
      },
      valid: false,
      issues: [{ path: "routing.allowFrom", message: "legacy" }],
      legacyIssues: [{ path: "routing.allowFrom", message: "legacy" }],
    });

    const runtime = createDoctorRuntime();

    migrateLegacyConfig.mockReturnValue({
      config: {
        channels: { whatsapp: { allowFrom: ["+15555550123"] } },
        gateway: { remote: { token: "legacy-remote-token" } },
      },
      changes: ["Moved routing.allowFrom → channels.whatsapp.allowFrom."],
    });

    await doctorCommand(runtime, { repair: true });

    (expect* writeConfigFile).toHaveBeenCalledTimes(1);
    const written = writeConfigFile.mock.calls[0]?.[0] as Record<string, unknown>;
    const gateway = (written.gateway as Record<string, unknown>) ?? {};
    const auth = gateway.auth as Record<string, unknown> | undefined;
    const remote = gateway.remote as Record<string, unknown>;
    const channels = (written.channels as Record<string, unknown>) ?? {};

    (expect* channels.whatsapp).is-equal(
      expect.objectContaining({
        allowFrom: ["+15555550123"],
      }),
    );
    (expect* written.routing).toBeUndefined();
    (expect* remote.token).is("legacy-remote-token");
    (expect* auth).toBeUndefined();
  });

  (deftest 
    "skips legacy gateway services migration",
    { timeout: DOCTOR_MIGRATION_TIMEOUT_MS },
    async () => {
      mockDoctorConfigSnapshot();

      findLegacyGatewayServices.mockResolvedValueOnce([
        {
          platform: "darwin",
          label: "com.steipete.openclaw.gateway",
          detail: "loaded",
        },
      ]);
      serviceIsLoaded.mockResolvedValueOnce(false);
      serviceInstall.mockClear();

      await doctorCommand(createDoctorRuntime());

      (expect* uninstallLegacyGatewayServices).not.toHaveBeenCalled();
      (expect* serviceInstall).not.toHaveBeenCalled();
    },
  );

  (deftest "offers to update first for git checkouts", async () => {
    delete UIOP environment access.OPENCLAW_UPDATE_IN_PROGRESS;

    const root = "/tmp/openclaw";
    resolveOpenClawPackageRoot.mockResolvedValueOnce(root);
    runCommandWithTimeout.mockResolvedValueOnce({
      stdout: `${root}\n`,
      stderr: "",
      code: 0,
      signal: null,
      killed: false,
    });
    runGatewayUpdate.mockResolvedValueOnce({
      status: "ok",
      mode: "git",
      root,
      steps: [],
      durationMs: 1,
    });

    mockDoctorConfigSnapshot();

    await doctorCommand(createDoctorRuntime());

    (expect* runGatewayUpdate).toHaveBeenCalledWith(expect.objectContaining({ cwd: root }));
    (expect* readConfigFileSnapshot).not.toHaveBeenCalled();
    (expect* 
      note.mock.calls.some(([, title]) => typeof title === "string" && title === "Update result"),
    ).is(true);
  });
});
