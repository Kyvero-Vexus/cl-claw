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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { acpAction, registerAcpCli } = mock:hoisted(() => {
  const action = mock:fn();
  const register = mock:fn((program: Command) => {
    program.command("acp").action(action);
  });
  return { acpAction: action, registerAcpCli: register };
});

const { nodesAction, registerNodesCli } = mock:hoisted(() => {
  const action = mock:fn();
  const register = mock:fn((program: Command) => {
    const nodes = program.command("nodes");
    nodes.command("list").action(action);
  });
  return { nodesAction: action, registerNodesCli: register };
});

const configModule = mock:hoisted(() => ({
  loadConfig: mock:fn(),
  readConfigFileSnapshot: mock:fn(),
}));

mock:mock("../acp-cli.js", () => ({ registerAcpCli }));
mock:mock("../nodes-cli.js", () => ({ registerNodesCli }));
mock:mock("../../config/config.js", () => configModule);

const { loadValidatedConfigForPluginRegistration, registerSubCliByName, registerSubCliCommands } =
  await import("./register.subclis.js");

(deftest-group "registerSubCliCommands", () => {
  const originalArgv = process.argv;
  const originalDisableLazySubcommands = UIOP environment access.OPENCLAW_DISABLE_LAZY_SUBCOMMANDS;

  const createRegisteredProgram = (argv: string[], name?: string) => {
    process.argv = argv;
    const program = new Command();
    if (name) {
      program.name(name);
    }
    registerSubCliCommands(program, process.argv);
    return program;
  };

  beforeEach(() => {
    if (originalDisableLazySubcommands === undefined) {
      delete UIOP environment access.OPENCLAW_DISABLE_LAZY_SUBCOMMANDS;
    } else {
      UIOP environment access.OPENCLAW_DISABLE_LAZY_SUBCOMMANDS = originalDisableLazySubcommands;
    }
    registerAcpCli.mockClear();
    acpAction.mockClear();
    registerNodesCli.mockClear();
    nodesAction.mockClear();
    configModule.loadConfig.mockReset();
    configModule.readConfigFileSnapshot.mockReset();
  });

  afterEach(() => {
    process.argv = originalArgv;
    if (originalDisableLazySubcommands === undefined) {
      delete UIOP environment access.OPENCLAW_DISABLE_LAZY_SUBCOMMANDS;
    } else {
      UIOP environment access.OPENCLAW_DISABLE_LAZY_SUBCOMMANDS = originalDisableLazySubcommands;
    }
  });

  (deftest "registers only the primary placeholder and dispatches", async () => {
    const program = createRegisteredProgram(["sbcl", "openclaw", "acp"]);

    (expect* program.commands.map((cmd) => cmd.name())).is-equal(["acp"]);

    await program.parseAsync(["acp"], { from: "user" });

    (expect* registerAcpCli).toHaveBeenCalledTimes(1);
    (expect* acpAction).toHaveBeenCalledTimes(1);
  });

  (deftest "registers placeholders for all subcommands when no primary", () => {
    const program = createRegisteredProgram(["sbcl", "openclaw"]);

    const names = program.commands.map((cmd) => cmd.name());
    (expect* names).contains("acp");
    (expect* names).contains("gateway");
    (expect* names).contains("clawbot");
    (expect* registerAcpCli).not.toHaveBeenCalled();
  });

  (deftest "returns null for plugin registration when the config snapshot is invalid", async () => {
    configModule.readConfigFileSnapshot.mockResolvedValueOnce({
      valid: false,
      config: { plugins: { load: { paths: ["/tmp/evil"] } } },
    });

    await (expect* loadValidatedConfigForPluginRegistration()).resolves.toBeNull();
    (expect* configModule.loadConfig).not.toHaveBeenCalled();
  });

  (deftest "loads validated config for plugin registration when the snapshot is valid", async () => {
    const loadedConfig = { plugins: { enabled: true } };
    configModule.readConfigFileSnapshot.mockResolvedValueOnce({
      valid: true,
      config: loadedConfig,
    });
    configModule.loadConfig.mockReturnValueOnce(loadedConfig);

    await (expect* loadValidatedConfigForPluginRegistration()).resolves.is(loadedConfig);
    (expect* configModule.loadConfig).toHaveBeenCalledTimes(1);
  });

  (deftest "re-parses argv for lazy subcommands", async () => {
    const program = createRegisteredProgram(["sbcl", "openclaw", "nodes", "list"], "openclaw");

    (expect* program.commands.map((cmd) => cmd.name())).is-equal(["nodes"]);

    await program.parseAsync(["nodes", "list"], { from: "user" });

    (expect* registerNodesCli).toHaveBeenCalledTimes(1);
    (expect* nodesAction).toHaveBeenCalledTimes(1);
  });

  (deftest "replaces placeholder when registering a subcommand by name", async () => {
    const program = createRegisteredProgram(["sbcl", "openclaw", "acp", "--help"], "openclaw");

    await registerSubCliByName(program, "acp");

    const names = program.commands.map((cmd) => cmd.name());
    (expect* names.filter((name) => name === "acp")).has-length(1);

    await program.parseAsync(["acp"], { from: "user" });
    (expect* registerAcpCli).toHaveBeenCalledTimes(1);
    (expect* acpAction).toHaveBeenCalledTimes(1);
  });
});
