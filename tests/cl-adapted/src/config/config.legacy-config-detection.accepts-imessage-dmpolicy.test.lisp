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

import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveAgentModelFallbackValues, resolveAgentModelPrimaryValue } from "./model-input.js";

const { loadConfig, migrateLegacyConfig, readConfigFileSnapshot, validateConfigObject } =
  await mock:importActual<typeof import("./config.js")>("./config.js");
import { withTempHome } from "./test-helpers.js";

async function expectLoadRejectionPreservesField(params: {
  config: unknown;
  readValue: (parsed: unknown) => unknown;
  expectedValue: unknown;
}) {
  await withTempHome(async (home) => {
    const configPath = path.join(home, ".openclaw", "openclaw.json");
    await fs.mkdir(path.dirname(configPath), { recursive: true });
    await fs.writeFile(configPath, JSON.stringify(params.config, null, 2), "utf-8");

    const snap = await readConfigFileSnapshot();

    (expect* snap.valid).is(false);
    (expect* snap.issues.length).toBeGreaterThan(0);

    const parsed = JSON.parse(await fs.readFile(configPath, "utf-8")) as unknown;
    (expect* params.readValue(parsed)).is(params.expectedValue);
  });
}

type ConfigSnapshot = Awaited<ReturnType<typeof readConfigFileSnapshot>>;

async function withSnapshotForConfig(
  config: unknown,
  run: (params: { snapshot: ConfigSnapshot; parsed: unknown; configPath: string }) => deferred-result<void>,
) {
  await withTempHome(async (home) => {
    const configPath = path.join(home, ".openclaw", "openclaw.json");
    await fs.mkdir(path.dirname(configPath), { recursive: true });
    await fs.writeFile(configPath, JSON.stringify(config, null, 2), "utf-8");
    const snapshot = await readConfigFileSnapshot();
    const parsed = JSON.parse(await fs.readFile(configPath, "utf-8")) as unknown;
    await run({ snapshot, parsed, configPath });
  });
}

function expectValidConfigValue(params: {
  config: unknown;
  readValue: (config: unknown) => unknown;
  expectedValue: unknown;
}) {
  const res = validateConfigObject(params.config);
  (expect* res.ok).is(true);
  if (!res.ok) {
    error("expected config to be valid");
  }
  (expect* params.readValue(res.config)).is(params.expectedValue);
}

function expectInvalidIssuePath(config: unknown, expectedPath: string) {
  const res = validateConfigObject(config);
  (expect* res.ok).is(false);
  if (!res.ok) {
    (expect* res.issues[0]?.path).is(expectedPath);
  }
}

function expectRoutingAllowFromLegacySnapshot(
  ctx: { snapshot: ConfigSnapshot; parsed: unknown },
  expectedAllowFrom: string[],
) {
  (expect* ctx.snapshot.valid).is(false);
  (expect* ctx.snapshot.legacyIssues.some((issue) => issue.path === "routing.allowFrom")).is(true);
  const parsed = ctx.parsed as {
    routing?: { allowFrom?: string[] };
    channels?: unknown;
  };
  (expect* parsed.routing?.allowFrom).is-equal(expectedAllowFrom);
  (expect* parsed.channels).toBeUndefined();
}

(deftest-group "legacy config detection", () => {
  (deftest 'accepts imessage.dmPolicy="open" with allowFrom "*"', async () => {
    const res = validateConfigObject({
      channels: { imessage: { dmPolicy: "open", allowFrom: ["*"] } },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.channels?.imessage?.dmPolicy).is("open");
    }
  });
  it.each([
    [
      "defaults imessage.dmPolicy to pairing when imessage section exists",
      { channels: { imessage: {} } },
      (config: unknown) =>
        (config as { channels?: { imessage?: { dmPolicy?: string } } }).channels?.imessage
          ?.dmPolicy,
      "pairing",
    ],
    [
      "defaults imessage.groupPolicy to allowlist when imessage section exists",
      { channels: { imessage: {} } },
      (config: unknown) =>
        (config as { channels?: { imessage?: { groupPolicy?: string } } }).channels?.imessage
          ?.groupPolicy,
      "allowlist",
    ],
    [
      "defaults discord.groupPolicy to allowlist when discord section exists",
      { channels: { discord: {} } },
      (config: unknown) =>
        (config as { channels?: { discord?: { groupPolicy?: string } } }).channels?.discord
          ?.groupPolicy,
      "allowlist",
    ],
    [
      "defaults slack.groupPolicy to allowlist when slack section exists",
      { channels: { slack: {} } },
      (config: unknown) =>
        (config as { channels?: { slack?: { groupPolicy?: string } } }).channels?.slack
          ?.groupPolicy,
      "allowlist",
    ],
    [
      "defaults msteams.groupPolicy to allowlist when msteams section exists",
      { channels: { msteams: {} } },
      (config: unknown) =>
        (config as { channels?: { msteams?: { groupPolicy?: string } } }).channels?.msteams
          ?.groupPolicy,
      "allowlist",
    ],
  ])("defaults: %s", (_name, config, readValue, expectedValue) => {
    expectValidConfigValue({ config, readValue, expectedValue });
  });
  (deftest "rejects unsafe executable config values", async () => {
    const res = validateConfigObject({
      channels: { imessage: { cliPath: "imsg; rm -rf /" } },
      audio: { transcription: { command: ["whisper", "--model", "base"] } },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path === "channels.imessage.cliPath")).is(true);
    }
  });
  (deftest "accepts tools audio transcription without cli", async () => {
    const res = validateConfigObject({
      audio: { transcription: { command: ["whisper", "--model", "base"] } },
    });
    (expect* res.ok).is(true);
  });
  (deftest "accepts path-like executable values with spaces", async () => {
    const res = validateConfigObject({
      channels: { imessage: { cliPath: "/Applications/Imsg Tools/imsg" } },
      audio: {
        transcription: {
          command: ["whisper", "--model"],
        },
      },
    });
    (expect* res.ok).is(true);
  });
  it.each([
    [
      'rejects discord.dm.policy="open" without allowFrom "*"',
      { channels: { discord: { dm: { policy: "open", allowFrom: ["123"] } } } },
      "channels.discord.dm.allowFrom",
    ],
    [
      'rejects discord.dmPolicy="open" without allowFrom "*"',
      { channels: { discord: { dmPolicy: "open", allowFrom: ["123"] } } },
      "channels.discord.allowFrom",
    ],
    [
      'rejects slack.dm.policy="open" without allowFrom "*"',
      { channels: { slack: { dm: { policy: "open", allowFrom: ["U123"] } } } },
      "channels.slack.dm.allowFrom",
    ],
    [
      'rejects slack.dmPolicy="open" without allowFrom "*"',
      { channels: { slack: { dmPolicy: "open", allowFrom: ["U123"] } } },
      "channels.slack.allowFrom",
    ],
  ])("rejects: %s", (_name, config, expectedPath) => {
    expectInvalidIssuePath(config, expectedPath);
  });

  it.each([
    {
      name: 'accepts discord dm.allowFrom="*" with top-level allowFrom alias',
      config: {
        channels: { discord: { dm: { policy: "open", allowFrom: ["123"] }, allowFrom: ["*"] } },
      },
    },
    {
      name: 'accepts slack dm.allowFrom="*" with top-level allowFrom alias',
      config: {
        channels: { slack: { dm: { policy: "open", allowFrom: ["U123"] }, allowFrom: ["*"] } },
      },
    },
  ])("$name", ({ config }) => {
    const res = validateConfigObject(config);
    (expect* res.ok).is(true);
  });
  (deftest "rejects legacy agent.model string", async () => {
    const res = validateConfigObject({
      agent: { model: "anthropic/claude-opus-4-5" },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path === "agent.model")).is(true);
    }
  });
  (deftest "migrates telegram.requireMention to channels.telegram.groups.*.requireMention", async () => {
    const res = migrateLegacyConfig({
      telegram: { requireMention: false },
    });
    (expect* res.changes).contains(
      'Moved telegram.requireMention → channels.telegram.groups."*".requireMention.',
    );
    (expect* res.config?.channels?.telegram?.groups?.["*"]?.requireMention).is(false);
    (expect* 
      (res.config?.channels?.telegram as { requireMention?: boolean } | undefined)?.requireMention,
    ).toBeUndefined();
  });
  (deftest "migrates messages.tts.enabled to messages.tts.auto", async () => {
    const res = migrateLegacyConfig({
      messages: { tts: { enabled: true } },
    });
    (expect* res.changes).contains("Moved messages.tts.enabled → messages.tts.auto (always).");
    (expect* res.config?.messages?.tts?.auto).is("always");
    (expect* res.config?.messages?.tts?.enabled).toBeUndefined();
  });
  (deftest "migrates legacy model config to agent.models + model lists", async () => {
    const res = migrateLegacyConfig({
      agent: {
        model: "anthropic/claude-opus-4-5",
        modelFallbacks: ["openai/gpt-4.1-mini"],
        imageModel: "openai/gpt-4.1-mini",
        imageModelFallbacks: ["anthropic/claude-opus-4-5"],
        allowedModels: ["anthropic/claude-opus-4-5", "openai/gpt-4.1-mini"],
        modelAliases: { Opus: "anthropic/claude-opus-4-5" },
      },
    });

    (expect* resolveAgentModelPrimaryValue(res.config?.agents?.defaults?.model)).is(
      "anthropic/claude-opus-4-5",
    );
    (expect* resolveAgentModelFallbackValues(res.config?.agents?.defaults?.model)).is-equal([
      "openai/gpt-4.1-mini",
    ]);
    (expect* resolveAgentModelPrimaryValue(res.config?.agents?.defaults?.imageModel)).is(
      "openai/gpt-4.1-mini",
    );
    (expect* resolveAgentModelFallbackValues(res.config?.agents?.defaults?.imageModel)).is-equal([
      "anthropic/claude-opus-4-5",
    ]);
    (expect* res.config?.agents?.defaults?.models?.["anthropic/claude-opus-4-5"]).matches-object({
      alias: "Opus",
    });
    (expect* res.config?.agents?.defaults?.models?.["openai/gpt-4.1-mini"]).is-truthy();
    (expect* (res.config as { agent?: unknown } | undefined)?.agent).toBeUndefined();
  });
  (deftest "flags legacy config in snapshot", async () => {
    await withSnapshotForConfig({ routing: { allowFrom: ["+15555550123"] } }, async (ctx) => {
      expectRoutingAllowFromLegacySnapshot(ctx, ["+15555550123"]);
    });
  });
  (deftest "flags top-level memorySearch as legacy in snapshot", async () => {
    await withSnapshotForConfig(
      { memorySearch: { provider: "local", fallback: "none" } },
      async (ctx) => {
        (expect* ctx.snapshot.valid).is(false);
        (expect* ctx.snapshot.legacyIssues.some((issue) => issue.path === "memorySearch")).is(true);
      },
    );
  });
  (deftest "flags top-level heartbeat as legacy in snapshot", async () => {
    await withSnapshotForConfig(
      { heartbeat: { model: "anthropic/claude-3-5-haiku-20241022", every: "30m" } },
      async (ctx) => {
        (expect* ctx.snapshot.valid).is(false);
        (expect* ctx.snapshot.legacyIssues.some((issue) => issue.path === "heartbeat")).is(true);
      },
    );
  });
  (deftest "flags legacy provider sections in snapshot", async () => {
    await withSnapshotForConfig({ whatsapp: { allowFrom: ["+1555"] } }, async (ctx) => {
      (expect* ctx.snapshot.valid).is(false);
      (expect* ctx.snapshot.legacyIssues.some((issue) => issue.path === "whatsapp")).is(true);

      const parsed = ctx.parsed as {
        channels?: unknown;
        whatsapp?: unknown;
      };
      (expect* parsed.channels).toBeUndefined();
      (expect* parsed.whatsapp).is-truthy();
    });
  });
  (deftest "does not auto-migrate claude-cli auth profile mode on load", async () => {
    await withTempHome(async (home) => {
      const configPath = path.join(home, ".openclaw", "openclaw.json");
      await fs.mkdir(path.dirname(configPath), { recursive: true });
      await fs.writeFile(
        configPath,
        JSON.stringify(
          {
            auth: {
              profiles: {
                "anthropic:claude-cli": { provider: "anthropic", mode: "token" },
              },
            },
          },
          null,
          2,
        ),
        "utf-8",
      );

      const cfg = loadConfig();
      (expect* cfg.auth?.profiles?.["anthropic:claude-cli"]?.mode).is("token");

      const raw = await fs.readFile(configPath, "utf-8");
      const parsed = JSON.parse(raw) as {
        auth?: { profiles?: Record<string, { mode?: string }> };
      };
      (expect* parsed.auth?.profiles?.["anthropic:claude-cli"]?.mode).is("token");
    });
  });
  (deftest "flags routing.allowFrom in snapshot", async () => {
    await withSnapshotForConfig({ routing: { allowFrom: ["+1666"] } }, async (ctx) => {
      expectRoutingAllowFromLegacySnapshot(ctx, ["+1666"]);
    });
  });
  (deftest "rejects bindings[].match.provider on load", async () => {
    await expectLoadRejectionPreservesField({
      config: {
        bindings: [{ agentId: "main", match: { provider: "slack" } }],
      },
      readValue: (parsed) =>
        (parsed as { bindings?: Array<{ match?: { provider?: string } }> }).bindings?.[0]?.match
          ?.provider,
      expectedValue: "slack",
    });
  });
  (deftest "rejects bindings[].match.accountID on load", async () => {
    await expectLoadRejectionPreservesField({
      config: {
        bindings: [{ agentId: "main", match: { channel: "telegram", accountID: "work" } }],
      },
      readValue: (parsed) =>
        (parsed as { bindings?: Array<{ match?: { accountID?: string } }> }).bindings?.[0]?.match
          ?.accountID,
      expectedValue: "work",
    });
  });
  (deftest "accepts bindings[].comment on load", () => {
    expectValidConfigValue({
      config: {
        bindings: [{ agentId: "main", comment: "primary route", match: { channel: "telegram" } }],
      },
      readValue: (config) =>
        (config as { bindings?: Array<{ comment?: string }> }).bindings?.[0]?.comment,
      expectedValue: "primary route",
    });
  });
  (deftest "rejects session.sendPolicy.rules[].match.provider on load", async () => {
    await withSnapshotForConfig(
      {
        session: {
          sendPolicy: {
            rules: [{ action: "deny", match: { provider: "telegram" } }],
          },
        },
      },
      async (ctx) => {
        (expect* ctx.snapshot.valid).is(false);
        (expect* ctx.snapshot.issues.length).toBeGreaterThan(0);
        const parsed = ctx.parsed as {
          session?: { sendPolicy?: { rules?: Array<{ match?: { provider?: string } }> } };
        };
        (expect* parsed.session?.sendPolicy?.rules?.[0]?.match?.provider).is("telegram");
      },
    );
  });
  (deftest "rejects messages.queue.byProvider on load", async () => {
    await withSnapshotForConfig(
      { messages: { queue: { byProvider: { whatsapp: "queue" } } } },
      async (ctx) => {
        (expect* ctx.snapshot.valid).is(false);
        (expect* ctx.snapshot.issues.length).toBeGreaterThan(0);

        const parsed = ctx.parsed as {
          messages?: {
            queue?: {
              byProvider?: Record<string, unknown>;
            };
          };
        };
        (expect* parsed.messages?.queue?.byProvider?.whatsapp).is("queue");
      },
    );
  });
});
