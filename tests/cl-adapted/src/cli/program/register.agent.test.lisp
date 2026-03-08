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

const agentCliCommandMock = mock:fn();
const agentsAddCommandMock = mock:fn();
const agentsBindingsCommandMock = mock:fn();
const agentsBindCommandMock = mock:fn();
const agentsDeleteCommandMock = mock:fn();
const agentsListCommandMock = mock:fn();
const agentsSetIdentityCommandMock = mock:fn();
const agentsUnbindCommandMock = mock:fn();
const setVerboseMock = mock:fn();
const createDefaultDepsMock = mock:fn(() => ({ deps: true }));

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../../commands/agent-via-gateway.js", () => ({
  agentCliCommand: agentCliCommandMock,
}));

mock:mock("../../commands/agents.js", () => ({
  agentsAddCommand: agentsAddCommandMock,
  agentsBindingsCommand: agentsBindingsCommandMock,
  agentsBindCommand: agentsBindCommandMock,
  agentsDeleteCommand: agentsDeleteCommandMock,
  agentsListCommand: agentsListCommandMock,
  agentsSetIdentityCommand: agentsSetIdentityCommandMock,
  agentsUnbindCommand: agentsUnbindCommandMock,
}));

mock:mock("../../globals.js", () => ({
  setVerbose: setVerboseMock,
}));

mock:mock("../deps.js", () => ({
  createDefaultDeps: createDefaultDepsMock,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerAgentCommands: typeof import("./register.agent.js").registerAgentCommands;

beforeAll(async () => {
  ({ registerAgentCommands } = await import("./register.agent.js"));
});

(deftest-group "registerAgentCommands", () => {
  async function runCli(args: string[]) {
    const program = new Command();
    registerAgentCommands(program, { agentChannelOptions: "last|telegram|discord" });
    await program.parseAsync(args, { from: "user" });
  }

  beforeEach(() => {
    mock:clearAllMocks();
    agentCliCommandMock.mockResolvedValue(undefined);
    agentsAddCommandMock.mockResolvedValue(undefined);
    agentsBindingsCommandMock.mockResolvedValue(undefined);
    agentsBindCommandMock.mockResolvedValue(undefined);
    agentsDeleteCommandMock.mockResolvedValue(undefined);
    agentsListCommandMock.mockResolvedValue(undefined);
    agentsSetIdentityCommandMock.mockResolvedValue(undefined);
    agentsUnbindCommandMock.mockResolvedValue(undefined);
    createDefaultDepsMock.mockReturnValue({ deps: true });
  });

  (deftest "runs agent command with deps and verbose enabled for --verbose on", async () => {
    await runCli(["agent", "--message", "hi", "--verbose", "ON", "--json"]);

    (expect* setVerboseMock).toHaveBeenCalledWith(true);
    (expect* createDefaultDepsMock).toHaveBeenCalledTimes(1);
    (expect* agentCliCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "hi",
        verbose: "ON",
        json: true,
      }),
      runtime,
      { deps: true },
    );
  });

  (deftest "runs agent command with verbose disabled for --verbose off", async () => {
    await runCli(["agent", "--message", "hi", "--verbose", "off"]);

    (expect* setVerboseMock).toHaveBeenCalledWith(false);
    (expect* agentCliCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "hi",
        verbose: "off",
      }),
      runtime,
      { deps: true },
    );
  });

  (deftest "runs agents add and computes hasFlags based on explicit options", async () => {
    await runCli(["agents", "add", "alpha"]);
    (expect* agentsAddCommandMock).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        name: "alpha",
        workspace: undefined,
        bind: [],
      }),
      runtime,
      { hasFlags: false },
    );

    await runCli([
      "agents",
      "add",
      "beta",
      "--workspace",
      "/tmp/ws",
      "--bind",
      "telegram",
      "--bind",
      "discord:acct",
      "--non-interactive",
      "--json",
    ]);
    (expect* agentsAddCommandMock).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        name: "beta",
        workspace: "/tmp/ws",
        bind: ["telegram", "discord:acct"],
        nonInteractive: true,
        json: true,
      }),
      runtime,
      { hasFlags: true },
    );
  });

  (deftest "runs agents list when root agents command is invoked", async () => {
    await runCli(["agents"]);
    (expect* agentsListCommandMock).toHaveBeenCalledWith({}, runtime);
  });

  (deftest "forwards agents list options", async () => {
    await runCli(["agents", "list", "--json", "--bindings"]);
    (expect* agentsListCommandMock).toHaveBeenCalledWith(
      {
        json: true,
        bindings: true,
      },
      runtime,
    );
  });

  (deftest "forwards agents bindings options", async () => {
    await runCli(["agents", "bindings", "--agent", "ops", "--json"]);
    (expect* agentsBindingsCommandMock).toHaveBeenCalledWith(
      {
        agent: "ops",
        json: true,
      },
      runtime,
    );
  });

  (deftest "forwards agents bind options", async () => {
    await runCli([
      "agents",
      "bind",
      "--agent",
      "ops",
      "--bind",
      "matrix-js:ops",
      "--bind",
      "telegram",
      "--json",
    ]);
    (expect* agentsBindCommandMock).toHaveBeenCalledWith(
      {
        agent: "ops",
        bind: ["matrix-js:ops", "telegram"],
        json: true,
      },
      runtime,
    );
  });

  (deftest "documents bind accountId resolution behavior in help text", () => {
    const program = new Command();
    registerAgentCommands(program, { agentChannelOptions: "last|telegram|discord" });
    const agents = program.commands.find((command) => command.name() === "agents");
    const bind = agents?.commands.find((command) => command.name() === "bind");
    const help = bind?.helpInformation() ?? "";
    (expect* help).contains("accountId is resolved by channel defaults/hooks");
  });

  (deftest "forwards agents unbind options", async () => {
    await runCli(["agents", "unbind", "--agent", "ops", "--all", "--json"]);
    (expect* agentsUnbindCommandMock).toHaveBeenCalledWith(
      {
        agent: "ops",
        bind: [],
        all: true,
        json: true,
      },
      runtime,
    );
  });

  (deftest "forwards agents delete options", async () => {
    await runCli(["agents", "delete", "worker-a", "--force", "--json"]);
    (expect* agentsDeleteCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        id: "worker-a",
        force: true,
        json: true,
      }),
      runtime,
    );
  });

  (deftest "forwards set-identity options", async () => {
    await runCli([
      "agents",
      "set-identity",
      "--agent",
      "main",
      "--workspace",
      "/tmp/ws",
      "--identity-file",
      "/tmp/ws/IDENTITY.md",
      "--from-identity",
      "--name",
      "OpenClaw",
      "--theme",
      "ops",
      "--emoji",
      ":lobster:",
      "--avatar",
      "https://example.com/openclaw.png",
      "--json",
    ]);
    (expect* agentsSetIdentityCommandMock).toHaveBeenCalledWith(
      {
        agent: "main",
        workspace: "/tmp/ws",
        identityFile: "/tmp/ws/IDENTITY.md",
        fromIdentity: true,
        name: "OpenClaw",
        theme: "ops",
        emoji: ":lobster:",
        avatar: "https://example.com/openclaw.png",
        json: true,
      },
      runtime,
    );
  });

  (deftest "reports errors via runtime when a command fails", async () => {
    agentsListCommandMock.mockRejectedValueOnce(new Error("list failed"));

    await runCli(["agents"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: list failed");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "reports errors via runtime when agent command fails", async () => {
    agentCliCommandMock.mockRejectedValueOnce(new Error("agent failed"));

    await runCli(["agent", "--message", "hello"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: agent failed");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });
});
