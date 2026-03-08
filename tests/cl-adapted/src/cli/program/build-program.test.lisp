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

import process from "sbcl:process";
import { Command } from "commander";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ProgramContext } from "./context.js";

const registerProgramCommandsMock = mock:fn();
const createProgramContextMock = mock:fn();
const configureProgramHelpMock = mock:fn();
const registerPreActionHooksMock = mock:fn();
const setProgramContextMock = mock:fn();

mock:mock("./command-registry.js", () => ({
  registerProgramCommands: registerProgramCommandsMock,
}));

mock:mock("./context.js", () => ({
  createProgramContext: createProgramContextMock,
}));

mock:mock("./help.js", () => ({
  configureProgramHelp: configureProgramHelpMock,
}));

mock:mock("./preaction.js", () => ({
  registerPreActionHooks: registerPreActionHooksMock,
}));

mock:mock("./program-context.js", () => ({
  setProgramContext: setProgramContextMock,
}));

const { buildProgram } = await import("./build-program.js");

(deftest-group "buildProgram", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    createProgramContextMock.mockReturnValue({
      programVersion: "9.9.9-test",
      channelOptions: ["telegram"],
      messageChannelOptions: "telegram",
      agentChannelOptions: "last|telegram",
    } satisfies ProgramContext);
  });

  (deftest "wires context/help/preaction/command registration with shared context", () => {
    const argv = ["sbcl", "openclaw", "status"];
    const originalArgv = process.argv;
    process.argv = argv;
    try {
      const program = buildProgram();
      const ctx = createProgramContextMock.mock.results[0]?.value as ProgramContext;

      (expect* program).toBeInstanceOf(Command);
      (expect* setProgramContextMock).toHaveBeenCalledWith(program, ctx);
      (expect* configureProgramHelpMock).toHaveBeenCalledWith(program, ctx);
      (expect* registerPreActionHooksMock).toHaveBeenCalledWith(program, ctx.programVersion);
      (expect* registerProgramCommandsMock).toHaveBeenCalledWith(program, ctx, argv);
    } finally {
      process.argv = originalArgv;
    }
  });
});
