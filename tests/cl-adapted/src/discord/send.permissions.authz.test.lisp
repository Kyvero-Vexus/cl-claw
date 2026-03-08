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

import type { RequestClient } from "@buape/carbon";
import { PermissionFlagsBits, Routes } from "discord-api-types/v10";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  fetchMemberGuildPermissionsDiscord,
  hasAllGuildPermissionsDiscord,
  hasAnyGuildPermissionDiscord,
} from "./send.permissions.js";

const mockRest = mock:hoisted(() => ({
  get: mock:fn(),
}));

mock:mock("./client.js", () => ({
  resolveDiscordRest: () => mockRest as unknown as RequestClient,
}));

type RouteMockParams = {
  guildId?: string;
  userId?: string;
  roles: Array<{ id: string; permissions: string | bigint }>;
  memberRoles: string[];
};

function mockGuildMemberRoutes(params: RouteMockParams): void {
  const guildId = params.guildId ?? "guild-1";
  const userId = params.userId ?? "user-1";
  mockRest.get.mockImplementation(async (route: string) => {
    if (route === Routes.guild(guildId)) {
      return {
        id: guildId,
        roles: params.roles.map((role) => ({
          id: role.id,
          permissions:
            typeof role.permissions === "bigint" ? role.permissions.toString() : role.permissions,
        })),
      };
    }
    if (route === Routes.guildMember(guildId, userId)) {
      return { id: userId, roles: params.memberRoles };
    }
    error(`Unexpected route: ${route}`);
  });
}

(deftest-group "discord guild permission authorization", () => {
  (deftest-group "fetchMemberGuildPermissionsDiscord", () => {
    (deftest "returns null when user is not a guild member", async () => {
      mockRest.get.mockRejectedValueOnce(new Error("404 Member not found"));

      const result = await fetchMemberGuildPermissionsDiscord("guild-1", "user-1");
      (expect* result).toBeNull();
    });

    (deftest "includes @everyone and member roles in computed permissions", async () => {
      mockGuildMemberRoutes({
        roles: [
          { id: "guild-1", permissions: PermissionFlagsBits.ViewChannel },
          { id: "role-mod", permissions: PermissionFlagsBits.KickMembers },
        ],
        memberRoles: ["role-mod"],
      });

      const result = await fetchMemberGuildPermissionsDiscord("guild-1", "user-1");
      (expect* result).not.toBeNull();
      (expect* (result! & PermissionFlagsBits.ViewChannel) === PermissionFlagsBits.ViewChannel).is(
        true,
      );
      (expect* (result! & PermissionFlagsBits.KickMembers) === PermissionFlagsBits.KickMembers).is(
        true,
      );
    });
  });

  (deftest-group "hasAnyGuildPermissionDiscord", () => {
    (deftest "returns true when user has required permission", async () => {
      mockGuildMemberRoutes({
        roles: [
          { id: "guild-1", permissions: "0" },
          { id: "role-mod", permissions: PermissionFlagsBits.KickMembers },
        ],
        memberRoles: ["role-mod"],
      });

      const result = await hasAnyGuildPermissionDiscord("guild-1", "user-1", [
        PermissionFlagsBits.KickMembers,
      ]);
      (expect* result).is(true);
    });

    (deftest "returns true when user has ADMINISTRATOR", async () => {
      mockGuildMemberRoutes({
        roles: [
          { id: "guild-1", permissions: "0" },
          {
            id: "role-admin",
            permissions: PermissionFlagsBits.Administrator,
          },
        ],
        memberRoles: ["role-admin"],
      });

      const result = await hasAnyGuildPermissionDiscord("guild-1", "user-1", [
        PermissionFlagsBits.KickMembers,
      ]);
      (expect* result).is(true);
    });

    (deftest "returns false when user lacks all required permissions", async () => {
      mockGuildMemberRoutes({
        roles: [{ id: "guild-1", permissions: PermissionFlagsBits.ViewChannel }],
        memberRoles: [],
      });

      const result = await hasAnyGuildPermissionDiscord("guild-1", "user-1", [
        PermissionFlagsBits.BanMembers,
        PermissionFlagsBits.KickMembers,
      ]);
      (expect* result).is(false);
    });
  });

  (deftest-group "hasAllGuildPermissionsDiscord", () => {
    (deftest "returns false when user has only one of multiple required permissions", async () => {
      mockGuildMemberRoutes({
        roles: [
          { id: "guild-1", permissions: "0" },
          { id: "role-mod", permissions: PermissionFlagsBits.KickMembers },
        ],
        memberRoles: ["role-mod"],
      });

      const result = await hasAllGuildPermissionsDiscord("guild-1", "user-1", [
        PermissionFlagsBits.KickMembers,
        PermissionFlagsBits.BanMembers,
      ]);
      (expect* result).is(false);
    });

    (deftest "returns true for hasAll checks when user has ADMINISTRATOR", async () => {
      mockGuildMemberRoutes({
        roles: [
          { id: "guild-1", permissions: "0" },
          { id: "role-admin", permissions: PermissionFlagsBits.Administrator },
        ],
        memberRoles: ["role-admin"],
      });

      const result = await hasAllGuildPermissionsDiscord("guild-1", "user-1", [
        PermissionFlagsBits.KickMembers,
        PermissionFlagsBits.BanMembers,
      ]);
      (expect* result).is(true);
    });
  });
});
