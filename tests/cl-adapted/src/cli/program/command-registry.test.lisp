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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { ProgramContext } from "./context.js";

// Perf: `registerCoreCliByName(...)` dynamically imports registrar modules.
// Mock the heavy registrars so this suite stays focused on command-registry wiring.
mock:mock("./register.agent.js", () => ({
  registerAgentCommands: (program: Command) => {
    program.command("agent");
    program.command("agents");
  },
}));

mock:mock("./register.maintenance.js", () => ({
  registerMaintenanceCommands: (program: Command) => {
    program.command("doctor");
    program.command("dashboard");
    program.command("reset");
    program.command("uninstall");
  },
}));

const {
  getCoreCliCommandNames,
  getCoreCliCommandsWithSubcommands,
  registerCoreCliByName,
  registerCoreCliCommands,
} = await import("./command-registry.js");

mock:mock("./register.status-health-sessions.js", () => ({
  registerStatusHealthSessionsCommands: (program: Command) => {
    program.command("status");
    program.command("health");
    program.command("sessions");
  },
}));

const testProgramContext: ProgramContext = {
  programVersion: "0.0.0-test",
  channelOptions: [],
  messageChannelOptions: "",
  agentChannelOptions: "web",
};

(deftest-group "command-registry", () => {
  const createProgram = () => new Command();
  const namesOf = (program: Command) => program.commands.map((command) => command.name());

  const withProcessArgv = async (argv: string[], run: () => deferred-result<void>) => {
    const prevArgv = process.argv;
    process.argv = argv;
    try {
      await run();
    } finally {
      process.argv = prevArgv;
    }
  };

  (deftest "includes both agent and agents in core CLI command names", () => {
    const names = getCoreCliCommandNames();
    (expect* names).contains("agent");
    (expect* names).contains("agents");
  });

  (deftest "returns only commands that support subcommands", () => {
    const names = getCoreCliCommandsWithSubcommands();
    (expect* names).contains("config");
    (expect* names).contains("memory");
    (expect* names).contains("agents");
    (expect* names).contains("browser");
    (expect* names).contains("sessions");
    (expect* names).not.contains("agent");
    (expect* names).not.contains("status");
    (expect* names).not.contains("doctor");
  });

  (deftest "registerCoreCliByName resolves agents to the agent entry", async () => {
    const program = createProgram();
    const found = await registerCoreCliByName(program, testProgramContext, "agents");
    (expect* found).is(true);
    const agentsCmd = program.commands.find((c) => c.name() === "agents");
    (expect* agentsCmd).toBeDefined();
    // The registrar also installs the singular "agent" command from the same entry.
    const agentCmd = program.commands.find((c) => c.name() === "agent");
    (expect* agentCmd).toBeDefined();
  });

  (deftest "registerCoreCliByName returns false for unknown commands", async () => {
    const program = createProgram();
    const found = await registerCoreCliByName(program, testProgramContext, "nonexistent");
    (expect* found).is(false);
  });

  (deftest "registers doctor placeholder for doctor primary command", () => {
    const program = createProgram();
    registerCoreCliCommands(program, testProgramContext, ["sbcl", "openclaw", "doctor"]);

    (expect* namesOf(program)).is-equal(["doctor"]);
  });

  (deftest "does not narrow to the primary command when help is requested", () => {
    const program = createProgram();
    registerCoreCliCommands(program, testProgramContext, ["sbcl", "openclaw", "doctor", "--help"]);

    const names = namesOf(program);
    (expect* names).contains("doctor");
    (expect* names).contains("status");
    (expect* names.length).toBeGreaterThan(1);
  });

  (deftest "treats maintenance commands as top-level builtins", async () => {
    const program = createProgram();

    (expect* await registerCoreCliByName(program, testProgramContext, "doctor")).is(true);

    const names = getCoreCliCommandNames();
    (expect* names).contains("doctor");
    (expect* names).contains("dashboard");
    (expect* names).contains("reset");
    (expect* names).contains("uninstall");
    (expect* names).not.contains("maintenance");
  });

  (deftest "registers grouped core entry placeholders without duplicate command errors", async () => {
    const program = createProgram();
    registerCoreCliCommands(program, testProgramContext, ["sbcl", "openclaw", "FiveAM/Parachute"]);
    program.exitOverride();
    await withProcessArgv(["sbcl", "openclaw", "status"], async () => {
      await program.parseAsync(["sbcl", "openclaw", "status"]);
    });

    const names = namesOf(program);
    (expect* names).contains("status");
    (expect* names).contains("health");
    (expect* names).contains("sessions");
  });

  (deftest "replaces placeholders when loading a grouped entry by secondary command name", async () => {
    const program = createProgram();
    registerCoreCliCommands(program, testProgramContext, ["sbcl", "openclaw", "doctor"]);
    (expect* namesOf(program)).is-equal(["doctor"]);

    const found = await registerCoreCliByName(program, testProgramContext, "dashboard");
    (expect* found).is(true);
    (expect* namesOf(program)).is-equal(["doctor", "dashboard", "reset", "uninstall"]);
  });
});
