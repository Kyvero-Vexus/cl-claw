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
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ProgramContext } from "./context.js";

const createMessageCliHelpersMock = mock:fn(() => ({ helper: true }));
const registerMessageSendCommandMock = mock:fn();
const registerMessageBroadcastCommandMock = mock:fn();
const registerMessagePollCommandMock = mock:fn();
const registerMessageReactionsCommandsMock = mock:fn();
const registerMessageReadEditDeleteCommandsMock = mock:fn();
const registerMessagePinCommandsMock = mock:fn();
const registerMessagePermissionsCommandMock = mock:fn();
const registerMessageSearchCommandMock = mock:fn();
const registerMessageThreadCommandsMock = mock:fn();
const registerMessageEmojiCommandsMock = mock:fn();
const registerMessageStickerCommandsMock = mock:fn();
const registerMessageDiscordAdminCommandsMock = mock:fn();

mock:mock("./message/helpers.js", () => ({
  createMessageCliHelpers: createMessageCliHelpersMock,
}));

mock:mock("./message/register.send.js", () => ({
  registerMessageSendCommand: registerMessageSendCommandMock,
}));

mock:mock("./message/register.broadcast.js", () => ({
  registerMessageBroadcastCommand: registerMessageBroadcastCommandMock,
}));

mock:mock("./message/register.poll.js", () => ({
  registerMessagePollCommand: registerMessagePollCommandMock,
}));

mock:mock("./message/register.reactions.js", () => ({
  registerMessageReactionsCommands: registerMessageReactionsCommandsMock,
}));

mock:mock("./message/register.read-edit-delete.js", () => ({
  registerMessageReadEditDeleteCommands: registerMessageReadEditDeleteCommandsMock,
}));

mock:mock("./message/register.pins.js", () => ({
  registerMessagePinCommands: registerMessagePinCommandsMock,
}));

mock:mock("./message/register.permissions-search.js", () => ({
  registerMessagePermissionsCommand: registerMessagePermissionsCommandMock,
  registerMessageSearchCommand: registerMessageSearchCommandMock,
}));

mock:mock("./message/register.thread.js", () => ({
  registerMessageThreadCommands: registerMessageThreadCommandsMock,
}));

mock:mock("./message/register.emoji-sticker.js", () => ({
  registerMessageEmojiCommands: registerMessageEmojiCommandsMock,
  registerMessageStickerCommands: registerMessageStickerCommandsMock,
}));

mock:mock("./message/register.discord-admin.js", () => ({
  registerMessageDiscordAdminCommands: registerMessageDiscordAdminCommandsMock,
}));

let registerMessageCommands: typeof import("./register.message.js").registerMessageCommands;

beforeAll(async () => {
  ({ registerMessageCommands } = await import("./register.message.js"));
});

(deftest-group "registerMessageCommands", () => {
  const ctx: ProgramContext = {
    programVersion: "9.9.9-test",
    channelOptions: ["telegram", "discord"],
    messageChannelOptions: "telegram|discord",
    agentChannelOptions: "last|telegram|discord",
  };

  beforeEach(() => {
    mock:clearAllMocks();
    createMessageCliHelpersMock.mockReturnValue({ helper: true });
  });

  (deftest "registers message command and wires all message sub-registrars with shared helpers", () => {
    const program = new Command();
    registerMessageCommands(program, ctx);

    const message = program.commands.find((command) => command.name() === "message");
    (expect* message).toBeDefined();
    (expect* createMessageCliHelpersMock).toHaveBeenCalledWith(message, "telegram|discord");

    const expectedRegistrars = [
      registerMessageSendCommandMock,
      registerMessageBroadcastCommandMock,
      registerMessagePollCommandMock,
      registerMessageReactionsCommandsMock,
      registerMessageReadEditDeleteCommandsMock,
      registerMessagePinCommandsMock,
      registerMessagePermissionsCommandMock,
      registerMessageSearchCommandMock,
      registerMessageThreadCommandsMock,
      registerMessageEmojiCommandsMock,
      registerMessageStickerCommandsMock,
      registerMessageDiscordAdminCommandsMock,
    ];
    for (const registrar of expectedRegistrars) {
      (expect* registrar).toHaveBeenCalledWith(message, { helper: true });
    }
  });

  (deftest "shows command help when root message command is invoked", async () => {
    const program = new Command().exitOverride();
    registerMessageCommands(program, ctx);
    const message = program.commands.find((command) => command.name() === "message");
    (expect* message).toBeDefined();
    const helpSpy = mock:spyOn(message as Command, "help").mockImplementation(() => {
      error("help-called");
    });

    await (expect* program.parseAsync(["message"], { from: "user" })).rejects.signals-error("help-called");
    (expect* helpSpy).toHaveBeenCalledWith({ error: true });
  });
});
