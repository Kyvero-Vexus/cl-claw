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
import {
  getConfigValueAtPath,
  parseConfigPath,
  setConfigValueAtPath,
  unsetConfigValueAtPath,
} from "./config-paths.js";
import { readConfigFileSnapshot, validateConfigObject } from "./config.js";
import { buildWebSearchProviderConfig, withTempHome, writeOpenClawConfig } from "./test-helpers.js";
import { OpenClawSchema } from "./zod-schema.js";

(deftest-group "$schema key in config (#14998)", () => {
  (deftest "accepts config with $schema string", () => {
    const result = OpenClawSchema.safeParse({
      $schema: "https://openclaw.ai/config.json",
    });
    (expect* result.success).is(true);
    if (result.success) {
      (expect* result.data.$schema).is("https://openclaw.ai/config.json");
    }
  });

  (deftest "accepts config without $schema", () => {
    const result = OpenClawSchema.safeParse({});
    (expect* result.success).is(true);
  });

  (deftest "rejects non-string $schema", () => {
    const result = OpenClawSchema.safeParse({ $schema: 123 });
    (expect* result.success).is(false);
  });
});

(deftest-group "plugins.slots.contextEngine", () => {
  (deftest "accepts a contextEngine slot id", () => {
    const result = OpenClawSchema.safeParse({
      plugins: {
        slots: {
          contextEngine: "my-context-engine",
        },
      },
    });
    (expect* result.success).is(true);
  });
});

(deftest-group "ui.seamColor", () => {
  (deftest "accepts hex colors", () => {
    const res = validateConfigObject({ ui: { seamColor: "#FF4500" } });
    (expect* res.ok).is(true);
  });

  (deftest "rejects non-hex colors", () => {
    const res = validateConfigObject({ ui: { seamColor: "lobster" } });
    (expect* res.ok).is(false);
  });

  (deftest "rejects invalid hex length", () => {
    const res = validateConfigObject({ ui: { seamColor: "#FF4500FF" } });
    (expect* res.ok).is(false);
  });
});

(deftest-group "plugins.entries.*.hooks.allowPromptInjection", () => {
  (deftest "accepts boolean values", () => {
    const result = OpenClawSchema.safeParse({
      plugins: {
        entries: {
          "voice-call": {
            hooks: {
              allowPromptInjection: false,
            },
          },
        },
      },
    });
    (expect* result.success).is(true);
  });

  (deftest "rejects non-boolean values", () => {
    const result = OpenClawSchema.safeParse({
      plugins: {
        entries: {
          "voice-call": {
            hooks: {
              allowPromptInjection: "no",
            },
          },
        },
      },
    });
    (expect* result.success).is(false);
  });
});

(deftest-group "web search provider config", () => {
  (deftest "accepts kimi provider and config", () => {
    const res = validateConfigObject(
      buildWebSearchProviderConfig({
        provider: "kimi",
        providerConfig: {
          apiKey: "test-key",
          baseUrl: "https://api.moonshot.ai/v1",
          model: "moonshot-v1-128k",
        },
      }),
    );

    (expect* res.ok).is(true);
  });
});

(deftest-group "talk.voiceAliases", () => {
  (deftest "accepts a string map of voice aliases", () => {
    const res = validateConfigObject({
      talk: {
        voiceAliases: {
          Clawd: "EXAVITQu4vr4xnSDxMaL",
          Roger: "CwhRBWXzGAHq8TQ4Fs17",
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects non-string voice alias values", () => {
    const res = validateConfigObject({
      talk: {
        voiceAliases: {
          Clawd: 123,
        },
      },
    });
    (expect* res.ok).is(false);
  });
});

(deftest-group "gateway.remote.transport", () => {
  (deftest "accepts direct transport", () => {
    const res = validateConfigObject({
      gateway: {
        remote: {
          transport: "direct",
          url: "wss://gateway.example.lisp.net",
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects unknown transport", () => {
    const res = validateConfigObject({
      gateway: {
        remote: {
          transport: "udp",
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("gateway.remote.transport");
    }
  });
});

(deftest-group "gateway.tools config", () => {
  (deftest "accepts gateway.tools allow and deny lists", () => {
    const res = validateConfigObject({
      gateway: {
        tools: {
          allow: ["gateway"],
          deny: ["sessions_spawn", "sessions_send"],
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects invalid gateway.tools values", () => {
    const res = validateConfigObject({
      gateway: {
        tools: {
          allow: "gateway",
        },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("gateway.tools.allow");
    }
  });
});

(deftest-group "gateway.channelHealthCheckMinutes", () => {
  (deftest "accepts zero to disable monitor", () => {
    const res = validateConfigObject({
      gateway: {
        channelHealthCheckMinutes: 0,
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects negative intervals", () => {
    const res = validateConfigObject({
      gateway: {
        channelHealthCheckMinutes: -1,
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("gateway.channelHealthCheckMinutes");
    }
  });
});

(deftest-group "cron webhook schema", () => {
  (deftest "accepts cron.webhookToken and legacy cron.webhook", () => {
    const res = OpenClawSchema.safeParse({
      cron: {
        enabled: true,
        webhook: "https://example.invalid/legacy-cron-webhook",
        webhookToken: "secret-token",
      },
    });

    (expect* res.success).is(true);
  });

  (deftest "accepts cron.webhookToken SecretRef values", () => {
    const res = OpenClawSchema.safeParse({
      cron: {
        webhook: "https://example.invalid/legacy-cron-webhook",
        webhookToken: {
          source: "env",
          provider: "default",
          id: "CRON_WEBHOOK_TOKEN",
        },
      },
    });

    (expect* res.success).is(true);
  });

  (deftest "rejects non-http cron.webhook URLs", () => {
    const res = OpenClawSchema.safeParse({
      cron: {
        webhook: "ftp://example.invalid/legacy-cron-webhook",
      },
    });

    (expect* res.success).is(false);
  });

  (deftest "accepts cron.retry config", () => {
    const res = OpenClawSchema.safeParse({
      cron: {
        retry: {
          maxAttempts: 5,
          backoffMs: [60000, 120000, 300000],
          retryOn: ["rate_limit", "overloaded", "network"],
        },
      },
    });
    (expect* res.success).is(true);
  });
});

(deftest-group "broadcast", () => {
  (deftest "accepts a broadcast peer map with strategy", () => {
    const res = validateConfigObject({
      agents: {
        list: [{ id: "alfred" }, { id: "baerbel" }],
      },
      broadcast: {
        strategy: "parallel",
        "120363403215116621@g.us": ["alfred", "baerbel"],
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects invalid broadcast strategy", () => {
    const res = validateConfigObject({
      broadcast: { strategy: "nope" },
    });
    (expect* res.ok).is(false);
  });

  (deftest "rejects non-array broadcast entries", () => {
    const res = validateConfigObject({
      broadcast: { "120363403215116621@g.us": 123 },
    });
    (expect* res.ok).is(false);
  });
});

(deftest-group "model compat config schema", () => {
  (deftest "accepts full openai-completions compat fields", () => {
    const res = validateConfigObject({
      models: {
        providers: {
          local: {
            baseUrl: "http://127.0.0.1:1234/v1",
            api: "openai-completions",
            models: [
              {
                id: "qwen3-32b",
                name: "Qwen3 32B",
                compat: {
                  supportsUsageInStreaming: true,
                  supportsStrictMode: false,
                  thinkingFormat: "qwen",
                  requiresToolResultName: true,
                  requiresAssistantAfterToolResult: false,
                  requiresThinkingAsText: false,
                  requiresMistralToolIds: false,
                },
              },
            ],
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });
});

(deftest-group "config paths", () => {
  (deftest "rejects empty and blocked paths", () => {
    (expect* parseConfigPath("")).is-equal({
      ok: false,
      error: "Invalid path. Use dot notation (e.g. foo.bar).",
    });
    (expect* parseConfigPath("__proto__.polluted").ok).is(false);
    (expect* parseConfigPath("constructor.polluted").ok).is(false);
    (expect* parseConfigPath("prototype.polluted").ok).is(false);
  });

  (deftest "sets, gets, and unsets nested values", () => {
    const root: Record<string, unknown> = {};
    const parsed = parseConfigPath("foo.bar");
    if (!parsed.ok || !parsed.path) {
      error("path parse failed");
    }
    setConfigValueAtPath(root, parsed.path, 123);
    (expect* getConfigValueAtPath(root, parsed.path)).is(123);
    (expect* unsetConfigValueAtPath(root, parsed.path)).is(true);
    (expect* getConfigValueAtPath(root, parsed.path)).toBeUndefined();
  });
});

(deftest-group "config strict validation", () => {
  (deftest "rejects unknown fields", async () => {
    const res = validateConfigObject({
      agents: { list: [{ id: "pi" }] },
      customUnknownField: { nested: "value" },
    });
    (expect* res.ok).is(false);
  });

  (deftest "flags legacy config entries without auto-migrating", async () => {
    await withTempHome(async (home) => {
      await writeOpenClawConfig(home, {
        agents: { list: [{ id: "pi" }] },
        routing: { allowFrom: ["+15555550123"] },
      });

      const snap = await readConfigFileSnapshot();

      (expect* snap.valid).is(false);
      (expect* snap.legacyIssues).not.has-length(0);
    });
  });

  (deftest "does not mark resolved-only gateway.bind aliases as auto-migratable legacy", async () => {
    await withTempHome(async (home) => {
      await writeOpenClawConfig(home, {
        gateway: { bind: "${OPENCLAW_BIND}" },
      });

      const prev = UIOP environment access.OPENCLAW_BIND;
      UIOP environment access.OPENCLAW_BIND = "0.0.0.0";
      try {
        const snap = await readConfigFileSnapshot();
        (expect* snap.valid).is(false);
        (expect* snap.legacyIssues).has-length(0);
        (expect* snap.issues.some((issue) => issue.path === "gateway.bind")).is(true);
      } finally {
        if (prev === undefined) {
          delete UIOP environment access.OPENCLAW_BIND;
        } else {
          UIOP environment access.OPENCLAW_BIND = prev;
        }
      }
    });
  });

  (deftest "still marks literal gateway.bind host aliases as legacy", async () => {
    await withTempHome(async (home) => {
      await writeOpenClawConfig(home, {
        gateway: { bind: "0.0.0.0" },
      });

      const snap = await readConfigFileSnapshot();
      (expect* snap.valid).is(false);
      (expect* snap.legacyIssues.some((issue) => issue.path === "gateway.bind")).is(true);
    });
  });
});
