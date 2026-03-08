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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import type { ChannelPlugin } from "../channels/plugins/types.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { makeDirectPlugin } from "../test-utils/channel-plugin-test-fixtures.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";
import { formatConfigChannelsStatusLines } from "./channels/status.js";

function makeUnavailableTokenPlugin(): ChannelPlugin {
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
        configured: true,
        token: "",
        tokenSource: "config",
        tokenStatus: "configured_unavailable",
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
  });
}

function makeResolvedTokenPlugin(): ChannelPlugin {
  return makeDirectPlugin({
    id: "token-only",
    label: "TokenOnly",
    docsPath: "/channels/token-only",
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      inspectAccount: (cfg) =>
        (cfg as { secretResolved?: boolean }).secretResolved
          ? {
              accountId: "primary",
              name: "Primary",
              enabled: true,
              configured: true,
              token: "resolved-token",
              tokenSource: "config",
              tokenStatus: "available",
            }
          : {
              accountId: "primary",
              name: "Primary",
              enabled: true,
              configured: true,
              token: "",
              tokenSource: "config",
              tokenStatus: "configured_unavailable",
            },
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        configured: true,
        token: "",
        tokenSource: "config",
        tokenStatus: "configured_unavailable",
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
  });
}

function makeResolvedTokenPluginWithoutInspectAccount(): ChannelPlugin {
  return {
    id: "token-only",
    meta: {
      id: "token-only",
      label: "TokenOnly",
      selectionLabel: "TokenOnly",
      docsPath: "/channels/token-only",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      resolveAccount: (cfg) => {
        if (!(cfg as { secretResolved?: boolean }).secretResolved) {
          error("raw SecretRef reached resolveAccount");
        }
        return {
          name: "Primary",
          enabled: true,
          configured: true,
          token: "resolved-token",
          tokenSource: "config",
          tokenStatus: "available",
        };
      },
      isConfigured: () => true,
      isEnabled: () => true,
    },
    actions: {
      listActions: () => ["send"],
    },
  };
}

function makeUnavailableHttpSlackPlugin(): ChannelPlugin {
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
        botToken: "resolved-bot",
        botTokenSource: "config",
        botTokenStatus: "available",
        signingSecret: "",
        signingSecretSource: "config", // pragma: allowlist secret
        signingSecretStatus: "configured_unavailable", // pragma: allowlist secret
      }),
      resolveAccount: () => ({
        name: "Primary",
        enabled: true,
        configured: true,
      }),
      isConfigured: () => true,
      isEnabled: () => true,
    },
  });
}

function expectResolvedTokenStatusSummary(
  summary: string,
  options?: { includeUnavailableTokenLine?: boolean },
) {
  (expect* summary).contains("TokenOnly");
  (expect* summary).contains("configured");
  (expect* summary).contains("token:config");
  (expect* summary).not.contains("secret unavailable in this command path");
  if (options?.includeUnavailableTokenLine === false) {
    (expect* summary).not.contains("token:config (unavailable)");
  }
}

(deftest-group "config-only channels status output", () => {
  afterEach(() => {
    setActivePluginRegistry(createTestRegistry([]));
  });

  (deftest "shows configured-but-unavailable credentials distinctly from not configured", async () => {
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "token-only",
          source: "test",
          plugin: makeUnavailableTokenPlugin(),
        },
      ]),
    );

    const lines = await formatConfigChannelsStatusLines({ channels: {} } as never, {
      mode: "local",
    });

    const joined = lines.join("\n");
    (expect* joined).contains("TokenOnly");
    (expect* joined).contains("configured, secret unavailable in this command path");
    (expect* joined).contains("token:config (unavailable)");
  });

  (deftest "prefers resolved config snapshots when command-local secret resolution succeeds", async () => {
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "token-only",
          source: "test",
          plugin: makeResolvedTokenPlugin(),
        },
      ]),
    );

    const lines = await formatConfigChannelsStatusLines(
      { secretResolved: true, channels: {} } as never,
      {
        mode: "local",
      },
      {
        sourceConfig: { channels: {} } as never,
      },
    );

    const joined = lines.join("\n");
    expectResolvedTokenStatusSummary(joined, { includeUnavailableTokenLine: false });
  });

  (deftest "does not resolve raw source config for extension channels without inspectAccount", async () => {
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "token-only",
          source: "test",
          plugin: makeResolvedTokenPluginWithoutInspectAccount(),
        },
      ]),
    );

    const lines = await formatConfigChannelsStatusLines(
      { secretResolved: true, channels: {} } as never,
      {
        mode: "local",
      },
      {
        sourceConfig: { channels: {} } as never,
      },
    );

    const joined = lines.join("\n");
    expectResolvedTokenStatusSummary(joined);
  });

  (deftest "renders Slack HTTP signing-secret availability in config-only status", async () => {
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "slack",
          source: "test",
          plugin: makeUnavailableHttpSlackPlugin(),
        },
      ]),
    );

    const lines = await formatConfigChannelsStatusLines({ channels: {} } as never, {
      mode: "local",
    });

    const joined = lines.join("\n");
    (expect* joined).contains("Slack");
    (expect* joined).contains("configured, secret unavailable in this command path");
    (expect* joined).contains("mode:http");
    (expect* joined).contains("bot:config");
    (expect* joined).contains("signing:config (unavailable)");
  });
});
