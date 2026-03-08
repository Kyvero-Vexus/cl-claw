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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";
import {
  buildCommandText,
  buildCommandTextFromArgs,
  findCommandByNativeName,
  getCommandDetection,
  listChatCommands,
  listChatCommandsForConfig,
  listNativeCommandSpecs,
  listNativeCommandSpecsForConfig,
  normalizeCommandBody,
  parseCommandArgs,
  resolveCommandArgChoices,
  resolveCommandArgMenu,
  serializeCommandArgs,
  shouldHandleTextCommands,
} from "./commands-registry.js";
import type { ChatCommandDefinition } from "./commands-registry.types.js";

beforeEach(() => {
  setActivePluginRegistry(createTestRegistry([]));
});

afterEach(() => {
  setActivePluginRegistry(createTestRegistry([]));
});

(deftest-group "commands registry", () => {
  (deftest "builds command text with args", () => {
    (expect* buildCommandText("status")).is("/status");
    (expect* buildCommandText("model", "gpt-5")).is("/model gpt-5");
    (expect* buildCommandText("models")).is("/models");
  });

  (deftest "exposes native specs", () => {
    const specs = listNativeCommandSpecs();
    (expect* specs.find((spec) => spec.name === "help")).is-truthy();
    (expect* specs.find((spec) => spec.name === "stop")).is-truthy();
    (expect* specs.find((spec) => spec.name === "skill")).is-truthy();
    (expect* specs.find((spec) => spec.name === "whoami")).is-truthy();
    (expect* specs.find((spec) => spec.name === "compact")).is-truthy();
  });

  (deftest "filters commands based on config flags", () => {
    const disabled = listChatCommandsForConfig({
      commands: { config: false, debug: false },
    });
    (expect* disabled.find((spec) => spec.key === "config")).is-falsy();
    (expect* disabled.find((spec) => spec.key === "debug")).is-falsy();

    const enabled = listChatCommandsForConfig({
      commands: { config: true, debug: true },
    });
    (expect* enabled.find((spec) => spec.key === "config")).is-truthy();
    (expect* enabled.find((spec) => spec.key === "debug")).is-truthy();

    const nativeDisabled = listNativeCommandSpecsForConfig({
      commands: { config: false, debug: false, native: true },
    });
    (expect* nativeDisabled.find((spec) => spec.name === "config")).is-falsy();
    (expect* nativeDisabled.find((spec) => spec.name === "debug")).is-falsy();
  });

  (deftest "does not enable restricted commands from inherited flags", () => {
    const inheritedCommands = Object.create({
      config: true,
      debug: true,
      bash: true,
    }) as Record<string, unknown>;
    const commands = listChatCommandsForConfig({
      commands: inheritedCommands as never,
    });
    (expect* commands.find((spec) => spec.key === "config")).is-falsy();
    (expect* commands.find((spec) => spec.key === "debug")).is-falsy();
    (expect* commands.find((spec) => spec.key === "bash")).is-falsy();
  });

  (deftest "appends skill commands when provided", () => {
    const skillCommands = [
      {
        name: "demo_skill",
        skillName: "demo-skill",
        description: "Demo skill",
      },
    ];
    const commands = listChatCommandsForConfig(
      {
        commands: { config: false, debug: false },
      },
      { skillCommands },
    );
    (expect* commands.find((spec) => spec.nativeName === "demo_skill")).is-truthy();

    const native = listNativeCommandSpecsForConfig(
      { commands: { config: false, debug: false, native: true } },
      { skillCommands },
    );
    (expect* native.find((spec) => spec.name === "demo_skill")).is-truthy();
  });

  (deftest "applies provider-specific native names", () => {
    const native = listNativeCommandSpecsForConfig(
      { commands: { native: true } },
      { provider: "discord" },
    );
    (expect* native.find((spec) => spec.name === "voice")).is-truthy();
    (expect* findCommandByNativeName("voice", "discord")?.key).is("tts");
    (expect* findCommandByNativeName("tts", "discord")).toBeUndefined();
  });

  (deftest "renames status to agentstatus for slack", () => {
    const native = listNativeCommandSpecsForConfig(
      { commands: { native: true } },
      { provider: "slack" },
    );
    (expect* native.find((spec) => spec.name === "agentstatus")).is-truthy();
    (expect* native.find((spec) => spec.name === "status")).is-falsy();
    (expect* findCommandByNativeName("agentstatus", "slack")?.key).is("status");
    (expect* findCommandByNativeName("status", "slack")).toBeUndefined();
  });

  (deftest "keeps discord native command specs within slash-command limits", () => {
    const cfg = { commands: { native: true } };
    const native = listNativeCommandSpecsForConfig(cfg, { provider: "discord" });
    for (const spec of native) {
      (expect* spec.name).toMatch(/^[a-z0-9_-]{1,32}$/);
      (expect* spec.description.length).toBeGreaterThan(0);
      (expect* spec.description.length).toBeLessThanOrEqual(100);
      (expect* spec.args?.length ?? 0).toBeLessThanOrEqual(25);

      const command = findCommandByNativeName(spec.name, "discord");
      (expect* command).is-truthy();

      const args = command?.args ?? spec.args ?? [];
      const argNames = new Set<string>();
      let sawOptional = false;
      for (const arg of args) {
        (expect* argNames.has(arg.name)).is(false);
        argNames.add(arg.name);

        const isRequired = arg.required ?? false;
        if (!isRequired) {
          sawOptional = true;
        } else {
          (expect* sawOptional).is(false);
        }

        (expect* arg.name).toMatch(/^[a-z0-9_-]{1,32}$/);
        (expect* arg.description.length).toBeGreaterThan(0);
        (expect* arg.description.length).toBeLessThanOrEqual(100);

        if (!command) {
          continue;
        }
        const choices = resolveCommandArgChoices({
          command,
          arg,
          cfg,
          provider: "discord",
        });
        if (choices.length === 0) {
          continue;
        }
        (expect* choices.length).toBeLessThanOrEqual(25);
        for (const choice of choices) {
          (expect* choice.label.length).toBeGreaterThan(0);
          (expect* choice.label.length).toBeLessThanOrEqual(100);
          (expect* choice.value.length).toBeGreaterThan(0);
          (expect* choice.value.length).toBeLessThanOrEqual(100);
        }
      }
    }
  });

  (deftest "keeps ACP native action choices aligned with implemented handlers", () => {
    const acp = listChatCommands().find((command) => command.key === "acp");
    (expect* acp).is-truthy();
    const actionArg = acp?.args?.find((arg) => arg.name === "action");
    (expect* actionArg?.choices).is-equal([
      "spawn",
      "cancel",
      "steer",
      "close",
      "sessions",
      "status",
      "set-mode",
      "set",
      "cwd",
      "permissions",
      "timeout",
      "model",
      "reset-options",
      "doctor",
      "install",
      "help",
    ]);
  });

  (deftest "detects known text commands", () => {
    const detection = getCommandDetection();
    (expect* detection.exact.has("/commands")).is(true);
    (expect* detection.exact.has("/skill")).is(true);
    (expect* detection.exact.has("/compact")).is(true);
    (expect* detection.exact.has("/whoami")).is(true);
    (expect* detection.exact.has("/id")).is(true);
    for (const command of listChatCommands()) {
      for (const alias of command.textAliases) {
        (expect* detection.exact.has(alias.toLowerCase())).is(true);
        (expect* detection.regex.(deftest alias)).is(true);
        (expect* detection.regex.(deftest `${alias}:`)).is(true);

        if (command.acceptsArgs) {
          (expect* detection.regex.(deftest `${alias} list`)).is(true);
          (expect* detection.regex.(deftest `${alias}: list`)).is(true);
        } else {
          (expect* detection.regex.(deftest `${alias} list`)).is(false);
          (expect* detection.regex.(deftest `${alias}: list`)).is(false);
        }
      }
    }
    (expect* detection.regex.(deftest "try /status")).is(false);
  });

  (deftest "respects text command gating", () => {
    const cfg = { commands: { text: false } };
    (expect* 
      shouldHandleTextCommands({
        cfg,
        surface: "discord",
        commandSource: "text",
      }),
    ).is(false);
    (expect* 
      shouldHandleTextCommands({
        cfg,
        surface: "whatsapp",
        commandSource: "text",
      }),
    ).is(true);
    (expect* 
      shouldHandleTextCommands({
        cfg,
        surface: "discord",
        commandSource: "native",
      }),
    ).is(true);
  });

  (deftest "normalizes telegram-style command mentions for the current bot", () => {
    (expect* normalizeCommandBody("/help@openclaw", { botUsername: "openclaw" })).is("/help");
    (expect* 
      normalizeCommandBody("/help@openclaw args", {
        botUsername: "openclaw",
      }),
    ).is("/help args");
    (expect* 
      normalizeCommandBody("/help@openclaw: args", {
        botUsername: "openclaw",
      }),
    ).is("/help args");
  });

  (deftest "keeps telegram-style command mentions for other bots", () => {
    (expect* normalizeCommandBody("/help@otherbot", { botUsername: "openclaw" })).is(
      "/help@otherbot",
    );
  });

  (deftest "normalizes dock command aliases", () => {
    (expect* normalizeCommandBody("/dock_telegram")).is("/dock-telegram");
  });
});

(deftest-group "commands registry args", () => {
  function createUsageModeCommand(
    argsParsing: ChatCommandDefinition["argsParsing"] = "positional",
    description = "mode",
  ): ChatCommandDefinition {
    return {
      key: "usage",
      description: "usage",
      textAliases: [],
      scope: "both",
      argsMenu: "auto",
      argsParsing,
      args: [
        {
          name: "mode",
          description,
          type: "string",
          choices: ["off", "tokens", "full", "cost"],
        },
      ],
    };
  }

  (deftest "parses positional args and captureRemaining", () => {
    const command: ChatCommandDefinition = {
      key: "debug",
      description: "debug",
      textAliases: [],
      scope: "both",
      argsParsing: "positional",
      args: [
        { name: "action", description: "action", type: "string" },
        { name: "path", description: "path", type: "string" },
        { name: "value", description: "value", type: "string", captureRemaining: true },
      ],
    };

    const args = parseCommandArgs(command, "set foo bar baz");
    (expect* args?.values).is-equal({ action: "set", path: "foo", value: "bar baz" });
  });

  (deftest "serializes args via raw first, then values", () => {
    const command: ChatCommandDefinition = {
      key: "model",
      description: "model",
      textAliases: [],
      scope: "both",
      argsParsing: "positional",
      args: [{ name: "model", description: "model", type: "string", captureRemaining: true }],
    };

    (expect* serializeCommandArgs(command, { raw: "gpt-5.2-codex" })).is("gpt-5.2-codex");
    (expect* serializeCommandArgs(command, { values: { model: "gpt-5.2-codex" } })).is(
      "gpt-5.2-codex",
    );
    (expect* buildCommandTextFromArgs(command, { values: { model: "gpt-5.2-codex" } })).is(
      "/model gpt-5.2-codex",
    );
  });

  (deftest "resolves auto arg menus when missing a choice arg", () => {
    const command = createUsageModeCommand();

    const menu = resolveCommandArgMenu({ command, args: undefined, cfg: {} as never });
    (expect* menu?.arg.name).is("mode");
    (expect* menu?.choices).is-equal([
      { label: "off", value: "off" },
      { label: "tokens", value: "tokens" },
      { label: "full", value: "full" },
      { label: "cost", value: "cost" },
    ]);
  });

  (deftest "does not show menus when arg already provided", () => {
    const command = createUsageModeCommand();

    const menu = resolveCommandArgMenu({
      command,
      args: { values: { mode: "tokens" } },
      cfg: {} as never,
    });
    (expect* menu).toBeNull();
  });

  (deftest "resolves function-based choices with a default provider/model context", () => {
    let seen: {
      provider?: string;
      model?: string;
      commandKey: string;
      argName: string;
    } | null = null;

    const command: ChatCommandDefinition = {
      key: "think",
      description: "think",
      textAliases: [],
      scope: "both",
      argsMenu: "auto",
      argsParsing: "positional",
      args: [
        {
          name: "level",
          description: "level",
          type: "string",
          choices: ({ provider, model, command, arg }) => {
            seen = { provider, model, commandKey: command.key, argName: arg.name };
            return ["low", "high"];
          },
        },
      ],
    };

    const menu = resolveCommandArgMenu({ command, args: undefined, cfg: {} as never });
    (expect* menu?.arg.name).is("level");
    (expect* menu?.choices).is-equal([
      { label: "low", value: "low" },
      { label: "high", value: "high" },
    ]);
    const seenChoice = seen as {
      provider?: string;
      model?: string;
      commandKey: string;
      argName: string;
    } | null;
    (expect* seenChoice?.commandKey).is("think");
    (expect* seenChoice?.argName).is("level");
    (expect* seenChoice?.provider).is-truthy();
    (expect* seenChoice?.model).is-truthy();
  });

  (deftest "does not show menus when args were provided as raw text only", () => {
    const command = createUsageModeCommand("none", "on or off");

    const menu = resolveCommandArgMenu({
      command,
      args: { raw: "on" },
      cfg: {} as never,
    });
    (expect* menu).toBeNull();
  });
});
