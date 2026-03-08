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
import { listChannelPlugins } from "../../channels/plugins/index.js";
import type { ChannelPlugin } from "../../channels/plugins/types.js";
import { makeDirectPlugin } from "../../test-utils/channel-plugin-test-fixtures.js";
import { buildChannelsTable } from "./channels.js";

mock:mock("../../channels/plugins/index.js", () => ({
  listChannelPlugins: mock:fn(),
}));

function makeMattermostPlugin(): ChannelPlugin {
  return {
    id: "mattermost",
    meta: {
      id: "mattermost",
      label: "Mattermost",
      selectionLabel: "Mattermost",
      docsPath: "/channels/mattermost",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => ["echo"],
      defaultAccountId: () => "echo",
      resolveAccount: () => ({
        name: "Echo",
        enabled: true,
        botToken: "bot-token-value",
        baseUrl: "https://mm.example.com",
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
    actions: {
      listActions: () => ["send"],
    },
  };
}

function makeSlackPlugin(params?: { botToken?: string; appToken?: string }): ChannelPlugin {
  return {
    id: "slack",
    meta: {
      id: "slack",
      label: "Slack",
      selectionLabel: "Slack",
      docsPath: "/channels/slack",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      inspectAccount: () => ({
        name: "Primary",
        enabled: true,
        botToken: params?.botToken ?? "bot-token",
        appToken: params?.appToken ?? "app-token",
      }),
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        botToken: params?.botToken ?? "bot-token",
        appToken: params?.appToken ?? "app-token",
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
    actions: {
      listActions: () => ["send"],
    },
  };
}

function makeUnavailableSlackPlugin(): ChannelPlugin {
  return {
    id: "slack",
    meta: {
      id: "slack",
      label: "Slack",
      selectionLabel: "Slack",
      docsPath: "/channels/slack",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      inspectAccount: () => ({
        name: "Primary",
        enabled: true,
        configured: true,
        botToken: "",
        appToken: "",
        botTokenSource: "config",
        appTokenSource: "config",
        botTokenStatus: "configured_unavailable",
        appTokenStatus: "configured_unavailable",
      }),
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        configured: true,
        botToken: "",
        appToken: "",
        botTokenSource: "config",
        appTokenSource: "config",
        botTokenStatus: "configured_unavailable",
        appTokenStatus: "configured_unavailable",
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
    actions: {
      listActions: () => ["send"],
    },
  };
}

function makeSourceAwareUnavailablePlugin(): ChannelPlugin {
  return makeDirectPlugin({
    id: "slack",
    label: "Slack",
    docsPath: "/channels/slack",
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      inspectAccount: (cfg) =>
        (cfg as { marker?: string }).marker === "source"
          ? {
              name: "Primary",
              enabled: true,
              configured: true,
              botToken: "",
              appToken: "",
              botTokenSource: "config",
              appTokenSource: "config",
              botTokenStatus: "configured_unavailable",
              appTokenStatus: "configured_unavailable",
            }
          : {
              name: "Primary",
              enabled: true,
              configured: false,
              botToken: "",
              appToken: "",
              botTokenSource: "none",
              appTokenSource: "none",
            },
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        botToken: "",
        appToken: "",
      }),
      isConfigured: (account) => Boolean((account as { configured?: boolean }).configured),
      isEnabled: () => true,
    },
  });
}

function makeSourceUnavailableResolvedAvailablePlugin(): ChannelPlugin {
  return {
    id: "discord",
    meta: {
      id: "discord",
      label: "Discord",
      selectionLabel: "Discord",
      docsPath: "/channels/discord",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      inspectAccount: (cfg) =>
        (cfg as { marker?: string }).marker === "source"
          ? {
              name: "Primary",
              enabled: true,
              configured: true,
              tokenSource: "config",
              tokenStatus: "configured_unavailable",
            }
          : {
              name: "Primary",
              enabled: true,
              configured: true,
              tokenSource: "config",
              tokenStatus: "available",
            },
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        configured: true,
        tokenSource: "config",
        tokenStatus: "available",
      }),
      isConfigured: (account) => Boolean((account as { configured?: boolean }).configured),
      isEnabled: () => true,
    },
    actions: {
      listActions: () => ["send"],
    },
  };
}

function makeHttpSlackUnavailablePlugin(): ChannelPlugin {
  return makeDirectPlugin({
    id: "slack",
    label: "Slack",
    docsPath: "/channels/slack",
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      inspectAccount: () => ({
        accountId: "primary",
        name: "Primary",
        enabled: true,
        configured: true,
        mode: "http",
        botToken: "xoxb-http",
        signingSecret: "",
        botTokenSource: "config",
        signingSecretSource: "config", // pragma: allowlist secret
        botTokenStatus: "available",
        signingSecretStatus: "configured_unavailable", // pragma: allowlist secret
      }),
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        configured: true,
        mode: "http",
        botToken: "xoxb-http",
        signingSecret: "",
        botTokenSource: "config",
        signingSecretSource: "config", // pragma: allowlist secret
        botTokenStatus: "available",
        signingSecretStatus: "configured_unavailable", // pragma: allowlist secret
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
  });
}

function makeTokenPlugin(): ChannelPlugin {
  return makeDirectPlugin({
    id: "token-only",
    label: "TokenOnly",
    docsPath: "/channels/token-only",
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        token: "token-value",
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
  });
}

(deftest-group "buildChannelsTable - mattermost token summary", () => {
  (deftest "does not require appToken for mattermost accounts", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([makeMattermostPlugin()]);

    const table = await buildChannelsTable({ channels: {} } as never, {
      showSecrets: false,
    });

    const mattermostRow = table.rows.find((row) => row.id === "mattermost");
    (expect* mattermostRow).toBeDefined();
    (expect* mattermostRow?.state).is("ok");
    (expect* mattermostRow?.detail).not.contains("need bot+app");
  });

  (deftest "keeps bot+app requirement when both fields exist", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([
      makeSlackPlugin({ botToken: "bot-token", appToken: "" }),
    ]);

    const table = await buildChannelsTable({ channels: {} } as never, {
      showSecrets: false,
    });

    const slackRow = table.rows.find((row) => row.id === "slack");
    (expect* slackRow).toBeDefined();
    (expect* slackRow?.state).is("warn");
    (expect* slackRow?.detail).contains("need bot+app");
  });

  (deftest "reports configured-but-unavailable Slack credentials as warn", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([makeUnavailableSlackPlugin()]);

    const table = await buildChannelsTable({ channels: {} } as never, {
      showSecrets: false,
    });

    const slackRow = table.rows.find((row) => row.id === "slack");
    (expect* slackRow).toBeDefined();
    (expect* slackRow?.state).is("warn");
    (expect* slackRow?.detail).contains("unavailable in this command path");
  });

  (deftest "preserves unavailable credential state from the source config snapshot", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([makeSourceAwareUnavailablePlugin()]);

    const table = await buildChannelsTable({ marker: "resolved", channels: {} } as never, {
      showSecrets: false,
      sourceConfig: { marker: "source", channels: {} } as never,
    });

    const slackRow = table.rows.find((row) => row.id === "slack");
    (expect* slackRow).toBeDefined();
    (expect* slackRow?.state).is("warn");
    (expect* slackRow?.detail).contains("unavailable in this command path");

    const slackDetails = table.details.find((detail) => detail.title === "Slack accounts");
    (expect* slackDetails).toBeDefined();
    (expect* slackDetails?.rows).is-equal([
      {
        Account: "primary (Primary)",
        Notes: "bot:config · app:config · secret unavailable in this command path",
        Status: "WARN",
      },
    ]);
  });

  (deftest "treats status-only available credentials as resolved", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([makeSourceUnavailableResolvedAvailablePlugin()]);

    const table = await buildChannelsTable({ marker: "resolved", channels: {} } as never, {
      showSecrets: false,
      sourceConfig: { marker: "source", channels: {} } as never,
    });

    const discordRow = table.rows.find((row) => row.id === "discord");
    (expect* discordRow).toBeDefined();
    (expect* discordRow?.state).is("ok");
    (expect* discordRow?.detail).is("configured");

    const discordDetails = table.details.find((detail) => detail.title === "Discord accounts");
    (expect* discordDetails).toBeDefined();
    (expect* discordDetails?.rows).is-equal([
      {
        Account: "primary (Primary)",
        Notes: "token:config",
        Status: "OK",
      },
    ]);
  });

  (deftest "treats Slack HTTP signing-secret availability as required config", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([makeHttpSlackUnavailablePlugin()]);

    const table = await buildChannelsTable({ channels: {} } as never, {
      showSecrets: false,
    });

    const slackRow = table.rows.find((row) => row.id === "slack");
    (expect* slackRow).toBeDefined();
    (expect* slackRow?.state).is("warn");
    (expect* slackRow?.detail).contains("configured http credentials unavailable");

    const slackDetails = table.details.find((detail) => detail.title === "Slack accounts");
    (expect* slackDetails).toBeDefined();
    (expect* slackDetails?.rows).is-equal([
      {
        Account: "primary (Primary)",
        Notes: "bot:config · signing:config · secret unavailable in this command path",
        Status: "WARN",
      },
    ]);
  });

  (deftest "still reports single-token channels as ok", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([makeTokenPlugin()]);

    const table = await buildChannelsTable({ channels: {} } as never, {
      showSecrets: false,
    });

    const tokenRow = table.rows.find((row) => row.id === "token-only");
    (expect* tokenRow).toBeDefined();
    (expect* tokenRow?.state).is("ok");
    (expect* tokenRow?.detail).contains("token");
  });
});
