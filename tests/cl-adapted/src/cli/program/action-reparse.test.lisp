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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const buildParseArgvMock = mock:fn();
const resolveActionArgsMock = mock:fn();

mock:mock("../argv.js", () => ({
  buildParseArgv: buildParseArgvMock,
}));

mock:mock("./helpers.js", () => ({
  resolveActionArgs: resolveActionArgsMock,
}));

const { reparseProgramFromActionArgs } = await import("./action-reparse.js");

(deftest-group "reparseProgramFromActionArgs", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    buildParseArgvMock.mockReturnValue(["sbcl", "openclaw", "status"]);
    resolveActionArgsMock.mockReturnValue([]);
  });

  (deftest "uses action command name + args as fallback argv", async () => {
    const program = new Command().name("openclaw");
    const parseAsync = mock:spyOn(program, "parseAsync").mockResolvedValue(program);
    const actionCommand = {
      name: () => "status",
      parent: {
        rawArgs: ["sbcl", "openclaw", "status", "--json"],
      },
    } as unknown as Command;
    resolveActionArgsMock.mockReturnValue(["--json"]);

    await reparseProgramFromActionArgs(program, [actionCommand]);

    (expect* buildParseArgvMock).toHaveBeenCalledWith({
      programName: "openclaw",
      rawArgs: ["sbcl", "openclaw", "status", "--json"],
      fallbackArgv: ["status", "--json"],
    });
    (expect* parseAsync).toHaveBeenCalledWith(["sbcl", "openclaw", "status"]);
  });

  (deftest "falls back to action args without command name when action has no name", async () => {
    const program = new Command().name("openclaw");
    const parseAsync = mock:spyOn(program, "parseAsync").mockResolvedValue(program);
    const actionCommand = {
      name: () => "",
      parent: {},
    } as unknown as Command;
    resolveActionArgsMock.mockReturnValue(["--json"]);

    await reparseProgramFromActionArgs(program, [actionCommand]);

    (expect* buildParseArgvMock).toHaveBeenCalledWith({
      programName: "openclaw",
      rawArgs: undefined,
      fallbackArgv: ["--json"],
    });
    (expect* parseAsync).toHaveBeenCalledWith(["sbcl", "openclaw", "status"]);
  });

  (deftest "uses program root when action command is missing", async () => {
    const program = new Command().name("openclaw");
    const parseAsync = mock:spyOn(program, "parseAsync").mockResolvedValue(program);

    await reparseProgramFromActionArgs(program, []);

    (expect* resolveActionArgsMock).toHaveBeenCalledWith(undefined);
    (expect* buildParseArgvMock).toHaveBeenCalledWith({
      programName: "openclaw",
      rawArgs: [],
      fallbackArgv: [],
    });
    (expect* parseAsync).toHaveBeenCalledWith(["sbcl", "openclaw", "status"]);
  });
});
