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
import type { OpenClawConfig } from "./config.js";
import { migrateLegacyConfig, validateConfigObject } from "./config.js";
import { WHISPER_BASE_AUDIO_MODEL } from "./legacy-migrate.test-helpers.js";

function getLegacyRouting(config: unknown) {
  return (config as { routing?: Record<string, unknown> } | undefined)?.routing;
}

function getChannelConfig(config: unknown, provider: string) {
  const channels = (config as { channels?: Record<string, Record<string, unknown>> } | undefined)
    ?.channels;
  return channels?.[provider];
}

(deftest-group "legacy config detection", () => {
  (deftest "rejects legacy routing keys", async () => {
    const cases = [
      {
        name: "routing.allowFrom",
        input: { routing: { allowFrom: ["+15555550123"] } },
        expectedPath: "routing.allowFrom",
      },
      {
        name: "routing.groupChat.requireMention",
        input: { routing: { groupChat: { requireMention: false } } },
        expectedPath: "routing.groupChat.requireMention",
      },
    ] as const;
    for (const testCase of cases) {
      const res = validateConfigObject(testCase.input);
      (expect* res.ok, testCase.name).is(false);
      if (!res.ok) {
        (expect* res.issues[0]?.path, testCase.name).is(testCase.expectedPath);
      }
    }
  });

  (deftest "migrates or drops routing.allowFrom based on whatsapp configuration", async () => {
    const cases = [
      {
        name: "whatsapp configured",
        input: { routing: { allowFrom: ["+15555550123"] }, channels: { whatsapp: {} } },
        expectedChange: "Moved routing.allowFrom → channels.whatsapp.allowFrom.",
        expectWhatsappAllowFrom: true,
      },
      {
        name: "whatsapp missing",
        input: { routing: { allowFrom: ["+15555550123"] } },
        expectedChange: "Removed routing.allowFrom (channels.whatsapp not configured).",
        expectWhatsappAllowFrom: false,
      },
    ] as const;
    for (const testCase of cases) {
      const res = migrateLegacyConfig(testCase.input);
      (expect* res.changes, testCase.name).contains(testCase.expectedChange);
      if (testCase.expectWhatsappAllowFrom) {
        (expect* res.config?.channels?.whatsapp?.allowFrom, testCase.name).is-equal(["+15555550123"]);
      } else {
        (expect* res.config?.channels?.whatsapp, testCase.name).toBeUndefined();
      }
      (expect* getLegacyRouting(res.config)?.allowFrom, testCase.name).toBeUndefined();
    }
  });

  (deftest "migrates routing.groupChat.requireMention to provider group defaults", async () => {
    const cases = [
      {
        name: "whatsapp configured",
        input: { routing: { groupChat: { requireMention: false } }, channels: { whatsapp: {} } },
        expectWhatsapp: true,
      },
      {
        name: "whatsapp missing",
        input: { routing: { groupChat: { requireMention: false } } },
        expectWhatsapp: false,
      },
    ] as const;
    for (const testCase of cases) {
      const res = migrateLegacyConfig(testCase.input);
      (expect* res.changes, testCase.name).contains(
        'Moved routing.groupChat.requireMention → channels.telegram.groups."*".requireMention.',
      );
      (expect* res.changes, testCase.name).contains(
        'Moved routing.groupChat.requireMention → channels.imessage.groups."*".requireMention.',
      );
      if (testCase.expectWhatsapp) {
        (expect* res.changes, testCase.name).contains(
          'Moved routing.groupChat.requireMention → channels.whatsapp.groups."*".requireMention.',
        );
        (expect* res.config?.channels?.whatsapp?.groups?.["*"]?.requireMention, testCase.name).is(
          false,
        );
      } else {
        (expect* res.changes, testCase.name).not.contains(
          'Moved routing.groupChat.requireMention → channels.whatsapp.groups."*".requireMention.',
        );
        (expect* res.config?.channels?.whatsapp, testCase.name).toBeUndefined();
      }
      (expect* res.config?.channels?.telegram?.groups?.["*"]?.requireMention, testCase.name).is(
        false,
      );
      (expect* res.config?.channels?.imessage?.groups?.["*"]?.requireMention, testCase.name).is(
        false,
      );
      (expect* getLegacyRouting(res.config)?.groupChat, testCase.name).toBeUndefined();
    }
  });
  (deftest "migrates routing.groupChat.mentionPatterns to messages.groupChat.mentionPatterns", async () => {
    const res = migrateLegacyConfig({
      routing: { groupChat: { mentionPatterns: ["@openclaw"] } },
    });
    (expect* res.changes).contains(
      "Moved routing.groupChat.mentionPatterns → messages.groupChat.mentionPatterns.",
    );
    (expect* res.config?.messages?.groupChat?.mentionPatterns).is-equal(["@openclaw"]);
    (expect* getLegacyRouting(res.config)?.groupChat).toBeUndefined();
  });
  (deftest "migrates routing agentToAgent/queue/transcribeAudio to tools/messages/media", async () => {
    const res = migrateLegacyConfig({
      routing: {
        agentToAgent: { enabled: true, allow: ["main"] },
        queue: { mode: "queue", cap: 3 },
        transcribeAudio: {
          command: ["whisper", "--model", "base"],
          timeoutSeconds: 2,
        },
      },
    });
    (expect* res.changes).contains("Moved routing.agentToAgent → tools.agentToAgent.");
    (expect* res.changes).contains("Moved routing.queue → messages.queue.");
    (expect* res.changes).contains("Moved routing.transcribeAudio → tools.media.audio.models.");
    (expect* res.config?.tools?.agentToAgent).is-equal({
      enabled: true,
      allow: ["main"],
    });
    (expect* res.config?.messages?.queue).is-equal({
      mode: "queue",
      cap: 3,
    });
    (expect* res.config?.tools?.media?.audio).is-equal(WHISPER_BASE_AUDIO_MODEL);
    (expect* getLegacyRouting(res.config)).toBeUndefined();
  });
  (deftest "migrates audio.transcription with custom script names", async () => {
    const res = migrateLegacyConfig({
      audio: {
        transcription: {
          command: ["/home/user/.scripts/whisperx-transcribe.sh"],
          timeoutSeconds: 120,
        },
      },
    });
    (expect* res.changes).contains("Moved audio.transcription → tools.media.audio.models.");
    (expect* res.config?.tools?.media?.audio).is-equal({
      enabled: true,
      models: [
        {
          command: "/home/user/.scripts/whisperx-transcribe.sh",
          type: "cli",
          timeoutSeconds: 120,
        },
      ],
    });
    (expect* res.config?.audio).toBeUndefined();
  });
  (deftest "rejects audio.transcription when command contains non-string parts", async () => {
    const res = migrateLegacyConfig({
      audio: {
        transcription: {
          command: [{}],
          timeoutSeconds: 120,
        },
      },
    });
    (expect* res.changes).contains("Removed audio.transcription (invalid or empty command).");
    (expect* res.config?.tools?.media?.audio).toBeUndefined();
    (expect* res.config?.audio).toBeUndefined();
  });
  (deftest "migrates agent config into agents.defaults and tools", async () => {
    const res = migrateLegacyConfig({
      agent: {
        model: "openai/gpt-5.2",
        tools: { allow: ["sessions.list"], deny: ["danger"] },
        elevated: { enabled: true, allowFrom: { discord: ["user:1"] } },
        bash: { timeoutSec: 12 },
        sandbox: { tools: { allow: ["browser.open"] } },
        subagents: { tools: { deny: ["sandbox"] } },
      },
    });
    (expect* res.changes).contains("Moved agent.tools.allow → tools.allow.");
    (expect* res.changes).contains("Moved agent.tools.deny → tools.deny.");
    (expect* res.changes).contains("Moved agent.elevated → tools.elevated.");
    (expect* res.changes).contains("Moved agent.bash → tools.exec.");
    (expect* res.changes).contains("Moved agent.sandbox.tools → tools.sandbox.tools.");
    (expect* res.changes).contains("Moved agent.subagents.tools → tools.subagents.tools.");
    (expect* res.changes).contains("Moved agent → agents.defaults.");
    (expect* res.config?.agents?.defaults?.model).is-equal({
      primary: "openai/gpt-5.2",
      fallbacks: [],
    });
    (expect* res.config?.tools?.allow).is-equal(["sessions.list"]);
    (expect* res.config?.tools?.deny).is-equal(["danger"]);
    (expect* res.config?.tools?.elevated).is-equal({
      enabled: true,
      allowFrom: { discord: ["user:1"] },
    });
    (expect* res.config?.tools?.exec).is-equal({ timeoutSec: 12 });
    (expect* res.config?.tools?.sandbox?.tools).is-equal({
      allow: ["browser.open"],
    });
    (expect* res.config?.tools?.subagents?.tools).is-equal({
      deny: ["sandbox"],
    });
    (expect* (res.config as { agent?: unknown }).agent).toBeUndefined();
  });
  (deftest "migrates top-level memorySearch to agents.defaults.memorySearch", async () => {
    const res = migrateLegacyConfig({
      memorySearch: {
        provider: "local",
        fallback: "none",
        query: { maxResults: 7 },
      },
    });
    (expect* res.changes).contains("Moved memorySearch → agents.defaults.memorySearch.");
    (expect* res.config?.agents?.defaults?.memorySearch).matches-object({
      provider: "local",
      fallback: "none",
      query: { maxResults: 7 },
    });
    (expect* (res.config as { memorySearch?: unknown }).memorySearch).toBeUndefined();
  });
  (deftest "merges top-level memorySearch into agents.defaults.memorySearch", async () => {
    const res = migrateLegacyConfig({
      memorySearch: {
        provider: "local",
        fallback: "none",
        query: { maxResults: 7 },
      },
      agents: {
        defaults: {
          memorySearch: {
            provider: "openai",
            model: "text-embedding-3-small",
          },
        },
      },
    });
    (expect* res.changes).contains(
      "Merged memorySearch → agents.defaults.memorySearch (filled missing fields from legacy; kept explicit agents.defaults values).",
    );
    (expect* res.config?.agents?.defaults?.memorySearch).matches-object({
      provider: "openai",
      model: "text-embedding-3-small",
      fallback: "none",
      query: { maxResults: 7 },
    });
  });
  (deftest "keeps nested agents.defaults.memorySearch values when merging legacy defaults", async () => {
    const res = migrateLegacyConfig({
      memorySearch: {
        query: {
          maxResults: 7,
          minScore: 0.25,
          hybrid: { enabled: true, textWeight: 0.8, vectorWeight: 0.2 },
        },
      },
      agents: {
        defaults: {
          memorySearch: {
            query: {
              maxResults: 3,
              hybrid: { enabled: false },
            },
          },
        },
      },
    });

    (expect* res.config?.agents?.defaults?.memorySearch).matches-object({
      query: {
        maxResults: 3,
        minScore: 0.25,
        hybrid: { enabled: false, textWeight: 0.8, vectorWeight: 0.2 },
      },
    });
  });
  (deftest "migrates tools.bash to tools.exec", async () => {
    const res = migrateLegacyConfig({
      tools: {
        bash: { timeoutSec: 12 },
      },
    });
    (expect* res.changes).contains("Moved tools.bash → tools.exec.");
    (expect* res.config?.tools?.exec).is-equal({ timeoutSec: 12 });
    (expect* (res.config?.tools as { bash?: unknown } | undefined)?.bash).toBeUndefined();
  });
  (deftest "accepts per-agent tools.elevated overrides", async () => {
    const res = validateConfigObject({
      tools: {
        elevated: {
          allowFrom: { whatsapp: ["+15555550123"] },
        },
      },
      agents: {
        list: [
          {
            id: "work",
            workspace: "~/openclaw-work",
            tools: {
              elevated: {
                enabled: false,
                allowFrom: { whatsapp: ["+15555550123"] },
              },
            },
          },
        ],
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config?.agents?.list?.[0]?.tools?.elevated).is-equal({
        enabled: false,
        allowFrom: { whatsapp: ["+15555550123"] },
      });
    }
  });
  (deftest "rejects telegram.requireMention", async () => {
    const res = validateConfigObject({
      telegram: { requireMention: true },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((issue) => issue.path === "telegram.requireMention")).is(true);
    }
  });
  (deftest "rejects gateway.token", async () => {
    const res = validateConfigObject({
      gateway: { token: "legacy-token" },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("gateway.token");
    }
  });
  (deftest "migrates gateway.token to gateway.auth.token", async () => {
    const res = migrateLegacyConfig({
      gateway: { token: "legacy-token" },
    });
    (expect* res.changes).contains("Moved gateway.token → gateway.auth.token.");
    (expect* res.config?.gateway?.auth?.token).is("legacy-token");
    (expect* res.config?.gateway?.auth?.mode).is("token");
    (expect* (res.config?.gateway as { token?: string })?.token).toBeUndefined();
  });
  (deftest "keeps gateway.bind tailnet", async () => {
    const res = migrateLegacyConfig({
      gateway: { bind: "tailnet" as const },
    });
    (expect* res.changes).not.contains("Migrated gateway.bind from 'tailnet' to 'auto'.");
    (expect* res.config?.gateway?.bind).is("tailnet");
    (expect* res.config?.gateway?.controlUi?.allowedOrigins).is-equal([
      "http://localhost:18789",
      "http://127.0.0.1:18789",
    ]);

    const validated = validateConfigObject({ gateway: { bind: "tailnet" as const } });
    (expect* validated.ok).is(true);
    if (validated.ok) {
      (expect* validated.config.gateway?.bind).is("tailnet");
    }
  });
  (deftest "normalizes gateway.bind host aliases to supported bind modes", async () => {
    const cases = [
      { input: "0.0.0.0", expected: "lan" },
      { input: "::", expected: "lan" },
      { input: "127.0.0.1", expected: "loopback" },
      { input: "localhost", expected: "loopback" },
      { input: "::1", expected: "loopback" },
    ] as const;

    for (const testCase of cases) {
      const res = migrateLegacyConfig({
        gateway: { bind: testCase.input },
      });
      (expect* res.changes).contains(
        `Normalized gateway.bind "${testCase.input}" → "${testCase.expected}".`,
      );
      (expect* res.config?.gateway?.bind).is(testCase.expected);

      const validated = validateConfigObject(res.config);
      (expect* validated.ok).is(true);
      if (validated.ok) {
        (expect* validated.config.gateway?.bind).is(testCase.expected);
      }
    }
  });
  (deftest "flags gateway.bind host aliases as legacy to trigger auto-migration paths", async () => {
    const cases = ["0.0.0.0", "::", "127.0.0.1", "localhost", "::1"] as const;
    for (const bind of cases) {
      const validated = validateConfigObject({ gateway: { bind } });
      (expect* validated.ok, bind).is(false);
      if (!validated.ok) {
        (expect* 
          validated.issues.some((issue) => issue.path === "gateway.bind"),
          bind,
        ).is(true);
      }
    }
  });
  (deftest "escapes control characters in gateway.bind migration change text", async () => {
    const res = migrateLegacyConfig({
      gateway: { bind: "\r\n0.0.0.0\r\n" },
    });
    (expect* res.changes).contains('Normalized gateway.bind "\\r\\n0.0.0.0\\r\\n" → "lan".');
  });
  (deftest 'enforces dmPolicy="open" allowFrom wildcard for supported providers', async () => {
    const cases = [
      {
        provider: "telegram",
        allowFrom: ["123456789"],
        expectedIssuePath: "channels.telegram.allowFrom",
      },
      {
        provider: "whatsapp",
        allowFrom: ["+15555550123"],
        expectedIssuePath: "channels.whatsapp.allowFrom",
      },
      {
        provider: "signal",
        allowFrom: ["+15555550123"],
        expectedIssuePath: "channels.signal.allowFrom",
      },
      {
        provider: "imessage",
        allowFrom: ["+15555550123"],
        expectedIssuePath: "channels.imessage.allowFrom",
      },
    ] as const;
    for (const testCase of cases) {
      const res = validateConfigObject({
        channels: {
          [testCase.provider]: { dmPolicy: "open", allowFrom: testCase.allowFrom },
        },
      });
      (expect* res.ok, testCase.provider).is(false);
      if (!res.ok) {
        (expect* res.issues[0]?.path, testCase.provider).is(testCase.expectedIssuePath);
      }
    }
  });

  (deftest 'accepts dmPolicy="open" when allowFrom includes wildcard', async () => {
    const providers = ["telegram", "whatsapp", "signal"] as const;
    for (const provider of providers) {
      const res = validateConfigObject({
        channels: { [provider]: { dmPolicy: "open", allowFrom: ["*"] } },
      });
      (expect* res.ok, provider).is(true);
      if (res.ok) {
        const channel = getChannelConfig(res.config, provider);
        (expect* channel?.dmPolicy, provider).is("open");
      }
    }
  });

  (deftest "defaults dm/group policy for configured providers", async () => {
    const providers = ["telegram", "whatsapp", "signal"] as const;
    for (const provider of providers) {
      const res = validateConfigObject({ channels: { [provider]: {} } });
      (expect* res.ok, provider).is(true);
      if (res.ok) {
        const channel = getChannelConfig(res.config, provider);
        (expect* channel?.dmPolicy, provider).is("pairing");
        (expect* channel?.groupPolicy, provider).is("allowlist");
        if (provider === "telegram") {
          (expect* channel?.streaming, provider).is("partial");
          (expect* channel?.streamMode, provider).toBeUndefined();
        }
      }
    }
  });
  (deftest "normalizes telegram legacy streamMode aliases", async () => {
    const cases = [
      {
        name: "top-level off",
        input: { channels: { telegram: { streamMode: "off" } } },
        expectedTopLevel: "off",
      },
      {
        name: "top-level block",
        input: { channels: { telegram: { streamMode: "block" } } },
        expectedTopLevel: "block",
      },
      {
        name: "per-account off",
        input: {
          channels: {
            telegram: {
              accounts: {
                ops: {
                  streamMode: "off",
                },
              },
            },
          },
        },
        expectedAccountStreaming: "off",
      },
    ] as const;
    for (const testCase of cases) {
      const res = validateConfigObject(testCase.input);
      (expect* res.ok, testCase.name).is(true);
      if (res.ok) {
        if ("expectedTopLevel" in testCase && testCase.expectedTopLevel !== undefined) {
          (expect* res.config.channels?.telegram?.streaming, testCase.name).is(
            testCase.expectedTopLevel,
          );
          (expect* res.config.channels?.telegram?.streamMode, testCase.name).toBeUndefined();
        }
        if (
          "expectedAccountStreaming" in testCase &&
          testCase.expectedAccountStreaming !== undefined
        ) {
          (expect* res.config.channels?.telegram?.accounts?.ops?.streaming, testCase.name).is(
            testCase.expectedAccountStreaming,
          );
          (expect* 
            res.config.channels?.telegram?.accounts?.ops?.streamMode,
            testCase.name,
          ).toBeUndefined();
        }
      }
    }
  });

  (deftest "normalizes discord streaming fields during legacy migration", async () => {
    const cases = [
      {
        name: "boolean streaming=true",
        input: { channels: { discord: { streaming: true } } },
        expectedChanges: ["Normalized channels.discord.streaming boolean → enum (partial)."],
        expectedStreaming: "partial",
      },
      {
        name: "streamMode with streaming boolean",
        input: { channels: { discord: { streaming: false, streamMode: "block" } } },
        expectedChanges: [
          "Moved channels.discord.streamMode → channels.discord.streaming (block).",
          "Normalized channels.discord.streaming boolean → enum (block).",
        ],
        expectedStreaming: "block",
      },
    ] as const;
    for (const testCase of cases) {
      const res = migrateLegacyConfig(testCase.input);
      for (const expectedChange of testCase.expectedChanges) {
        (expect* res.changes, testCase.name).contains(expectedChange);
      }
      (expect* res.config?.channels?.discord?.streaming, testCase.name).is(
        testCase.expectedStreaming,
      );
      (expect* res.config?.channels?.discord?.streamMode, testCase.name).toBeUndefined();
    }
  });

  (deftest "normalizes discord streaming fields during validation", async () => {
    const cases = [
      {
        name: "streaming=true",
        input: { channels: { discord: { streaming: true } } },
        expectedStreaming: "partial",
      },
      {
        name: "streaming=false",
        input: { channels: { discord: { streaming: false } } },
        expectedStreaming: "off",
      },
      {
        name: "streamMode overrides streaming boolean",
        input: { channels: { discord: { streamMode: "block", streaming: false } } },
        expectedStreaming: "block",
      },
    ] as const;
    for (const testCase of cases) {
      const res = validateConfigObject(testCase.input);
      (expect* res.ok, testCase.name).is(true);
      if (res.ok) {
        (expect* res.config.channels?.discord?.streaming, testCase.name).is(
          testCase.expectedStreaming,
        );
        (expect* res.config.channels?.discord?.streamMode, testCase.name).toBeUndefined();
      }
    }
  });
  (deftest "normalizes account-level discord and slack streaming aliases", async () => {
    const cases = [
      {
        name: "discord account streaming boolean",
        input: {
          channels: {
            discord: {
              accounts: {
                work: {
                  streaming: true,
                },
              },
            },
          },
        },
        assert: (config: NonNullable<OpenClawConfig>) => {
          (expect* config.channels?.discord?.accounts?.work?.streaming).is("partial");
          (expect* config.channels?.discord?.accounts?.work?.streamMode).toBeUndefined();
        },
      },
      {
        name: "slack streamMode alias",
        input: {
          channels: {
            slack: {
              streamMode: "status_final",
            },
          },
        },
        assert: (config: NonNullable<OpenClawConfig>) => {
          (expect* config.channels?.slack?.streaming).is("progress");
          (expect* config.channels?.slack?.streamMode).toBeUndefined();
          (expect* config.channels?.slack?.nativeStreaming).is(true);
        },
      },
      {
        name: "slack streaming boolean legacy",
        input: {
          channels: {
            slack: {
              streaming: false,
            },
          },
        },
        assert: (config: NonNullable<OpenClawConfig>) => {
          (expect* config.channels?.slack?.streaming).is("off");
          (expect* config.channels?.slack?.nativeStreaming).is(false);
        },
      },
    ] as const;
    for (const testCase of cases) {
      const res = validateConfigObject(testCase.input);
      (expect* res.ok, testCase.name).is(true);
      if (res.ok) {
        testCase.assert(res.config);
      }
    }
  });
  (deftest "accepts historyLimit overrides per provider and account", async () => {
    const res = validateConfigObject({
      messages: { groupChat: { historyLimit: 12 } },
      channels: {
        whatsapp: { historyLimit: 9, accounts: { work: { historyLimit: 4 } } },
        telegram: { historyLimit: 8, accounts: { ops: { historyLimit: 3 } } },
        slack: { historyLimit: 7, accounts: { ops: { historyLimit: 2 } } },
        signal: { historyLimit: 6 },
        imessage: { historyLimit: 5 },
        msteams: { historyLimit: 4 },
        discord: { historyLimit: 3 },
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.channels?.whatsapp?.historyLimit).is(9);
      (expect* res.config.channels?.whatsapp?.accounts?.work?.historyLimit).is(4);
      (expect* res.config.channels?.telegram?.historyLimit).is(8);
      (expect* res.config.channels?.telegram?.accounts?.ops?.historyLimit).is(3);
      (expect* res.config.channels?.slack?.historyLimit).is(7);
      (expect* res.config.channels?.slack?.accounts?.ops?.historyLimit).is(2);
      (expect* res.config.channels?.signal?.historyLimit).is(6);
      (expect* res.config.channels?.imessage?.historyLimit).is(5);
      (expect* res.config.channels?.msteams?.historyLimit).is(4);
      (expect* res.config.channels?.discord?.historyLimit).is(3);
    }
  });
});
