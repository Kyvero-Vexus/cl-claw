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
import { getSlashCommands, helpText, parseCommand } from "./commands.js";

(deftest-group "parseCommand", () => {
  (deftest "normalizes aliases and keeps command args", () => {
    (expect* parseCommand("/elev full")).is-equal({ name: "elevated", args: "full" });
  });

  (deftest "returns empty name for empty input", () => {
    (expect* parseCommand("   ")).is-equal({ name: "", args: "" });
  });
});

(deftest-group "getSlashCommands", () => {
  (deftest "provides level completions for built-in toggles", () => {
    const commands = getSlashCommands();
    const verbose = commands.find((command) => command.name === "verbose");
    const activation = commands.find((command) => command.name === "activation");
    (expect* verbose?.getArgumentCompletions?.("o")).is-equal([
      { value: "on", label: "on" },
      { value: "off", label: "off" },
    ]);
    (expect* activation?.getArgumentCompletions?.("a")).is-equal([
      { value: "always", label: "always" },
    ]);
  });
});

(deftest-group "helpText", () => {
  (deftest "includes slash command help for aliases", () => {
    const output = helpText();
    (expect* output).contains("/elevated <on|off|ask|full>");
    (expect* output).contains("/elev <on|off|ask|full>");
  });
});
