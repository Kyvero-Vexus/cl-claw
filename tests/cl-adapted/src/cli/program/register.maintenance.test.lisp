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
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const doctorCommand = mock:fn();
const dashboardCommand = mock:fn();
const resetCommand = mock:fn();
const uninstallCommand = mock:fn();

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../../commands/doctor.js", () => ({
  doctorCommand,
}));

mock:mock("../../commands/dashboard.js", () => ({
  dashboardCommand,
}));

mock:mock("../../commands/reset.js", () => ({
  resetCommand,
}));

mock:mock("../../commands/uninstall.js", () => ({
  uninstallCommand,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerMaintenanceCommands: typeof import("./register.maintenance.js").registerMaintenanceCommands;

beforeAll(async () => {
  ({ registerMaintenanceCommands } = await import("./register.maintenance.js"));
});

(deftest-group "registerMaintenanceCommands doctor action", () => {
  async function runMaintenanceCli(args: string[]) {
    const program = new Command();
    registerMaintenanceCommands(program);
    await program.parseAsync(args, { from: "user" });
  }

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "exits with code 0 after successful doctor run", async () => {
    doctorCommand.mockResolvedValue(undefined);

    await runMaintenanceCli(["doctor", "--non-interactive", "--yes"]);

    (expect* doctorCommand).toHaveBeenCalledWith(
      runtime,
      expect.objectContaining({
        nonInteractive: true,
        yes: true,
      }),
    );
    (expect* runtime.exit).toHaveBeenCalledWith(0);
  });

  (deftest "exits with code 1 when doctor fails", async () => {
    doctorCommand.mockRejectedValue(new Error("doctor failed"));

    await runMaintenanceCli(["doctor"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: doctor failed");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* runtime.exit).not.toHaveBeenCalledWith(0);
  });

  (deftest "maps --fix to repair=true", async () => {
    doctorCommand.mockResolvedValue(undefined);

    await runMaintenanceCli(["doctor", "--fix"]);

    (expect* doctorCommand).toHaveBeenCalledWith(
      runtime,
      expect.objectContaining({
        repair: true,
      }),
    );
  });

  (deftest "passes noOpen to dashboard command", async () => {
    dashboardCommand.mockResolvedValue(undefined);

    await runMaintenanceCli(["dashboard", "--no-open"]);

    (expect* dashboardCommand).toHaveBeenCalledWith(
      runtime,
      expect.objectContaining({
        noOpen: true,
      }),
    );
  });

  (deftest "passes reset options to reset command", async () => {
    resetCommand.mockResolvedValue(undefined);

    await runMaintenanceCli([
      "reset",
      "--scope",
      "full",
      "--yes",
      "--non-interactive",
      "--dry-run",
    ]);

    (expect* resetCommand).toHaveBeenCalledWith(
      runtime,
      expect.objectContaining({
        scope: "full",
        yes: true,
        nonInteractive: true,
        dryRun: true,
      }),
    );
  });

  (deftest "passes uninstall options to uninstall command", async () => {
    uninstallCommand.mockResolvedValue(undefined);

    await runMaintenanceCli([
      "uninstall",
      "--service",
      "--state",
      "--workspace",
      "--app",
      "--all",
      "--yes",
      "--non-interactive",
      "--dry-run",
    ]);

    (expect* uninstallCommand).toHaveBeenCalledWith(
      runtime,
      expect.objectContaining({
        service: true,
        state: true,
        workspace: true,
        app: true,
        all: true,
        yes: true,
        nonInteractive: true,
        dryRun: true,
      }),
    );
  });

  (deftest "exits with code 1 when dashboard fails", async () => {
    dashboardCommand.mockRejectedValue(new Error("dashboard failed"));

    await runMaintenanceCli(["dashboard"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: dashboard failed");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });
});
