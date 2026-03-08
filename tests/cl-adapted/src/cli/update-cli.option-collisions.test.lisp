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
import { runRegisteredCli } from "../test-utils/command-runner.js";

const updateCommand = mock:fn(async (_opts: unknown) => {});
const updateStatusCommand = mock:fn(async (_opts: unknown) => {});
const updateWizardCommand = mock:fn(async (_opts: unknown) => {});

const defaultRuntime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("./update-cli/update-command.js", () => ({
  updateCommand: (opts: unknown) => updateCommand(opts),
}));

mock:mock("./update-cli/status.js", () => ({
  updateStatusCommand: (opts: unknown) => updateStatusCommand(opts),
}));

mock:mock("./update-cli/wizard.js", () => ({
  updateWizardCommand: (opts: unknown) => updateWizardCommand(opts),
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime,
}));

(deftest-group "update cli option collisions", () => {
  let registerUpdateCli: typeof import("./update-cli.js").registerUpdateCli;

  beforeAll(async () => {
    ({ registerUpdateCli } = await import("./update-cli.js"));
  });

  beforeEach(() => {
    updateCommand.mockClear();
    updateStatusCommand.mockClear();
    updateWizardCommand.mockClear();
    defaultRuntime.log.mockClear();
    defaultRuntime.error.mockClear();
    defaultRuntime.exit.mockClear();
  });

  (deftest "forwards parent-captured --json/--timeout to `update status`", async () => {
    await runRegisteredCli({
      register: registerUpdateCli as (program: Command) => void,
      argv: ["update", "status", "--json", "--timeout", "9"],
    });

    (expect* updateStatusCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        json: true,
        timeout: "9",
      }),
    );
  });

  (deftest "forwards parent-captured --timeout to `update wizard`", async () => {
    await runRegisteredCli({
      register: registerUpdateCli as (program: Command) => void,
      argv: ["update", "wizard", "--timeout", "13"],
    });

    (expect* updateWizardCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        timeout: "13",
      }),
    );
  });
});
