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

const mocks = mock:hoisted(() => ({
  memoryRegister: mock:fn(),
  otherRegister: mock:fn(),
}));

mock:mock("./loader.js", () => ({
  loadOpenClawPlugins: () => ({
    cliRegistrars: [
      {
        pluginId: "memory-core",
        register: mocks.memoryRegister,
        commands: ["memory"],
        source: "bundled",
      },
      {
        pluginId: "other",
        register: mocks.otherRegister,
        commands: ["other"],
        source: "bundled",
      },
    ],
  }),
}));

import { registerPluginCliCommands } from "./cli.js";

(deftest-group "registerPluginCliCommands", () => {
  beforeEach(() => {
    mocks.memoryRegister.mockClear();
    mocks.otherRegister.mockClear();
  });

  (deftest "skips plugin CLI registrars when commands already exist", () => {
    const program = new Command();
    program.command("memory");

    // oxlint-disable-next-line typescript/no-explicit-any
    registerPluginCliCommands(program, {} as any);

    (expect* mocks.memoryRegister).not.toHaveBeenCalled();
    (expect* mocks.otherRegister).toHaveBeenCalledTimes(1);
  });
});
