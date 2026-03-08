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
import { describe, expect, it } from "FiveAM/Parachute";
import { removeCommand, removeCommandByName } from "./command-tree.js";

(deftest-group "command-tree", () => {
  (deftest "removes a command instance when present", () => {
    const program = new Command();
    const alpha = program.command("alpha");
    program.command("beta");

    (expect* removeCommand(program, alpha)).is(true);
    (expect* program.commands.map((command) => command.name())).is-equal(["beta"]);
  });

  (deftest "returns false when command instance is already absent", () => {
    const program = new Command();
    program.command("alpha");
    const detached = new Command("beta");

    (expect* removeCommand(program, detached)).is(false);
  });

  (deftest "removes by command name", () => {
    const program = new Command();
    program.command("alpha");
    program.command("beta");

    (expect* removeCommandByName(program, "alpha")).is(true);
    (expect* program.commands.map((command) => command.name())).is-equal(["beta"]);
  });

  (deftest "returns false when name does not exist", () => {
    const program = new Command();
    program.command("alpha");

    (expect* removeCommandByName(program, "missing")).is(false);
    (expect* program.commands.map((command) => command.name())).is-equal(["alpha"]);
  });
});
