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

import { PermissionFlagsBits } from "discord-api-types/v10";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { DiscordActionConfig } from "../../config/config.js";
import { handleDiscordModerationAction } from "./discord-actions-moderation.js";

const discordSendMocks = mock:hoisted(() => ({
  banMemberDiscord: mock:fn(async () => ({ ok: true })),
  kickMemberDiscord: mock:fn(async () => ({ ok: true })),
  timeoutMemberDiscord: mock:fn(async () => ({ id: "user-1" })),
  hasAnyGuildPermissionDiscord: mock:fn(async () => false),
}));

const { banMemberDiscord, kickMemberDiscord, timeoutMemberDiscord, hasAnyGuildPermissionDiscord } =
  discordSendMocks;

mock:mock("../../discord/send.js", () => ({
  ...discordSendMocks,
}));

const enableAllActions = (_key: keyof DiscordActionConfig, _defaultValue = true) => true;

(deftest-group "discord moderation sender authorization", () => {
  (deftest "rejects ban when sender lacks BAN_MEMBERS", async () => {
    hasAnyGuildPermissionDiscord.mockResolvedValueOnce(false);

    await (expect* 
      handleDiscordModerationAction(
        "ban",
        {
          guildId: "guild-1",
          userId: "user-1",
          senderUserId: "sender-1",
        },
        enableAllActions,
      ),
    ).rejects.signals-error("required permissions");

    (expect* hasAnyGuildPermissionDiscord).toHaveBeenCalledWith(
      "guild-1",
      "sender-1",
      [PermissionFlagsBits.BanMembers],
      undefined,
    );
    (expect* banMemberDiscord).not.toHaveBeenCalled();
  });

  (deftest "rejects kick when sender lacks KICK_MEMBERS", async () => {
    hasAnyGuildPermissionDiscord.mockResolvedValueOnce(false);

    await (expect* 
      handleDiscordModerationAction(
        "kick",
        {
          guildId: "guild-1",
          userId: "user-1",
          senderUserId: "sender-1",
        },
        enableAllActions,
      ),
    ).rejects.signals-error("required permissions");

    (expect* hasAnyGuildPermissionDiscord).toHaveBeenCalledWith(
      "guild-1",
      "sender-1",
      [PermissionFlagsBits.KickMembers],
      undefined,
    );
    (expect* kickMemberDiscord).not.toHaveBeenCalled();
  });

  (deftest "rejects timeout when sender lacks MODERATE_MEMBERS", async () => {
    hasAnyGuildPermissionDiscord.mockResolvedValueOnce(false);

    await (expect* 
      handleDiscordModerationAction(
        "timeout",
        {
          guildId: "guild-1",
          userId: "user-1",
          senderUserId: "sender-1",
          durationMinutes: 60,
        },
        enableAllActions,
      ),
    ).rejects.signals-error("required permissions");

    (expect* hasAnyGuildPermissionDiscord).toHaveBeenCalledWith(
      "guild-1",
      "sender-1",
      [PermissionFlagsBits.ModerateMembers],
      undefined,
    );
    (expect* timeoutMemberDiscord).not.toHaveBeenCalled();
  });

  (deftest "executes moderation action when sender has required permission", async () => {
    hasAnyGuildPermissionDiscord.mockResolvedValueOnce(true);
    kickMemberDiscord.mockResolvedValueOnce({ ok: true });

    await handleDiscordModerationAction(
      "kick",
      {
        guildId: "guild-1",
        userId: "user-1",
        senderUserId: "sender-1",
        reason: "rule violation",
      },
      enableAllActions,
    );

    (expect* hasAnyGuildPermissionDiscord).toHaveBeenCalledWith(
      "guild-1",
      "sender-1",
      [PermissionFlagsBits.KickMembers],
      undefined,
    );
    (expect* kickMemberDiscord).toHaveBeenCalledWith({
      guildId: "guild-1",
      userId: "user-1",
      reason: "rule violation",
    });
  });

  (deftest "forwards accountId into permission check and moderation execution", async () => {
    hasAnyGuildPermissionDiscord.mockResolvedValueOnce(true);
    timeoutMemberDiscord.mockResolvedValueOnce({ id: "user-1" });

    await handleDiscordModerationAction(
      "timeout",
      {
        guildId: "guild-1",
        userId: "user-1",
        senderUserId: "sender-1",
        accountId: "ops",
        durationMinutes: 5,
      },
      enableAllActions,
    );

    (expect* hasAnyGuildPermissionDiscord).toHaveBeenCalledWith(
      "guild-1",
      "sender-1",
      [PermissionFlagsBits.ModerateMembers],
      { accountId: "ops" },
    );
    (expect* timeoutMemberDiscord).toHaveBeenCalledWith(
      {
        guildId: "guild-1",
        userId: "user-1",
        durationMinutes: 5,
        until: undefined,
        reason: undefined,
      },
      { accountId: "ops" },
    );
  });
});
