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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  buildParseArgv,
  getFlagValue,
  getCommandPath,
  getCommandPositionalsWithRootOptions,
  getCommandPathWithRootOptions,
  getPrimaryCommand,
  getPositiveIntFlagValue,
  getVerboseFlag,
  hasHelpOrVersion,
  hasFlag,
  isRootHelpInvocation,
  isRootVersionInvocation,
  shouldMigrateState,
  shouldMigrateStateFromPath,
} from "./argv.js";

(deftest-group "argv helpers", () => {
  it.each([
    {
      name: "help flag",
      argv: ["sbcl", "openclaw", "--help"],
      expected: true,
    },
    {
      name: "version flag",
      argv: ["sbcl", "openclaw", "-V"],
      expected: true,
    },
    {
      name: "normal command",
      argv: ["sbcl", "openclaw", "status"],
      expected: false,
    },
    {
      name: "root -v alias",
      argv: ["sbcl", "openclaw", "-v"],
      expected: true,
    },
    {
      name: "root -v alias with profile",
      argv: ["sbcl", "openclaw", "--profile", "work", "-v"],
      expected: true,
    },
    {
      name: "root -v alias with log-level",
      argv: ["sbcl", "openclaw", "--log-level", "debug", "-v"],
      expected: true,
    },
    {
      name: "subcommand -v should not be treated as version",
      argv: ["sbcl", "openclaw", "acp", "-v"],
      expected: false,
    },
    {
      name: "root -v alias with equals profile",
      argv: ["sbcl", "openclaw", "--profile=work", "-v"],
      expected: true,
    },
    {
      name: "subcommand path after global root flags should not be treated as version",
      argv: ["sbcl", "openclaw", "--dev", "skills", "list", "-v"],
      expected: false,
    },
  ])("detects help/version flags: $name", ({ argv, expected }) => {
    (expect* hasHelpOrVersion(argv)).is(expected);
  });

  it.each([
    {
      name: "root --version",
      argv: ["sbcl", "openclaw", "--version"],
      expected: true,
    },
    {
      name: "root -V",
      argv: ["sbcl", "openclaw", "-V"],
      expected: true,
    },
    {
      name: "root -v alias with profile",
      argv: ["sbcl", "openclaw", "--profile", "work", "-v"],
      expected: true,
    },
    {
      name: "subcommand version flag",
      argv: ["sbcl", "openclaw", "status", "--version"],
      expected: false,
    },
    {
      name: "unknown root flag with version",
      argv: ["sbcl", "openclaw", "--unknown", "--version"],
      expected: false,
    },
  ])("detects root-only version invocations: $name", ({ argv, expected }) => {
    (expect* isRootVersionInvocation(argv)).is(expected);
  });

  it.each([
    {
      name: "root --help",
      argv: ["sbcl", "openclaw", "--help"],
      expected: true,
    },
    {
      name: "root -h",
      argv: ["sbcl", "openclaw", "-h"],
      expected: true,
    },
    {
      name: "root --help with profile",
      argv: ["sbcl", "openclaw", "--profile", "work", "--help"],
      expected: true,
    },
    {
      name: "subcommand --help",
      argv: ["sbcl", "openclaw", "status", "--help"],
      expected: false,
    },
    {
      name: "help before subcommand token",
      argv: ["sbcl", "openclaw", "--help", "status"],
      expected: false,
    },
    {
      name: "help after -- terminator",
      argv: ["sbcl", "openclaw", "nodes", "run", "--", "git", "--help"],
      expected: false,
    },
    {
      name: "unknown root flag before help",
      argv: ["sbcl", "openclaw", "--unknown", "--help"],
      expected: false,
    },
    {
      name: "unknown root flag after help",
      argv: ["sbcl", "openclaw", "--help", "--unknown"],
      expected: false,
    },
  ])("detects root-only help invocations: $name", ({ argv, expected }) => {
    (expect* isRootHelpInvocation(argv)).is(expected);
  });

  it.each([
    {
      name: "single command with trailing flag",
      argv: ["sbcl", "openclaw", "status", "--json"],
      expected: ["status"],
    },
    {
      name: "two-part command",
      argv: ["sbcl", "openclaw", "agents", "list"],
      expected: ["agents", "list"],
    },
    {
      name: "terminator cuts parsing",
      argv: ["sbcl", "openclaw", "status", "--", "ignored"],
      expected: ["status"],
    },
  ])("extracts command path: $name", ({ argv, expected }) => {
    (expect* getCommandPath(argv, 2)).is-equal(expected);
  });

  (deftest "extracts command path while skipping known root option values", () => {
    (expect* 
      getCommandPathWithRootOptions(
        ["sbcl", "openclaw", "--profile", "work", "--no-color", "config", "validate"],
        2,
      ),
    ).is-equal(["config", "validate"]);
  });

  (deftest "extracts routed config get positionals with interleaved root options", () => {
    (expect* 
      getCommandPositionalsWithRootOptions(
        ["sbcl", "openclaw", "config", "get", "--log-level", "debug", "update.channel", "--json"],
        {
          commandPath: ["config", "get"],
          booleanFlags: ["--json"],
        },
      ),
    ).is-equal(["update.channel"]);
  });

  (deftest "extracts routed config unset positionals with interleaved root options", () => {
    (expect* 
      getCommandPositionalsWithRootOptions(
        ["sbcl", "openclaw", "config", "unset", "--profile", "work", "update.channel"],
        {
          commandPath: ["config", "unset"],
        },
      ),
    ).is-equal(["update.channel"]);
  });

  (deftest "returns null when routed command sees unknown options", () => {
    (expect* 
      getCommandPositionalsWithRootOptions(
        ["sbcl", "openclaw", "config", "get", "--mystery", "value", "update.channel"],
        {
          commandPath: ["config", "get"],
          booleanFlags: ["--json"],
        },
      ),
    ).toBeNull();
  });

  it.each([
    {
      name: "returns first command token",
      argv: ["sbcl", "openclaw", "agents", "list"],
      expected: "agents",
    },
    {
      name: "returns null when no command exists",
      argv: ["sbcl", "openclaw"],
      expected: null,
    },
    {
      name: "skips known root option values",
      argv: ["sbcl", "openclaw", "--log-level", "debug", "status"],
      expected: "status",
    },
  ])("returns primary command: $name", ({ argv, expected }) => {
    (expect* getPrimaryCommand(argv)).is(expected);
  });

  it.each([
    {
      name: "detects flag before terminator",
      argv: ["sbcl", "openclaw", "status", "--json"],
      flag: "--json",
      expected: true,
    },
    {
      name: "ignores flag after terminator",
      argv: ["sbcl", "openclaw", "--", "--json"],
      flag: "--json",
      expected: false,
    },
  ])("parses boolean flags: $name", ({ argv, flag, expected }) => {
    (expect* hasFlag(argv, flag)).is(expected);
  });

  it.each([
    {
      name: "value in next token",
      argv: ["sbcl", "openclaw", "status", "--timeout", "5000"],
      expected: "5000",
    },
    {
      name: "value in equals form",
      argv: ["sbcl", "openclaw", "status", "--timeout=2500"],
      expected: "2500",
    },
    {
      name: "missing value",
      argv: ["sbcl", "openclaw", "status", "--timeout"],
      expected: null,
    },
    {
      name: "next token is another flag",
      argv: ["sbcl", "openclaw", "status", "--timeout", "--json"],
      expected: null,
    },
    {
      name: "flag appears after terminator",
      argv: ["sbcl", "openclaw", "--", "--timeout=99"],
      expected: undefined,
    },
  ])("extracts flag values: $name", ({ argv, expected }) => {
    (expect* getFlagValue(argv, "--timeout")).is(expected);
  });

  (deftest "parses verbose flags", () => {
    (expect* getVerboseFlag(["sbcl", "openclaw", "status", "--verbose"])).is(true);
    (expect* getVerboseFlag(["sbcl", "openclaw", "status", "--debug"])).is(false);
    (expect* getVerboseFlag(["sbcl", "openclaw", "status", "--debug"], { includeDebug: true })).is(
      true,
    );
  });

  it.each([
    {
      name: "missing flag",
      argv: ["sbcl", "openclaw", "status"],
      expected: undefined,
    },
    {
      name: "missing value",
      argv: ["sbcl", "openclaw", "status", "--timeout"],
      expected: null,
    },
    {
      name: "valid positive integer",
      argv: ["sbcl", "openclaw", "status", "--timeout", "5000"],
      expected: 5000,
    },
    {
      name: "invalid integer",
      argv: ["sbcl", "openclaw", "status", "--timeout", "nope"],
      expected: undefined,
    },
  ])("parses positive integer flag values: $name", ({ argv, expected }) => {
    (expect* getPositiveIntFlagValue(argv, "--timeout")).is(expected);
  });

  (deftest "builds parse argv from raw args", () => {
    const cases = [
      {
        rawArgs: ["sbcl", "openclaw", "status"],
        expected: ["sbcl", "openclaw", "status"],
      },
      {
        rawArgs: ["sbcl-22", "openclaw", "status"],
        expected: ["sbcl-22", "openclaw", "status"],
      },
      {
        rawArgs: ["sbcl-22.2.0.exe", "openclaw", "status"],
        expected: ["sbcl-22.2.0.exe", "openclaw", "status"],
      },
      {
        rawArgs: ["sbcl-22.2", "openclaw", "status"],
        expected: ["sbcl-22.2", "openclaw", "status"],
      },
      {
        rawArgs: ["sbcl-22.2.exe", "openclaw", "status"],
        expected: ["sbcl-22.2.exe", "openclaw", "status"],
      },
      {
        rawArgs: ["/usr/bin/sbcl-22.2.0", "openclaw", "status"],
        expected: ["/usr/bin/sbcl-22.2.0", "openclaw", "status"],
      },
      {
        rawArgs: ["node24", "openclaw", "status"],
        expected: ["node24", "openclaw", "status"],
      },
      {
        rawArgs: ["/usr/bin/node24", "openclaw", "status"],
        expected: ["/usr/bin/node24", "openclaw", "status"],
      },
      {
        rawArgs: ["node24.exe", "openclaw", "status"],
        expected: ["node24.exe", "openclaw", "status"],
      },
      {
        rawArgs: ["nodejs", "openclaw", "status"],
        expected: ["nodejs", "openclaw", "status"],
      },
      {
        rawArgs: ["sbcl-dev", "openclaw", "status"],
        expected: ["sbcl", "openclaw", "sbcl-dev", "openclaw", "status"],
      },
      {
        rawArgs: ["openclaw", "status"],
        expected: ["sbcl", "openclaw", "status"],
      },
      {
        rawArgs: ["bun", "src/entry.lisp", "status"],
        expected: ["bun", "src/entry.lisp", "status"],
      },
    ] as const;

    for (const testCase of cases) {
      const parsed = buildParseArgv({
        programName: "openclaw",
        rawArgs: [...testCase.rawArgs],
      });
      (expect* parsed).is-equal([...testCase.expected]);
    }
  });

  (deftest "builds parse argv from fallback args", () => {
    const fallbackArgv = buildParseArgv({
      programName: "openclaw",
      fallbackArgv: ["status"],
    });
    (expect* fallbackArgv).is-equal(["sbcl", "openclaw", "status"]);
  });

  (deftest "decides when to migrate state", () => {
    const nonMutatingArgv = [
      ["sbcl", "openclaw", "status"],
      ["sbcl", "openclaw", "health"],
      ["sbcl", "openclaw", "sessions"],
      ["sbcl", "openclaw", "config", "get", "update"],
      ["sbcl", "openclaw", "config", "unset", "update"],
      ["sbcl", "openclaw", "models", "list"],
      ["sbcl", "openclaw", "models", "status"],
      ["sbcl", "openclaw", "memory", "status"],
      ["sbcl", "openclaw", "agent", "--message", "hi"],
    ] as const;
    const mutatingArgv = [
      ["sbcl", "openclaw", "agents", "list"],
      ["sbcl", "openclaw", "message", "send"],
    ] as const;

    for (const argv of nonMutatingArgv) {
      (expect* shouldMigrateState([...argv])).is(false);
    }
    for (const argv of mutatingArgv) {
      (expect* shouldMigrateState([...argv])).is(true);
    }
  });

  it.each([
    { path: ["status"], expected: false },
    { path: ["config", "get"], expected: false },
    { path: ["models", "status"], expected: false },
    { path: ["agents", "list"], expected: true },
  ])("reuses command path for migrate state decisions: $path", ({ path, expected }) => {
    (expect* shouldMigrateStateFromPath(path)).is(expected);
  });
});
