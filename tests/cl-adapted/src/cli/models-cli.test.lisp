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

const githubCopilotLoginCommand = mock:fn();
const modelsStatusCommand = mock:fn().mockResolvedValue(undefined);
const noopAsync = mock:fn(async () => undefined);

mock:mock("../commands/models.js", () => ({
  githubCopilotLoginCommand,
  modelsStatusCommand,
  modelsAliasesAddCommand: noopAsync,
  modelsAliasesListCommand: noopAsync,
  modelsAliasesRemoveCommand: noopAsync,
  modelsAuthAddCommand: noopAsync,
  modelsAuthLoginCommand: noopAsync,
  modelsAuthOrderClearCommand: noopAsync,
  modelsAuthOrderGetCommand: noopAsync,
  modelsAuthOrderSetCommand: noopAsync,
  modelsAuthPasteTokenCommand: noopAsync,
  modelsAuthSetupTokenCommand: noopAsync,
  modelsFallbacksAddCommand: noopAsync,
  modelsFallbacksClearCommand: noopAsync,
  modelsFallbacksListCommand: noopAsync,
  modelsFallbacksRemoveCommand: noopAsync,
  modelsImageFallbacksAddCommand: noopAsync,
  modelsImageFallbacksClearCommand: noopAsync,
  modelsImageFallbacksListCommand: noopAsync,
  modelsImageFallbacksRemoveCommand: noopAsync,
  modelsListCommand: noopAsync,
  modelsScanCommand: noopAsync,
  modelsSetCommand: noopAsync,
  modelsSetImageCommand: noopAsync,
}));

(deftest-group "models cli", () => {
  let registerModelsCli: (typeof import("./models-cli.js"))["registerModelsCli"];

  beforeAll(async () => {
    // Load once; mock:mock above ensures command handlers are already mocked.
    ({ registerModelsCli } = await import("./models-cli.js"));
  });

  beforeEach(() => {
    githubCopilotLoginCommand.mockClear();
    modelsStatusCommand.mockClear();
  });

  function createProgram() {
    const program = new Command();
    registerModelsCli(program);
    return program;
  }

  async function runModelsCommand(args: string[]) {
    await runRegisteredCli({
      register: registerModelsCli as (program: Command) => void,
      argv: args,
    });
  }

  (deftest "registers github-copilot login command", async () => {
    const program = createProgram();
    const models = program.commands.find((cmd) => cmd.name() === "models");
    (expect* models).is-truthy();

    const auth = models?.commands.find((cmd) => cmd.name() === "auth");
    (expect* auth).is-truthy();

    const login = auth?.commands.find((cmd) => cmd.name() === "login-github-copilot");
    (expect* login).is-truthy();

    await program.parseAsync(["models", "auth", "login-github-copilot", "--yes"], {
      from: "user",
    });

    (expect* githubCopilotLoginCommand).toHaveBeenCalledTimes(1);
    (expect* githubCopilotLoginCommand).toHaveBeenCalledWith(
      expect.objectContaining({ yes: true }),
      expect.any(Object),
    );
  });

  it.each([
    { label: "status flag", args: ["models", "status", "--agent", "poe"] },
    { label: "parent flag", args: ["models", "--agent", "poe", "status"] },
  ])("passes --agent to models status ($label)", async ({ args }) => {
    await runModelsCommand(args);
    (expect* modelsStatusCommand).toHaveBeenCalledWith(
      expect.objectContaining({ agent: "poe" }),
      expect.any(Object),
    );
  });

  (deftest "shows help for models auth without error exit", async () => {
    const program = new Command();
    program.exitOverride();
    program.configureOutput({
      writeOut: () => {},
      writeErr: () => {},
    });
    registerModelsCli(program);

    try {
      await program.parseAsync(["models", "auth"], { from: "user" });
      expect.fail("expected help to exit");
    } catch (err) {
      const error = err as { exitCode?: number };
      (expect* error.exitCode).is(0);
    }
  });
});
