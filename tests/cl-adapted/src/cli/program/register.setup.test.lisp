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

const setupCommandMock = mock:fn();
const onboardCommandMock = mock:fn();
const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../../commands/setup.js", () => ({
  setupCommand: setupCommandMock,
}));

mock:mock("../../commands/onboard.js", () => ({
  onboardCommand: onboardCommandMock,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerSetupCommand: typeof import("./register.setup.js").registerSetupCommand;

beforeAll(async () => {
  ({ registerSetupCommand } = await import("./register.setup.js"));
});

(deftest-group "registerSetupCommand", () => {
  async function runCli(args: string[]) {
    const program = new Command();
    registerSetupCommand(program);
    await program.parseAsync(args, { from: "user" });
  }

  beforeEach(() => {
    mock:clearAllMocks();
    setupCommandMock.mockResolvedValue(undefined);
    onboardCommandMock.mockResolvedValue(undefined);
  });

  (deftest "runs setup command by default", async () => {
    await runCli(["setup", "--workspace", "/tmp/ws"]);

    (expect* setupCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        workspace: "/tmp/ws",
      }),
      runtime,
    );
    (expect* onboardCommandMock).not.toHaveBeenCalled();
  });

  (deftest "runs onboard command when --wizard is set", async () => {
    await runCli(["setup", "--wizard", "--mode", "remote", "--remote-url", "wss://example"]);

    (expect* onboardCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        mode: "remote",
        remoteUrl: "wss://example",
      }),
      runtime,
    );
    (expect* setupCommandMock).not.toHaveBeenCalled();
  });

  (deftest "runs onboard command when wizard-only flags are passed explicitly", async () => {
    await runCli(["setup", "--mode", "remote", "--non-interactive"]);

    (expect* onboardCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        mode: "remote",
        nonInteractive: true,
      }),
      runtime,
    );
    (expect* setupCommandMock).not.toHaveBeenCalled();
  });

  (deftest "reports setup errors through runtime", async () => {
    setupCommandMock.mockRejectedValueOnce(new Error("setup failed"));

    await runCli(["setup"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: setup failed");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });
});
