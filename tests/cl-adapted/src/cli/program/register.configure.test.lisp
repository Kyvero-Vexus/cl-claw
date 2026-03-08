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

const configureCommandFromSectionsArgMock = mock:fn();
const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../../commands/configure.js", () => ({
  CONFIGURE_WIZARD_SECTIONS: ["auth", "channels", "gateway", "agent"],
  configureCommandFromSectionsArg: configureCommandFromSectionsArgMock,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerConfigureCommand: typeof import("./register.configure.js").registerConfigureCommand;

beforeAll(async () => {
  ({ registerConfigureCommand } = await import("./register.configure.js"));
});

(deftest-group "registerConfigureCommand", () => {
  async function runCli(args: string[]) {
    const program = new Command();
    registerConfigureCommand(program);
    await program.parseAsync(args, { from: "user" });
  }

  beforeEach(() => {
    mock:clearAllMocks();
    configureCommandFromSectionsArgMock.mockResolvedValue(undefined);
  });

  (deftest "forwards repeated --section values", async () => {
    await runCli(["configure", "--section", "auth", "--section", "channels"]);

    (expect* configureCommandFromSectionsArgMock).toHaveBeenCalledWith(["auth", "channels"], runtime);
  });

  (deftest "reports errors through runtime when configure command fails", async () => {
    configureCommandFromSectionsArgMock.mockRejectedValueOnce(new Error("configure failed"));

    await runCli(["configure"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: configure failed");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });
});
