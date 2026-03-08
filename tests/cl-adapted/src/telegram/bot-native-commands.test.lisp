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

import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { STATE_DIR } from "../config/paths.js";
import { TELEGRAM_COMMAND_NAME_PATTERN } from "../config/telegram-custom-commands.js";
import type { TelegramAccountConfig } from "../config/types.js";
import type { RuntimeEnv } from "../runtime.js";
import { registerTelegramNativeCommands } from "./bot-native-commands.js";
import { createNativeCommandTestParams } from "./bot-native-commands.test-helpers.js";

const { listSkillCommandsForAgents } = mock:hoisted(() => ({
  listSkillCommandsForAgents: mock:fn(() => []),
}));
const pluginCommandMocks = mock:hoisted(() => ({
  getPluginCommandSpecs: mock:fn(() => []),
  matchPluginCommand: mock:fn(() => null),
  executePluginCommand: mock:fn(async () => ({ text: "ok" })),
}));
const deliveryMocks = mock:hoisted(() => ({
  deliverReplies: mock:fn(async () => ({ delivered: true })),
}));

mock:mock("../auto-reply/skill-commands.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../auto-reply/skill-commands.js")>();
  return {
    ...actual,
    listSkillCommandsForAgents,
  };
});
mock:mock("../plugins/commands.js", () => ({
  getPluginCommandSpecs: pluginCommandMocks.getPluginCommandSpecs,
  matchPluginCommand: pluginCommandMocks.matchPluginCommand,
  executePluginCommand: pluginCommandMocks.executePluginCommand,
}));
mock:mock("./bot/delivery.js", () => ({
  deliverReplies: deliveryMocks.deliverReplies,
}));

(deftest-group "registerTelegramNativeCommands", () => {
  type RegisteredCommand = {
    command: string;
    description: string;
  };

  async function waitForRegisteredCommands(
    setMyCommands: ReturnType<typeof mock:fn>,
  ): deferred-result<RegisteredCommand[]> {
    await mock:waitFor(() => {
      (expect* setMyCommands).toHaveBeenCalled();
    });
    return setMyCommands.mock.calls[0]?.[0] as RegisteredCommand[];
  }

  beforeEach(() => {
    listSkillCommandsForAgents.mockClear();
    listSkillCommandsForAgents.mockReturnValue([]);
    pluginCommandMocks.getPluginCommandSpecs.mockClear();
    pluginCommandMocks.getPluginCommandSpecs.mockReturnValue([]);
    pluginCommandMocks.matchPluginCommand.mockClear();
    pluginCommandMocks.matchPluginCommand.mockReturnValue(null);
    pluginCommandMocks.executePluginCommand.mockClear();
    pluginCommandMocks.executePluginCommand.mockResolvedValue({ text: "ok" });
    deliveryMocks.deliverReplies.mockClear();
    deliveryMocks.deliverReplies.mockResolvedValue({ delivered: true });
  });

  const buildParams = (cfg: OpenClawConfig, accountId = "default") =>
    createNativeCommandTestParams({
      bot: {
        api: {
          setMyCommands: mock:fn().mockResolvedValue(undefined),
          sendMessage: mock:fn().mockResolvedValue(undefined),
        },
        command: mock:fn(),
      } as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
      cfg,
      runtime: {} as RuntimeEnv,
      accountId,
      telegramCfg: {} as TelegramAccountConfig,
    });

  (deftest "scopes skill commands when account binding exists", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", default: true }, { id: "butler" }],
      },
      bindings: [
        {
          agentId: "butler",
          match: { channel: "telegram", accountId: "bot-a" },
        },
      ],
    };

    registerTelegramNativeCommands(buildParams(cfg, "bot-a"));

    (expect* listSkillCommandsForAgents).toHaveBeenCalledWith({
      cfg,
      agentIds: ["butler"],
    });
  });

  (deftest "scopes skill commands to default agent without a matching binding (#15599)", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", default: true }, { id: "butler" }],
      },
    };

    registerTelegramNativeCommands(buildParams(cfg, "bot-a"));

    (expect* listSkillCommandsForAgents).toHaveBeenCalledWith({
      cfg,
      agentIds: ["main"],
    });
  });

  (deftest "truncates Telegram command registration to 100 commands", async () => {
    const cfg: OpenClawConfig = {
      commands: { native: false },
    };
    const customCommands = Array.from({ length: 120 }, (_, index) => ({
      command: `cmd_${index}`,
      description: `Command ${index}`,
    }));
    const setMyCommands = mock:fn().mockResolvedValue(undefined);
    const runtimeLog = mock:fn();

    registerTelegramNativeCommands({
      ...buildParams(cfg),
      bot: {
        api: {
          setMyCommands,
          sendMessage: mock:fn().mockResolvedValue(undefined),
        },
        command: mock:fn(),
      } as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
      runtime: { log: runtimeLog } as unknown as RuntimeEnv,
      telegramCfg: { customCommands } as TelegramAccountConfig,
      nativeEnabled: false,
      nativeSkillsEnabled: false,
    });

    const registeredCommands = await waitForRegisteredCommands(setMyCommands);
    (expect* registeredCommands).has-length(100);
    (expect* registeredCommands).is-equal(customCommands.slice(0, 100));
    (expect* runtimeLog).toHaveBeenCalledWith(
      "Telegram limits bots to 100 commands. 120 configured; registering first 100. Use channels.telegram.commands.native: false to disable, or reduce plugin/skill/custom commands.",
    );
  });

  (deftest "normalizes hyphenated native command names for Telegram registration", async () => {
    const setMyCommands = mock:fn().mockResolvedValue(undefined);
    const command = mock:fn();

    registerTelegramNativeCommands({
      ...buildParams({}),
      bot: {
        api: {
          setMyCommands,
          sendMessage: mock:fn().mockResolvedValue(undefined),
        },
        command,
      } as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
    });

    const registeredCommands = await waitForRegisteredCommands(setMyCommands);
    (expect* registeredCommands.some((entry) => entry.command === "export_session")).is(true);
    (expect* registeredCommands.some((entry) => entry.command === "export-session")).is(false);

    const registeredHandlers = command.mock.calls.map(([name]) => name);
    (expect* registeredHandlers).contains("export_session");
    (expect* registeredHandlers).not.contains("export-session");
  });

  (deftest "registers only Telegram-safe command names across native, custom, and plugin sources", async () => {
    const setMyCommands = mock:fn().mockResolvedValue(undefined);

    pluginCommandMocks.getPluginCommandSpecs.mockReturnValue([
      { name: "plugin-status", description: "Plugin status" },
      { name: "plugin@bad", description: "Bad plugin command" },
    ] as never);

    registerTelegramNativeCommands({
      ...buildParams({}),
      bot: {
        api: {
          setMyCommands,
          sendMessage: mock:fn().mockResolvedValue(undefined),
        },
        command: mock:fn(),
      } as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
      telegramCfg: {
        customCommands: [
          { command: "custom-backup", description: "Custom backup" },
          { command: "custom!bad", description: "Bad custom command" },
        ],
      } as TelegramAccountConfig,
    });

    const registeredCommands = await waitForRegisteredCommands(setMyCommands);

    (expect* registeredCommands.length).toBeGreaterThan(0);
    for (const entry of registeredCommands) {
      (expect* entry.command.includes("-")).is(false);
      (expect* TELEGRAM_COMMAND_NAME_PATTERN.(deftest entry.command)).is(true);
    }

    (expect* registeredCommands.some((entry) => entry.command === "export_session")).is(true);
    (expect* registeredCommands.some((entry) => entry.command === "custom_backup")).is(true);
    (expect* registeredCommands.some((entry) => entry.command === "plugin_status")).is(true);
    (expect* registeredCommands.some((entry) => entry.command === "plugin-status")).is(false);
    (expect* registeredCommands.some((entry) => entry.command === "custom-bad")).is(false);
  });

  (deftest "passes agent-scoped media roots for plugin command replies with media", async () => {
    const commandHandlers = new Map<string, (ctx: unknown) => deferred-result<void>>();
    const sendMessage = mock:fn().mockResolvedValue(undefined);
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", default: true }, { id: "work" }],
      },
      bindings: [{ agentId: "work", match: { channel: "telegram", accountId: "default" } }],
    };

    pluginCommandMocks.getPluginCommandSpecs.mockReturnValue([
      {
        name: "plug",
        description: "Plugin command",
      },
    ] as never);
    pluginCommandMocks.matchPluginCommand.mockReturnValue({
      command: { key: "plug", requireAuth: false },
      args: undefined,
    } as never);
    pluginCommandMocks.executePluginCommand.mockResolvedValue({
      text: "with media",
      mediaUrl: "/tmp/workspace-work/render.png",
    } as never);

    registerTelegramNativeCommands({
      ...buildParams(cfg),
      bot: {
        api: {
          setMyCommands: mock:fn().mockResolvedValue(undefined),
          sendMessage,
        },
        command: mock:fn((name: string, cb: (ctx: unknown) => deferred-result<void>) => {
          commandHandlers.set(name, cb);
        }),
      } as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
    });

    const handler = commandHandlers.get("plug");
    (expect* handler).is-truthy();
    await handler?.({
      match: "",
      message: {
        message_id: 1,
        date: Math.floor(Date.now() / 1000),
        chat: { id: 123, type: "private" },
        from: { id: 456, username: "alice" },
      },
    });

    (expect* deliveryMocks.deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        mediaLocalRoots: expect.arrayContaining([path.join(STATE_DIR, "workspace-work")]),
      }),
    );
    (expect* sendMessage).not.toHaveBeenCalledWith(123, "Command not found.");
  });
});
