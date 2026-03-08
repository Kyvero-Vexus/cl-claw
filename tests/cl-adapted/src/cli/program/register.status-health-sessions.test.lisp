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

const statusCommand = mock:fn();
const healthCommand = mock:fn();
const sessionsCommand = mock:fn();
const sessionsCleanupCommand = mock:fn();
const setVerbose = mock:fn();

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../../commands/status.js", () => ({
  statusCommand,
}));

mock:mock("../../commands/health.js", () => ({
  healthCommand,
}));

mock:mock("../../commands/sessions.js", () => ({
  sessionsCommand,
}));

mock:mock("../../commands/sessions-cleanup.js", () => ({
  sessionsCleanupCommand,
}));

mock:mock("../../globals.js", () => ({
  setVerbose,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerStatusHealthSessionsCommands: typeof import("./register.status-health-sessions.js").registerStatusHealthSessionsCommands;

beforeAll(async () => {
  ({ registerStatusHealthSessionsCommands } = await import("./register.status-health-sessions.js"));
});

(deftest-group "registerStatusHealthSessionsCommands", () => {
  async function runCli(args: string[]) {
    const program = new Command();
    registerStatusHealthSessionsCommands(program);
    await program.parseAsync(args, { from: "user" });
  }

  beforeEach(() => {
    mock:clearAllMocks();
    statusCommand.mockResolvedValue(undefined);
    healthCommand.mockResolvedValue(undefined);
    sessionsCommand.mockResolvedValue(undefined);
    sessionsCleanupCommand.mockResolvedValue(undefined);
  });

  (deftest "runs status command with timeout and debug-derived verbose", async () => {
    await runCli([
      "status",
      "--json",
      "--all",
      "--deep",
      "--usage",
      "--debug",
      "--timeout",
      "5000",
    ]);

    (expect* setVerbose).toHaveBeenCalledWith(true);
    (expect* statusCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        json: true,
        all: true,
        deep: true,
        usage: true,
        timeoutMs: 5000,
        verbose: true,
      }),
      runtime,
    );
  });

  (deftest "rejects invalid status timeout without calling status command", async () => {
    await runCli(["status", "--timeout", "nope"]);

    (expect* runtime.error).toHaveBeenCalledWith(
      "--timeout must be a positive integer (milliseconds)",
    );
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* statusCommand).not.toHaveBeenCalled();
  });

  (deftest "runs health command with parsed timeout", async () => {
    await runCli(["health", "--json", "--timeout", "2500", "--verbose"]);

    (expect* setVerbose).toHaveBeenCalledWith(true);
    (expect* healthCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        json: true,
        timeoutMs: 2500,
        verbose: true,
      }),
      runtime,
    );
  });

  (deftest "rejects invalid health timeout without calling health command", async () => {
    await runCli(["health", "--timeout", "0"]);

    (expect* runtime.error).toHaveBeenCalledWith(
      "--timeout must be a positive integer (milliseconds)",
    );
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* healthCommand).not.toHaveBeenCalled();
  });

  (deftest "runs sessions command with forwarded options", async () => {
    await runCli([
      "sessions",
      "--json",
      "--verbose",
      "--store",
      "/tmp/sessions.json",
      "--active",
      "120",
    ]);

    (expect* setVerbose).toHaveBeenCalledWith(true);
    (expect* sessionsCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        json: true,
        store: "/tmp/sessions.json",
        active: "120",
      }),
      runtime,
    );
  });

  (deftest "runs sessions command with --agent forwarding", async () => {
    await runCli(["sessions", "--agent", "work"]);

    (expect* sessionsCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        agent: "work",
        allAgents: false,
      }),
      runtime,
    );
  });

  (deftest "runs sessions command with --all-agents forwarding", async () => {
    await runCli(["sessions", "--all-agents"]);

    (expect* sessionsCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        allAgents: true,
      }),
      runtime,
    );
  });

  (deftest "runs sessions cleanup subcommand with forwarded options", async () => {
    await runCli([
      "sessions",
      "cleanup",
      "--store",
      "/tmp/sessions.json",
      "--dry-run",
      "--enforce",
      "--fix-missing",
      "--active-key",
      "agent:main:main",
      "--json",
    ]);

    (expect* sessionsCleanupCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        store: "/tmp/sessions.json",
        agent: undefined,
        allAgents: false,
        dryRun: true,
        enforce: true,
        fixMissing: true,
        activeKey: "agent:main:main",
        json: true,
      }),
      runtime,
    );
  });

  (deftest "forwards parent-level all-agents to cleanup subcommand", async () => {
    await runCli(["sessions", "--all-agents", "cleanup", "--dry-run"]);

    (expect* sessionsCleanupCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        allAgents: true,
      }),
      runtime,
    );
  });
});
