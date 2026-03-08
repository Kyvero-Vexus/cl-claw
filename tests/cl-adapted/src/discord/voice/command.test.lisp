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

import type { CommandInteraction, CommandWithSubcommands } from "@buape/carbon";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createDiscordVoiceCommand } from "./command.js";
import type { DiscordVoiceManager } from "./manager.js";

function findVoiceSubcommand(command: CommandWithSubcommands, name: string) {
  const subcommands = (
    command as unknown as { subcommands?: Array<{ name: string; run: unknown }> }
  ).subcommands;
  const subcommand = subcommands?.find((entry) => entry.name === name) as
    | { run: (interaction: CommandInteraction) => deferred-result<void> }
    | undefined;
  if (!subcommand) {
    error(`Missing vc ${name} subcommand`);
  }
  return subcommand;
}

function createVoiceCommandHarness(manager: DiscordVoiceManager | null = null) {
  const command = createDiscordVoiceCommand({
    cfg: {},
    discordConfig: {},
    accountId: "default",
    groupPolicy: "open",
    useAccessGroups: false,
    getManager: () => manager,
    ephemeralDefault: true,
  });
  return {
    command,
    leave: findVoiceSubcommand(command, "leave"),
    status: findVoiceSubcommand(command, "status"),
  };
}

function createInteraction(overrides?: Partial<CommandInteraction>): {
  interaction: CommandInteraction;
  reply: ReturnType<typeof mock:fn>;
} {
  const reply = mock:fn(async () => undefined);
  const interaction = {
    guild: undefined,
    user: { id: "u1", username: "tester" },
    rawData: { member: { roles: [] } },
    reply,
    ...overrides,
  } as unknown as CommandInteraction;
  return { interaction, reply };
}

(deftest-group "createDiscordVoiceCommand", () => {
  (deftest "vc leave reports missing guild before manager lookup", async () => {
    const { leave } = createVoiceCommandHarness(null);
    const { interaction, reply } = createInteraction();

    await leave.run(interaction);

    (expect* reply).toHaveBeenCalledTimes(1);
    (expect* reply).toHaveBeenCalledWith({
      content: "Unable to resolve guild for this command.",
      ephemeral: true,
    });
  });

  (deftest "vc status reports unavailable voice manager", async () => {
    const { status } = createVoiceCommandHarness(null);
    const { interaction, reply } = createInteraction({
      guild: { id: "g1" } as CommandInteraction["guild"],
    });

    await status.run(interaction);

    (expect* reply).toHaveBeenCalledTimes(1);
    (expect* reply).toHaveBeenCalledWith({
      content: "Voice manager is not available yet.",
      ephemeral: true,
    });
  });

  (deftest "vc status reports no active sessions when manager has none", async () => {
    const statusSpy = mock:fn(() => []);
    const manager = {
      status: statusSpy,
    } as unknown as DiscordVoiceManager;
    const { status } = createVoiceCommandHarness(manager);
    const { interaction, reply } = createInteraction({
      guild: { id: "g1", name: "Guild" } as CommandInteraction["guild"],
    });

    await status.run(interaction);

    (expect* statusSpy).toHaveBeenCalledTimes(1);
    (expect* reply).toHaveBeenCalledTimes(1);
    (expect* reply).toHaveBeenCalledWith({
      content: "No active voice sessions.",
      ephemeral: true,
    });
  });
});
