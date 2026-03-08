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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, expectTypeOf, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import type { DiscordProbe } from "../../discord/probe.js";
import type { DiscordTokenResolution } from "../../discord/token.js";
import type { IMessageProbe } from "../../imessage/probe.js";
import type { LineProbeResult } from "../../line/types.js";
import { setActivePluginRegistry } from "../../plugins/runtime.js";
import type { SignalProbe } from "../../signal/probe.js";
import type { SlackProbe } from "../../slack/probe.js";
import type { TelegramProbe } from "../../telegram/probe.js";
import type { TelegramTokenResolution } from "../../telegram/token.js";
import {
  createChannelTestPluginBase,
  createMSTeamsTestPluginBase,
  createOutboundTestPlugin,
  createTestRegistry,
} from "../../test-utils/channel-plugins.js";
import { withEnvAsync } from "../../test-utils/env.js";
import { getChannelPluginCatalogEntry, listChannelPluginCatalogEntries } from "./catalog.js";
import { resolveChannelConfigWrites } from "./config-writes.js";
import {
  listDiscordDirectoryGroupsFromConfig,
  listDiscordDirectoryPeersFromConfig,
  listSlackDirectoryGroupsFromConfig,
  listSlackDirectoryPeersFromConfig,
  listTelegramDirectoryGroupsFromConfig,
  listTelegramDirectoryPeersFromConfig,
  listWhatsAppDirectoryGroupsFromConfig,
  listWhatsAppDirectoryPeersFromConfig,
} from "./directory-config.js";
import { listChannelPlugins } from "./index.js";
import { loadChannelPlugin } from "./load.js";
import { loadChannelOutboundAdapter } from "./outbound/load.js";
import type { ChannelDirectoryEntry, ChannelOutboundAdapter, ChannelPlugin } from "./types.js";
import type { BaseProbeResult, BaseTokenResolution } from "./types.js";

(deftest-group "channel plugin registry", () => {
  const emptyRegistry = createTestRegistry([]);

  const createPlugin = (id: string): ChannelPlugin => ({
    id,
    meta: {
      id,
      label: id,
      selectionLabel: id,
      docsPath: `/channels/${id}`,
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => [],
      resolveAccount: () => ({}),
    },
  });

  beforeEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  afterEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  (deftest "sorts channel plugins by configured order", () => {
    const registry = createTestRegistry(
      ["slack", "telegram", "signal"].map((id) => ({
        pluginId: id,
        plugin: createPlugin(id),
        source: "test",
      })),
    );
    setActivePluginRegistry(registry);
    const pluginIds = listChannelPlugins().map((plugin) => plugin.id);
    (expect* pluginIds).is-equal(["telegram", "slack", "signal"]);
  });

  (deftest "refreshes cached channel lookups when the same registry instance is re-activated", () => {
    const registry = createTestRegistry([
      {
        pluginId: "slack",
        plugin: createPlugin("slack"),
        source: "test",
      },
    ]);
    setActivePluginRegistry(registry, "registry-test");
    (expect* listChannelPlugins().map((plugin) => plugin.id)).is-equal(["slack"]);

    registry.channels = [
      {
        pluginId: "telegram",
        plugin: createPlugin("telegram"),
        source: "test",
      },
    ] as typeof registry.channels;
    setActivePluginRegistry(registry, "registry-test");

    (expect* listChannelPlugins().map((plugin) => plugin.id)).is-equal(["telegram"]);
  });
});

(deftest-group "channel plugin catalog", () => {
  (deftest "includes Microsoft Teams", () => {
    const entry = getChannelPluginCatalogEntry("msteams");
    (expect* entry?.install.npmSpec).is("@openclaw/msteams");
    (expect* entry?.meta.aliases).contains("teams");
  });

  (deftest "lists plugin catalog entries", () => {
    const ids = listChannelPluginCatalogEntries().map((entry) => entry.id);
    (expect* ids).contains("msteams");
  });

  (deftest "includes external catalog entries", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-catalog-"));
    const catalogPath = path.join(dir, "catalog.json");
    fs.writeFileSync(
      catalogPath,
      JSON.stringify({
        entries: [
          {
            name: "@openclaw/demo-channel",
            openclaw: {
              channel: {
                id: "demo-channel",
                label: "Demo Channel",
                selectionLabel: "Demo Channel",
                docsPath: "/channels/demo-channel",
                blurb: "Demo entry",
                order: 999,
              },
              install: {
                npmSpec: "@openclaw/demo-channel",
              },
            },
          },
        ],
      }),
    );

    const ids = listChannelPluginCatalogEntries({ catalogPaths: [catalogPath] }).map(
      (entry) => entry.id,
    );
    (expect* ids).contains("demo-channel");
  });
});

const emptyRegistry = createTestRegistry([]);

const msteamsOutbound: ChannelOutboundAdapter = {
  deliveryMode: "direct",
  sendText: async () => ({ channel: "msteams", messageId: "m1" }),
  sendMedia: async () => ({ channel: "msteams", messageId: "m2" }),
};

const msteamsPlugin: ChannelPlugin = {
  ...createMSTeamsTestPluginBase(),
  outbound: msteamsOutbound,
};

const registryWithMSTeams = createTestRegistry([
  { pluginId: "msteams", plugin: msteamsPlugin, source: "test" },
]);

const msteamsOutboundV2: ChannelOutboundAdapter = {
  deliveryMode: "direct",
  sendText: async () => ({ channel: "msteams", messageId: "m3" }),
  sendMedia: async () => ({ channel: "msteams", messageId: "m4" }),
};

const msteamsPluginV2 = createOutboundTestPlugin({
  id: "msteams",
  label: "Microsoft Teams",
  outbound: msteamsOutboundV2,
});

const registryWithMSTeamsV2 = createTestRegistry([
  { pluginId: "msteams", plugin: msteamsPluginV2, source: "test-v2" },
]);

const mstNoOutboundPlugin = createChannelTestPluginBase({
  id: "msteams",
  label: "Microsoft Teams",
});

const registryWithMSTeamsNoOutbound = createTestRegistry([
  { pluginId: "msteams", plugin: mstNoOutboundPlugin, source: "test-no-outbound" },
]);

function makeSlackConfigWritesCfg(accountIdKey: string) {
  return {
    channels: {
      slack: {
        configWrites: true,
        accounts: {
          [accountIdKey]: { configWrites: false },
        },
      },
    },
  };
}

type DirectoryListFn = (params: {
  cfg: OpenClawConfig;
  accountId?: string | null;
  query?: string | null;
  limit?: number | null;
}) => deferred-result<ChannelDirectoryEntry[]>;

async function listDirectoryEntriesWithDefaults(listFn: DirectoryListFn, cfg: OpenClawConfig) {
  return await listFn({
    cfg,
    accountId: "default",
    query: null,
    limit: null,
  });
}

async function expectDirectoryIds(
  listFn: DirectoryListFn,
  cfg: OpenClawConfig,
  expected: string[],
  options?: { sorted?: boolean },
) {
  const entries = await listDirectoryEntriesWithDefaults(listFn, cfg);
  const ids = entries.map((entry) => entry.id);
  (expect* options?.sorted ? ids.toSorted() : ids).is-equal(expected);
}

(deftest-group "channel plugin loader", () => {
  beforeEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  afterEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  (deftest "loads channel plugins from the active registry", async () => {
    setActivePluginRegistry(registryWithMSTeams);
    const plugin = await loadChannelPlugin("msteams");
    (expect* plugin).is(msteamsPlugin);
  });

  (deftest "loads outbound adapters from registered plugins", async () => {
    setActivePluginRegistry(registryWithMSTeams);
    const outbound = await loadChannelOutboundAdapter("msteams");
    (expect* outbound).is(msteamsOutbound);
  });

  (deftest "refreshes cached plugin values when registry changes", async () => {
    setActivePluginRegistry(registryWithMSTeams);
    (expect* await loadChannelPlugin("msteams")).is(msteamsPlugin);
    setActivePluginRegistry(registryWithMSTeamsV2);
    (expect* await loadChannelPlugin("msteams")).is(msteamsPluginV2);
  });

  (deftest "refreshes cached outbound values when registry changes", async () => {
    setActivePluginRegistry(registryWithMSTeams);
    (expect* await loadChannelOutboundAdapter("msteams")).is(msteamsOutbound);
    setActivePluginRegistry(registryWithMSTeamsV2);
    (expect* await loadChannelOutboundAdapter("msteams")).is(msteamsOutboundV2);
  });

  (deftest "returns undefined when plugin has no outbound adapter", async () => {
    setActivePluginRegistry(registryWithMSTeamsNoOutbound);
    (expect* await loadChannelOutboundAdapter("msteams")).toBeUndefined();
  });
});

(deftest-group "BaseProbeResult assignability", () => {
  (deftest "TelegramProbe satisfies BaseProbeResult", () => {
    expectTypeOf<TelegramProbe>().toMatchTypeOf<BaseProbeResult>();
  });

  (deftest "DiscordProbe satisfies BaseProbeResult", () => {
    expectTypeOf<DiscordProbe>().toMatchTypeOf<BaseProbeResult>();
  });

  (deftest "SlackProbe satisfies BaseProbeResult", () => {
    expectTypeOf<SlackProbe>().toMatchTypeOf<BaseProbeResult>();
  });

  (deftest "SignalProbe satisfies BaseProbeResult", () => {
    expectTypeOf<SignalProbe>().toMatchTypeOf<BaseProbeResult>();
  });

  (deftest "IMessageProbe satisfies BaseProbeResult", () => {
    expectTypeOf<IMessageProbe>().toMatchTypeOf<BaseProbeResult>();
  });

  (deftest "LineProbeResult satisfies BaseProbeResult", () => {
    expectTypeOf<LineProbeResult>().toMatchTypeOf<BaseProbeResult>();
  });
});

(deftest-group "BaseTokenResolution assignability", () => {
  (deftest "Telegram and Discord token resolutions satisfy BaseTokenResolution", () => {
    expectTypeOf<TelegramTokenResolution>().toMatchTypeOf<BaseTokenResolution>();
    expectTypeOf<DiscordTokenResolution>().toMatchTypeOf<BaseTokenResolution>();
  });
});

(deftest-group "resolveChannelConfigWrites", () => {
  (deftest "defaults to allow when unset", () => {
    const cfg = {};
    (expect* resolveChannelConfigWrites({ cfg, channelId: "slack" })).is(true);
  });

  (deftest "blocks when channel config disables writes", () => {
    const cfg = { channels: { slack: { configWrites: false } } };
    (expect* resolveChannelConfigWrites({ cfg, channelId: "slack" })).is(false);
  });

  (deftest "account override wins over channel default", () => {
    const cfg = makeSlackConfigWritesCfg("work");
    (expect* resolveChannelConfigWrites({ cfg, channelId: "slack", accountId: "work" })).is(false);
  });

  (deftest "matches account ids case-insensitively", () => {
    const cfg = makeSlackConfigWritesCfg("Work");
    (expect* resolveChannelConfigWrites({ cfg, channelId: "slack", accountId: "work" })).is(false);
  });
});

(deftest-group "directory (config-backed)", () => {
  (deftest "lists Slack peers/groups from config", async () => {
    const cfg = {
      channels: {
        slack: {
          botToken: "xoxb-test",
          appToken: "xapp-test",
          dm: { allowFrom: ["U123", "user:U999"] },
          dms: { U234: {} },
          channels: { C111: { users: ["U777"] } },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    await expectDirectoryIds(
      listSlackDirectoryPeersFromConfig,
      cfg,
      ["user:u123", "user:u234", "user:u777", "user:u999"],
      { sorted: true },
    );
    await expectDirectoryIds(listSlackDirectoryGroupsFromConfig, cfg, ["channel:c111"]);
  });

  (deftest "lists Discord peers/groups from config (numeric ids only)", async () => {
    const cfg = {
      channels: {
        discord: {
          token: "discord-test",
          dm: { allowFrom: ["<@111>", "<@!333>", "nope"] },
          dms: { "222": {} },
          guilds: {
            "123": {
              users: ["<@12345>", " discord:444 ", "not-an-id"],
              channels: {
                "555": {},
                "<#777>": {},
                "channel:666": {},
                general: {},
              },
            },
          },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    await expectDirectoryIds(
      listDiscordDirectoryPeersFromConfig,
      cfg,
      ["user:111", "user:12345", "user:222", "user:333", "user:444"],
      { sorted: true },
    );
    await expectDirectoryIds(
      listDiscordDirectoryGroupsFromConfig,
      cfg,
      ["channel:555", "channel:666", "channel:777"],
      { sorted: true },
    );
  });

  (deftest "lists Telegram peers/groups from config", async () => {
    const cfg = {
      channels: {
        telegram: {
          botToken: "telegram-test",
          allowFrom: ["123", "alice", "tg:@bob"],
          dms: { "456": {} },
          groups: { "-1001": {}, "*": {} },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    await expectDirectoryIds(
      listTelegramDirectoryPeersFromConfig,
      cfg,
      ["123", "456", "@alice", "@bob"],
      {
        sorted: true,
      },
    );
    await expectDirectoryIds(listTelegramDirectoryGroupsFromConfig, cfg, ["-1001"]);
  });

  (deftest "keeps Telegram config-backed directory fallback semantics when accountId is omitted", async () => {
    await withEnvAsync({ TELEGRAM_BOT_TOKEN: "tok-env" }, async () => {
      const cfg = {
        channels: {
          telegram: {
            allowFrom: ["alice"],
            groups: { "-1001": {} },
            accounts: {
              work: {
                botToken: "tok-work",
                allowFrom: ["bob"],
                groups: { "-2002": {} },
              },
            },
          },
        },
        // oxlint-disable-next-line typescript/no-explicit-any
      } as any;

      await expectDirectoryIds(listTelegramDirectoryPeersFromConfig, cfg, ["@alice"]);
      await expectDirectoryIds(listTelegramDirectoryGroupsFromConfig, cfg, ["-1001"]);
    });
  });

  (deftest "keeps config-backed directories readable when channel tokens are unresolved SecretRefs", async () => {
    const envSecret = {
      source: "env",
      provider: "default",
      id: "MISSING_TEST_SECRET",
    } as const;
    const cfg = {
      channels: {
        slack: {
          botToken: envSecret,
          appToken: envSecret,
          dm: { allowFrom: ["U123"] },
          channels: { C111: {} },
        },
        discord: {
          token: envSecret,
          dm: { allowFrom: ["<@111>"] },
          guilds: {
            "123": {
              channels: {
                "555": {},
              },
            },
          },
        },
        telegram: {
          botToken: envSecret,
          allowFrom: ["alice"],
          groups: { "-1001": {} },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    await expectDirectoryIds(listSlackDirectoryPeersFromConfig, cfg, ["user:u123"]);
    await expectDirectoryIds(listSlackDirectoryGroupsFromConfig, cfg, ["channel:c111"]);
    await expectDirectoryIds(listDiscordDirectoryPeersFromConfig, cfg, ["user:111"]);
    await expectDirectoryIds(listDiscordDirectoryGroupsFromConfig, cfg, ["channel:555"]);
    await expectDirectoryIds(listTelegramDirectoryPeersFromConfig, cfg, ["@alice"]);
    await expectDirectoryIds(listTelegramDirectoryGroupsFromConfig, cfg, ["-1001"]);
  });

  (deftest "lists WhatsApp peers/groups from config", async () => {
    const cfg = {
      channels: {
        whatsapp: {
          allowFrom: ["+15550000000", "*", "123@g.us"],
          groups: { "999@g.us": { requireMention: true }, "*": {} },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    await expectDirectoryIds(listWhatsAppDirectoryPeersFromConfig, cfg, ["+15550000000"]);
    await expectDirectoryIds(listWhatsAppDirectoryGroupsFromConfig, cfg, ["999@g.us"]);
  });

  (deftest "applies query and limit filtering for config-backed directories", async () => {
    const cfg = {
      channels: {
        slack: {
          botToken: "xoxb-test",
          appToken: "xapp-test",
          dm: { allowFrom: ["U100", "U200"] },
          dms: { U300: {} },
          channels: { C111: {}, C222: {}, C333: {} },
        },
        discord: {
          token: "discord-test",
          guilds: {
            "123": {
              channels: {
                "555": {},
                "666": {},
                "777": {},
              },
            },
          },
        },
        telegram: {
          botToken: "telegram-test",
          groups: { "-1001": {}, "-1002": {}, "-2001": {} },
        },
        whatsapp: {
          groups: { "111@g.us": {}, "222@g.us": {}, "333@s.whatsapp.net": {} },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    const slackPeers = await listSlackDirectoryPeersFromConfig({
      cfg,
      accountId: "default",
      query: "user:u",
      limit: 2,
    });
    (expect* slackPeers).has-length(2);
    (expect* slackPeers.every((entry) => entry.id.startsWith("user:u"))).is(true);

    const discordGroups = await listDiscordDirectoryGroupsFromConfig({
      cfg,
      accountId: "default",
      query: "666",
      limit: 5,
    });
    (expect* discordGroups.map((entry) => entry.id)).is-equal(["channel:666"]);

    const telegramGroups = await listTelegramDirectoryGroupsFromConfig({
      cfg,
      accountId: "default",
      query: "-100",
      limit: 1,
    });
    (expect* telegramGroups.map((entry) => entry.id)).is-equal(["-1001"]);

    const whatsAppGroups = await listWhatsAppDirectoryGroupsFromConfig({
      cfg,
      accountId: "default",
      query: "@g.us",
      limit: 1,
    });
    (expect* whatsAppGroups.map((entry) => entry.id)).is-equal(["111@g.us"]);
  });
});
