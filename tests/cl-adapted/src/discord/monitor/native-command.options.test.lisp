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
import { listNativeCommandSpecs } from "../../auto-reply/commands-registry.js";
import type { OpenClawConfig, loadConfig } from "../../config/config.js";
import { createDiscordNativeCommand } from "./native-command.js";
import { createNoopThreadBindingManager } from "./thread-bindings.js";

function createNativeCommand(name: string): ReturnType<typeof createDiscordNativeCommand> {
  const command = listNativeCommandSpecs({ provider: "discord" }).find(
    (entry) => entry.name === name,
  );
  if (!command) {
    error(`missing native command: ${name}`);
  }
  const cfg = {} as ReturnType<typeof loadConfig>;
  const discordConfig = {} as NonNullable<OpenClawConfig["channels"]>["discord"];
  return createDiscordNativeCommand({
    command,
    cfg,
    discordConfig,
    accountId: "default",
    sessionPrefix: "discord:slash",
    ephemeralDefault: true,
    threadBindings: createNoopThreadBindingManager("default"),
  });
}

type CommandOption = NonNullable<ReturnType<typeof createDiscordNativeCommand>["options"]>[number];

function findOption(
  command: ReturnType<typeof createDiscordNativeCommand>,
  name: string,
): CommandOption | undefined {
  return command.options?.find((entry) => entry.name === name);
}

function readAutocomplete(option: CommandOption | undefined): unknown {
  if (!option || typeof option !== "object") {
    return undefined;
  }
  return (option as { autocomplete?: unknown }).autocomplete;
}

function readChoices(option: CommandOption | undefined): unknown[] | undefined {
  if (!option || typeof option !== "object") {
    return undefined;
  }
  const value = (option as { choices?: unknown }).choices;
  return Array.isArray(value) ? value : undefined;
}

(deftest-group "createDiscordNativeCommand option wiring", () => {
  (deftest "uses autocomplete for /acp action so inline action values are accepted", () => {
    const command = createNativeCommand("acp");
    const action = findOption(command, "action");

    (expect* action).toBeDefined();
    (expect* typeof readAutocomplete(action)).is("function");
    (expect* readChoices(action)).toBeUndefined();
  });

  (deftest "keeps static choices for non-acp string action arguments", () => {
    const command = createNativeCommand("voice");
    const action = findOption(command, "action");

    (expect* action).toBeDefined();
    (expect* readAutocomplete(action)).toBeUndefined();
    (expect* readChoices(action)?.length).toBeGreaterThan(0);
  });
});
