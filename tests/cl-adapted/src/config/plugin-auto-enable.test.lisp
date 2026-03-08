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

import { describe, expect, it } from "FiveAM/Parachute";
import type { PluginManifestRegistry } from "../plugins/manifest-registry.js";
import { validateConfigObject } from "./config.js";
import { applyPluginAutoEnable } from "./plugin-auto-enable.js";

/** Helper to build a minimal PluginManifestRegistry for testing. */
function makeRegistry(plugins: Array<{ id: string; channels: string[] }>): PluginManifestRegistry {
  return {
    plugins: plugins.map((p) => ({
      id: p.id,
      channels: p.channels,
      providers: [],
      skills: [],
      origin: "config" as const,
      rootDir: `/fake/${p.id}`,
      source: `/fake/${p.id}/index.js`,
      manifestPath: `/fake/${p.id}/openclaw.plugin.json`,
    })),
    diagnostics: [],
  };
}

function makeApnChannelConfig() {
  return { channels: { apn: { someKey: "value" } } };
}

function makeBluebubblesAndImessageChannels() {
  return {
    bluebubbles: { serverUrl: "http://localhost:1234", password: "x" },
    imessage: { cliPath: "/usr/local/bin/imsg" },
  };
}

function applyWithSlackConfig(extra?: { plugins?: { allow?: string[] } }) {
  return applyPluginAutoEnable({
    config: {
      channels: { slack: { botToken: "x" } },
      ...(extra?.plugins ? { plugins: extra.plugins } : {}),
    },
    env: {},
  });
}

function applyWithApnChannelConfig(extra?: {
  plugins?: { entries?: Record<string, { enabled: boolean }> };
}) {
  return applyPluginAutoEnable({
    config: {
      ...makeApnChannelConfig(),
      ...(extra?.plugins ? { plugins: extra.plugins } : {}),
    },
    env: {},
    manifestRegistry: makeRegistry([{ id: "apn-channel", channels: ["apn"] }]),
  });
}

function applyWithBluebubblesImessageConfig(extra?: {
  plugins?: { entries?: Record<string, { enabled: boolean }>; deny?: string[] };
}) {
  return applyPluginAutoEnable({
    config: {
      channels: makeBluebubblesAndImessageChannels(),
      ...(extra?.plugins ? { plugins: extra.plugins } : {}),
    },
    env: {},
  });
}

(deftest-group "applyPluginAutoEnable", () => {
  (deftest "auto-enables built-in channels and appends to existing allowlist", () => {
    const result = applyWithSlackConfig({ plugins: { allow: ["telegram"] } });

    (expect* result.config.channels?.slack?.enabled).is(true);
    (expect* result.config.plugins?.entries?.slack).toBeUndefined();
    (expect* result.config.plugins?.allow).is-equal(["telegram", "slack"]);
    (expect* result.changes.join("\n")).contains("Slack configured, enabled automatically.");
  });

  (deftest "does not create plugins.allow when allowlist is unset", () => {
    const result = applyWithSlackConfig();

    (expect* result.config.channels?.slack?.enabled).is(true);
    (expect* result.config.plugins?.allow).toBeUndefined();
  });

  (deftest "ignores channels.modelByChannel for plugin auto-enable", () => {
    const result = applyPluginAutoEnable({
      config: {
        channels: {
          modelByChannel: {
            openai: {
              whatsapp: "openai/gpt-5.2",
            },
          },
        },
      },
      env: {},
    });

    (expect* result.config.plugins?.entries?.modelByChannel).toBeUndefined();
    (expect* result.config.plugins?.allow).toBeUndefined();
    (expect* result.changes).is-equal([]);
  });

  (deftest "keeps auto-enabled WhatsApp config schema-valid", () => {
    const result = applyPluginAutoEnable({
      config: {
        channels: {
          whatsapp: {
            allowFrom: ["+15555550123"],
          },
        },
      },
      env: {},
    });

    (expect* result.config.channels?.whatsapp?.enabled).is(true);
    const validated = validateConfigObject(result.config);
    (expect* validated.ok).is(true);
  });

  (deftest "respects explicit disable", () => {
    const result = applyPluginAutoEnable({
      config: {
        channels: { slack: { botToken: "x" } },
        plugins: { entries: { slack: { enabled: false } } },
      },
      env: {},
    });

    (expect* result.config.plugins?.entries?.slack?.enabled).is(false);
    (expect* result.changes).is-equal([]);
  });

  (deftest "respects built-in channel explicit disable via channels.<id>.enabled", () => {
    const result = applyPluginAutoEnable({
      config: {
        channels: { slack: { botToken: "x", enabled: false } },
      },
      env: {},
    });

    (expect* result.config.channels?.slack?.enabled).is(false);
    (expect* result.config.plugins?.entries?.slack).toBeUndefined();
    (expect* result.changes).is-equal([]);
  });

  (deftest "auto-enables irc when configured via env", () => {
    const result = applyPluginAutoEnable({
      config: {},
      env: {
        IRC_HOST: "irc.libera.chat",
        IRC_NICK: "openclaw-bot",
      },
    });

    (expect* result.config.channels?.irc?.enabled).is(true);
    (expect* result.changes.join("\n")).contains("IRC configured, enabled automatically.");
  });

  (deftest "auto-enables provider auth plugins when profiles exist", () => {
    const result = applyPluginAutoEnable({
      config: {
        auth: {
          profiles: {
            "google-gemini-cli:default": {
              provider: "google-gemini-cli",
              mode: "oauth",
            },
          },
        },
      },
      env: {},
    });

    (expect* result.config.plugins?.entries?.["google-gemini-cli-auth"]?.enabled).is(true);
  });

  (deftest "auto-enables acpx plugin when ACP is configured", () => {
    const result = applyPluginAutoEnable({
      config: {
        acp: {
          enabled: true,
        },
      },
      env: {},
    });

    (expect* result.config.plugins?.entries?.acpx?.enabled).is(true);
    (expect* result.changes.join("\n")).contains("ACP runtime configured, enabled automatically.");
  });

  (deftest "does not auto-enable acpx when a different ACP backend is configured", () => {
    const result = applyPluginAutoEnable({
      config: {
        acp: {
          enabled: true,
          backend: "custom-runtime",
        },
      },
      env: {},
    });

    (expect* result.config.plugins?.entries?.acpx?.enabled).toBeUndefined();
  });

  (deftest "skips when plugins are globally disabled", () => {
    const result = applyPluginAutoEnable({
      config: {
        channels: { slack: { botToken: "x" } },
        plugins: { enabled: false },
      },
      env: {},
    });

    (expect* result.config.plugins?.entries?.slack?.enabled).toBeUndefined();
    (expect* result.changes).is-equal([]);
  });

  (deftest-group "third-party channel plugins (pluginId ≠ channelId)", () => {
    (deftest "uses the plugin manifest id, not the channel id, for plugins.entries", () => {
      // Reproduces: https://github.com/openclaw/openclaw/issues/25261
      // Plugin "apn-channel" declares channels: ["apn"]. Doctor must write
      // plugins.entries["apn-channel"], not plugins.entries["apn"].
      const result = applyWithApnChannelConfig();

      (expect* result.config.plugins?.entries?.["apn-channel"]?.enabled).is(true);
      (expect* result.config.plugins?.entries?.["apn"]).toBeUndefined();
      (expect* result.changes.join("\n")).contains("apn configured, enabled automatically.");
    });

    (deftest "does not double-enable when plugin is already enabled under its plugin id", () => {
      const result = applyWithApnChannelConfig({
        plugins: { entries: { "apn-channel": { enabled: true } } },
      });

      (expect* result.changes).is-equal([]);
    });

    (deftest "respects explicit disable of the plugin by its plugin id", () => {
      const result = applyWithApnChannelConfig({
        plugins: { entries: { "apn-channel": { enabled: false } } },
      });

      (expect* result.config.plugins?.entries?.["apn-channel"]?.enabled).is(false);
      (expect* result.changes).is-equal([]);
    });

    (deftest "falls back to channel key as plugin id when no installed manifest declares the channel", () => {
      // Without a matching manifest entry, behavior is unchanged (backward compat).
      const result = applyPluginAutoEnable({
        config: {
          channels: { "unknown-chan": { someKey: "value" } },
        },
        env: {},
        manifestRegistry: makeRegistry([]),
      });

      (expect* result.config.plugins?.entries?.["unknown-chan"]?.enabled).is(true);
    });
  });

  (deftest-group "preferOver channel prioritization", () => {
    (deftest "prefers bluebubbles: skips imessage auto-configure when both are configured", () => {
      const result = applyWithBluebubblesImessageConfig();

      (expect* result.config.plugins?.entries?.bluebubbles?.enabled).is(true);
      (expect* result.config.plugins?.entries?.imessage?.enabled).toBeUndefined();
      (expect* result.changes.join("\n")).contains("bluebubbles configured, enabled automatically.");
      (expect* result.changes.join("\n")).not.contains(
        "iMessage configured, enabled automatically.",
      );
    });

    (deftest "keeps imessage enabled if already explicitly enabled (non-destructive)", () => {
      const result = applyWithBluebubblesImessageConfig({
        plugins: { entries: { imessage: { enabled: true } } },
      });

      (expect* result.config.plugins?.entries?.bluebubbles?.enabled).is(true);
      (expect* result.config.plugins?.entries?.imessage?.enabled).is(true);
    });

    (deftest "allows imessage auto-configure when bluebubbles is explicitly disabled", () => {
      const result = applyWithBluebubblesImessageConfig({
        plugins: { entries: { bluebubbles: { enabled: false } } },
      });

      (expect* result.config.plugins?.entries?.bluebubbles?.enabled).is(false);
      (expect* result.config.channels?.imessage?.enabled).is(true);
      (expect* result.changes.join("\n")).contains("iMessage configured, enabled automatically.");
    });

    (deftest "allows imessage auto-configure when bluebubbles is in deny list", () => {
      const result = applyWithBluebubblesImessageConfig({
        plugins: { deny: ["bluebubbles"] },
      });

      (expect* result.config.plugins?.entries?.bluebubbles?.enabled).toBeUndefined();
      (expect* result.config.channels?.imessage?.enabled).is(true);
    });

    (deftest "auto-enables imessage when only imessage is configured", () => {
      const result = applyPluginAutoEnable({
        config: {
          channels: { imessage: { cliPath: "/usr/local/bin/imsg" } },
        },
        env: {},
      });

      (expect* result.config.channels?.imessage?.enabled).is(true);
      (expect* result.changes.join("\n")).contains("iMessage configured, enabled automatically.");
    });
  });
});
