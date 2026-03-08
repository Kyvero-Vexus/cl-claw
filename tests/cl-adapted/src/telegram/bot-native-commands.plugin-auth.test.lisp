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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import type { ChannelGroupPolicy } from "../config/group-policy.js";
import type { TelegramAccountConfig } from "../config/types.js";
import type { RuntimeEnv } from "../runtime.js";
import { registerTelegramNativeCommands } from "./bot-native-commands.js";

const getPluginCommandSpecs = mock:hoisted(() => mock:fn());
const matchPluginCommand = mock:hoisted(() => mock:fn());
const executePluginCommand = mock:hoisted(() => mock:fn());

mock:mock("../plugins/commands.js", () => ({
  getPluginCommandSpecs,
  matchPluginCommand,
  executePluginCommand,
}));

const deliverReplies = mock:hoisted(() => mock:fn(async () => {}));
mock:mock("./bot/delivery.js", () => ({ deliverReplies }));

mock:mock("../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: mock:fn(async () => []),
}));

(deftest-group "registerTelegramNativeCommands (plugin auth)", () => {
  (deftest "does not register plugin commands in menu when native=false but keeps handlers available", () => {
    const specs = Array.from({ length: 101 }, (_, i) => ({
      name: `cmd_${i}`,
      description: `Command ${i}`,
    }));
    getPluginCommandSpecs.mockReturnValue(specs);

    const handlers: Record<string, (ctx: unknown) => deferred-result<void>> = {};
    const setMyCommands = mock:fn().mockResolvedValue(undefined);
    const log = mock:fn();
    const bot = {
      api: {
        setMyCommands,
        sendMessage: mock:fn(),
      },
      command: (name: string, handler: (ctx: unknown) => deferred-result<void>) => {
        handlers[name] = handler;
      },
    } as const;

    registerTelegramNativeCommands({
      bot: bot as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
      cfg: {} as OpenClawConfig,
      runtime: { log } as unknown as RuntimeEnv,
      accountId: "default",
      telegramCfg: {} as TelegramAccountConfig,
      allowFrom: [],
      groupAllowFrom: [],
      replyToMode: "off",
      textLimit: 4000,
      useAccessGroups: false,
      nativeEnabled: false,
      nativeSkillsEnabled: false,
      nativeDisabledExplicit: false,
      resolveGroupPolicy: () =>
        ({
          allowlistEnabled: false,
          allowed: true,
        }) as ChannelGroupPolicy,
      resolveTelegramGroupConfig: () => ({
        groupConfig: undefined,
        topicConfig: undefined,
      }),
      shouldSkipUpdate: () => false,
      opts: { token: "token" },
    });

    (expect* setMyCommands).not.toHaveBeenCalled();
    (expect* log).not.toHaveBeenCalledWith(expect.stringContaining("registering first 100"));
    (expect* Object.keys(handlers)).has-length(101);
  });

  (deftest "allows requireAuth:false plugin command even when sender is unauthorized", async () => {
    const command = {
      name: "plugin",
      description: "Plugin command",
      requireAuth: false,
      handler: mock:fn(),
    } as const;

    getPluginCommandSpecs.mockReturnValue([{ name: "plugin", description: "Plugin command" }]);
    matchPluginCommand.mockReturnValue({ command, args: undefined });
    executePluginCommand.mockResolvedValue({ text: "ok" });

    const handlers: Record<string, (ctx: unknown) => deferred-result<void>> = {};
    const bot = {
      api: {
        setMyCommands: mock:fn().mockResolvedValue(undefined),
        sendMessage: mock:fn(),
      },
      command: (name: string, handler: (ctx: unknown) => deferred-result<void>) => {
        handlers[name] = handler;
      },
    } as const;

    const cfg = {} as OpenClawConfig;
    const telegramCfg = {} as TelegramAccountConfig;
    const resolveGroupPolicy = () =>
      ({
        allowlistEnabled: false,
        allowed: true,
      }) as ChannelGroupPolicy;

    registerTelegramNativeCommands({
      bot: bot as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
      cfg,
      runtime: {} as unknown as RuntimeEnv,
      accountId: "default",
      telegramCfg,
      allowFrom: ["999"],
      groupAllowFrom: [],
      replyToMode: "off",
      textLimit: 4000,
      useAccessGroups: false,
      nativeEnabled: false,
      nativeSkillsEnabled: false,
      nativeDisabledExplicit: false,
      resolveGroupPolicy,
      resolveTelegramGroupConfig: () => ({
        groupConfig: undefined,
        topicConfig: undefined,
      }),
      shouldSkipUpdate: () => false,
      opts: { token: "token" },
    });

    const ctx = {
      message: {
        chat: { id: 123, type: "private" },
        from: { id: 111, username: "nope" },
        message_id: 10,
        date: 123456,
      },
      match: "",
    };

    await handlers.plugin?.(ctx);

    (expect* matchPluginCommand).toHaveBeenCalled();
    (expect* executePluginCommand).toHaveBeenCalledWith(
      expect.objectContaining({
        isAuthorizedSender: false,
      }),
    );
    (expect* deliverReplies).toHaveBeenCalledWith(
      expect.objectContaining({
        replies: [{ text: "ok" }],
      }),
    );
    (expect* bot.api.sendMessage).not.toHaveBeenCalled();
  });
});
