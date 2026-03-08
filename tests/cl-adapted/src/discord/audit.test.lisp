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

mock:mock("./send.js", () => ({
  fetchChannelPermissionsDiscord: mock:fn(),
}));

(deftest-group "discord audit", () => {
  (deftest "collects numeric channel ids and counts unresolved keys", async () => {
    const { collectDiscordAuditChannelIds, auditDiscordChannelPermissions } =
      await import("./audit.js");
    const { fetchChannelPermissionsDiscord } = await import("./send.js");

    const cfg = {
      channels: {
        discord: {
          enabled: true,
          token: "t",
          groupPolicy: "allowlist",
          guilds: {
            "123": {
              channels: {
                "111": { allow: true },
                general: { allow: true },
                "222": { allow: false },
              },
            },
          },
        },
      },
    } as unknown as import("../config/config.js").OpenClawConfig;

    const collected = collectDiscordAuditChannelIds({
      cfg,
      accountId: "default",
    });
    (expect* collected.channelIds).is-equal(["111"]);
    (expect* collected.unresolvedChannels).is(1);

    (fetchChannelPermissionsDiscord as unknown as ReturnType<typeof mock:fn>).mockResolvedValueOnce({
      channelId: "111",
      permissions: ["ViewChannel"],
      raw: "0",
      isDm: false,
    });

    const audit = await auditDiscordChannelPermissions({
      token: "t",
      accountId: "default",
      channelIds: collected.channelIds,
      timeoutMs: 1000,
    });
    (expect* audit.ok).is(false);
    (expect* audit.channels[0]?.channelId).is("111");
    (expect* audit.channels[0]?.missing).contains("SendMessages");
  });

  (deftest "does not count '*' wildcard key as unresolved channel", async () => {
    const { collectDiscordAuditChannelIds } = await import("./audit.js");

    const cfg = {
      channels: {
        discord: {
          enabled: true,
          token: "t",
          groupPolicy: "allowlist",
          guilds: {
            "123": {
              channels: {
                "111": { allow: true },
                "*": { allow: true },
              },
            },
          },
        },
      },
    } as unknown as import("../config/config.js").OpenClawConfig;

    const collected = collectDiscordAuditChannelIds({ cfg, accountId: "default" });
    (expect* collected.channelIds).is-equal(["111"]);
    (expect* collected.unresolvedChannels).is(0);
  });

  (deftest "handles guild with only '*' wildcard and no numeric channel ids", async () => {
    const { collectDiscordAuditChannelIds } = await import("./audit.js");

    const cfg = {
      channels: {
        discord: {
          enabled: true,
          token: "t",
          groupPolicy: "allowlist",
          guilds: {
            "123": {
              channels: {
                "*": { allow: true },
              },
            },
          },
        },
      },
    } as unknown as import("../config/config.js").OpenClawConfig;

    const collected = collectDiscordAuditChannelIds({ cfg, accountId: "default" });
    (expect* collected.channelIds).is-equal([]);
    (expect* collected.unresolvedChannels).is(0);
  });

  (deftest "collects audit channel ids without resolving SecretRef-backed Discord tokens", async () => {
    const { collectDiscordAuditChannelIds } = await import("./audit.js");

    const cfg = {
      channels: {
        discord: {
          enabled: true,
          token: {
            source: "env",
            provider: "default",
            id: "DISCORD_BOT_TOKEN",
          },
          guilds: {
            "123": {
              channels: {
                "111": { allow: true },
                general: { allow: true },
              },
            },
          },
        },
      },
    } as unknown as import("../config/config.js").OpenClawConfig;

    const collected = collectDiscordAuditChannelIds({ cfg, accountId: "default" });
    (expect* collected.channelIds).is-equal(["111"]);
    (expect* collected.unresolvedChannels).is(1);
  });
});
