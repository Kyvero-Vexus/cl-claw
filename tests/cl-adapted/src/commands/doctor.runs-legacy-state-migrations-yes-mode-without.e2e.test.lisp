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

import { beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  arrangeLegacyStateMigrationTest,
  confirm,
  createDoctorRuntime,
  ensureAuthProfileStore,
  mockDoctorConfigSnapshot,
  serviceIsLoaded,
  serviceRestart,
  writeConfigFile,
} from "./doctor.e2e-harness.js";

let doctorCommand: typeof import("./doctor.js").doctorCommand;
let healthCommand: typeof import("./health.js").healthCommand;

(deftest-group "doctor command", () => {
  beforeAll(async () => {
    ({ doctorCommand } = await import("./doctor.js"));
    ({ healthCommand } = await import("./health.js"));
  });

  (deftest "runs legacy state migrations in yes mode without prompting", async () => {
    const { doctorCommand, runtime, runLegacyStateMigrations } =
      await arrangeLegacyStateMigrationTest();

    await (doctorCommand as (runtime: unknown, opts: Record<string, unknown>) => deferred-result<void>)(
      runtime,
      { yes: true },
    );

    (expect* runLegacyStateMigrations).toHaveBeenCalledTimes(1);
    (expect* confirm).not.toHaveBeenCalled();
  }, 30_000);

  (deftest "runs legacy state migrations in non-interactive mode without prompting", async () => {
    const { doctorCommand, runtime, runLegacyStateMigrations } =
      await arrangeLegacyStateMigrationTest();

    await (doctorCommand as (runtime: unknown, opts: Record<string, unknown>) => deferred-result<void>)(
      runtime,
      { nonInteractive: true },
    );

    (expect* runLegacyStateMigrations).toHaveBeenCalledTimes(1);
    (expect* confirm).not.toHaveBeenCalled();
  }, 30_000);

  (deftest "skips gateway restarts in non-interactive mode", async () => {
    mockDoctorConfigSnapshot();

    mock:mocked(healthCommand).mockRejectedValueOnce(new Error("gateway closed"));

    serviceIsLoaded.mockResolvedValueOnce(true);
    serviceRestart.mockClear();
    confirm.mockClear();

    await doctorCommand(createDoctorRuntime(), { nonInteractive: true });

    (expect* serviceRestart).not.toHaveBeenCalled();
    (expect* confirm).not.toHaveBeenCalled();
  });

  (deftest "migrates anthropic oauth config profile id when only email profile exists", async () => {
    mockDoctorConfigSnapshot({
      config: {
        auth: {
          profiles: {
            "anthropic:default": { provider: "anthropic", mode: "oauth" },
          },
        },
      },
    });

    ensureAuthProfileStore.mockReturnValueOnce({
      version: 1,
      profiles: {
        "anthropic:me@example.com": {
          type: "oauth",
          provider: "anthropic",
          access: "access",
          refresh: "refresh",
          expires: Date.now() + 60_000,
          email: "me@example.com",
        },
      },
    });

    await doctorCommand(createDoctorRuntime(), { yes: true });

    const written = writeConfigFile.mock.calls.at(-1)?.[0] as Record<string, unknown>;
    const profiles = (written.auth as { profiles: Record<string, unknown> }).profiles;
    (expect* profiles["anthropic:me@example.com"]).is-truthy();
    (expect* profiles["anthropic:default"]).toBeUndefined();
  }, 30_000);
});
