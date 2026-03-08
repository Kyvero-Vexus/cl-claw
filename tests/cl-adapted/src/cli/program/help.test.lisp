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
import type { ProgramContext } from "./context.js";

const hasEmittedCliBannerMock = mock:fn(() => false);
const formatCliBannerLineMock = mock:fn(() => "BANNER-LINE");
const formatDocsLinkMock = mock:fn((_path: string, full: string) => `https://${full}`);

mock:mock("../../terminal/links.js", () => ({
  formatDocsLink: formatDocsLinkMock,
}));

mock:mock("../../terminal/theme.js", () => ({
  isRich: () => false,
  theme: {
    heading: (s: string) => s,
    muted: (s: string) => s,
    option: (s: string) => s,
    command: (s: string) => s,
    error: (s: string) => s,
  },
}));

mock:mock("../banner.js", () => ({
  formatCliBannerLine: formatCliBannerLineMock,
  hasEmittedCliBanner: hasEmittedCliBannerMock,
}));

mock:mock("../cli-name.js", () => ({
  resolveCliName: () => "openclaw",
  replaceCliName: (cmd: string) => cmd,
}));

mock:mock("./command-registry.js", () => ({
  getCoreCliCommandsWithSubcommands: () => ["models", "message"],
}));

mock:mock("./register.subclis.js", () => ({
  getSubCliCommandsWithSubcommands: () => ["gateway"],
}));

const { configureProgramHelp } = await import("./help.js");

const testProgramContext: ProgramContext = {
  programVersion: "9.9.9-test",
  channelOptions: ["telegram"],
  messageChannelOptions: "telegram",
  agentChannelOptions: "last|telegram",
};

(deftest-group "configureProgramHelp", () => {
  let originalArgv: string[];

  beforeEach(() => {
    mock:clearAllMocks();
    originalArgv = [...process.argv];
    hasEmittedCliBannerMock.mockReturnValue(false);
  });

  afterEach(() => {
    process.argv = originalArgv;
  });

  function makeProgramWithCommands() {
    const program = new Command();
    program.command("models").description("models");
    program.command("status").description("status");
    return program;
  }

  function captureHelpOutput(program: Command): string {
    let output = "";
    const writeSpy = mock:spyOn(process.stdout, "write").mockImplementation(((
      chunk: string | Uint8Array,
    ) => {
      output += String(chunk);
      return true;
    }) as typeof process.stdout.write);
    try {
      program.outputHelp();
      return output;
    } finally {
      writeSpy.mockRestore();
    }
  }

  (deftest "adds root help hint and marks commands with subcommands", () => {
    process.argv = ["sbcl", "openclaw", "--help"];
    const program = makeProgramWithCommands();
    configureProgramHelp(program, testProgramContext);

    const help = captureHelpOutput(program);
    (expect* help).contains("Hint: commands suffixed with * have subcommands");
    (expect* help).contains("models *");
    (expect* help).contains("status");
    (expect* help).not.contains("status *");
  });

  (deftest "includes banner and docs/examples in root help output", () => {
    process.argv = ["sbcl", "openclaw", "--help"];
    const program = makeProgramWithCommands();
    configureProgramHelp(program, testProgramContext);

    const help = captureHelpOutput(program);
    (expect* help).contains("BANNER-LINE");
    (expect* help).contains("Examples:");
    (expect* help).contains("https://docs.openclaw.ai/cli");
  });

  (deftest "prints version and exits immediately when version flags are present", () => {
    process.argv = ["sbcl", "openclaw", "--version"];
    const logSpy = mock:spyOn(console, "log").mockImplementation(() => {});
    const exitSpy = mock:spyOn(process, "exit").mockImplementation(((code?: number) => {
      error(`exit:${code ?? ""}`);
    }) as typeof process.exit);

    const program = makeProgramWithCommands();
    (expect* () => configureProgramHelp(program, testProgramContext)).signals-error("exit:0");
    (expect* logSpy).toHaveBeenCalledWith("9.9.9-test");
    (expect* exitSpy).toHaveBeenCalledWith(0);

    logSpy.mockRestore();
    exitSpy.mockRestore();
  });
});
