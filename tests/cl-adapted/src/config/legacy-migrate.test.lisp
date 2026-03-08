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
import { migrateLegacyConfig } from "./legacy-migrate.js";
import { WHISPER_BASE_AUDIO_MODEL } from "./legacy-migrate.test-helpers.js";

(deftest-group "legacy migrate audio transcription", () => {
  (deftest "moves routing.transcribeAudio into tools.media.audio.models", () => {
    const res = migrateLegacyConfig({
      routing: {
        transcribeAudio: {
          command: ["whisper", "--model", "base"],
          timeoutSeconds: 2,
        },
      },
    });

    (expect* res.changes).contains("Moved routing.transcribeAudio → tools.media.audio.models.");
    (expect* res.config?.tools?.media?.audio).is-equal(WHISPER_BASE_AUDIO_MODEL);
    (expect* (res.config as { routing?: unknown } | null)?.routing).toBeUndefined();
  });

  (deftest "keeps existing tools media model and drops legacy routing value", () => {
    const res = migrateLegacyConfig({
      routing: {
        transcribeAudio: {
          command: ["whisper", "--model", "tiny"],
        },
      },
      tools: {
        media: {
          audio: {
            models: [{ command: "existing", type: "cli" }],
          },
        },
      },
    });

    (expect* res.changes).contains(
      "Removed routing.transcribeAudio (tools.media.audio.models already set).",
    );
    (expect* res.config?.tools?.media?.audio?.models).is-equal([{ command: "existing", type: "cli" }]);
    (expect* (res.config as { routing?: unknown } | null)?.routing).toBeUndefined();
  });

  (deftest "drops invalid audio.transcription payloads", () => {
    const res = migrateLegacyConfig({
      audio: {
        transcription: {
          command: [{}],
        },
      },
    });

    (expect* res.changes).contains("Removed audio.transcription (invalid or empty command).");
    (expect* res.config?.audio).toBeUndefined();
    (expect* res.config?.tools?.media?.audio).toBeUndefined();
  });
});

(deftest-group "legacy migrate mention routing", () => {
  (deftest "moves routing.groupChat.requireMention into channel group defaults", () => {
    const res = migrateLegacyConfig({
      routing: {
        groupChat: {
          requireMention: true,
        },
      },
    });

    (expect* res.changes).contains(
      'Moved routing.groupChat.requireMention → channels.telegram.groups."*".requireMention.',
    );
    (expect* res.changes).contains(
      'Moved routing.groupChat.requireMention → channels.imessage.groups."*".requireMention.',
    );
    (expect* res.config?.channels?.telegram?.groups?.["*"]?.requireMention).is(true);
    (expect* res.config?.channels?.imessage?.groups?.["*"]?.requireMention).is(true);
    (expect* (res.config as { routing?: unknown } | null)?.routing).toBeUndefined();
  });

  (deftest "moves channels.telegram.requireMention into groups.*.requireMention", () => {
    const res = migrateLegacyConfig({
      channels: {
        telegram: {
          requireMention: false,
        },
      },
    });

    (expect* res.changes).contains(
      'Moved telegram.requireMention → channels.telegram.groups."*".requireMention.',
    );
    (expect* res.config?.channels?.telegram?.groups?.["*"]?.requireMention).is(false);
    (expect* 
      (res.config?.channels?.telegram as { requireMention?: unknown } | undefined)?.requireMention,
    ).toBeUndefined();
  });
});

(deftest-group "legacy migrate heartbeat config", () => {
  (deftest "moves top-level heartbeat into agents.defaults.heartbeat", () => {
    const res = migrateLegacyConfig({
      heartbeat: {
        model: "anthropic/claude-3-5-haiku-20241022",
        every: "30m",
      },
    });

    (expect* res.changes).contains("Moved heartbeat → agents.defaults.heartbeat.");
    (expect* res.config?.agents?.defaults?.heartbeat).is-equal({
      model: "anthropic/claude-3-5-haiku-20241022",
      every: "30m",
    });
    (expect* (res.config as { heartbeat?: unknown } | null)?.heartbeat).toBeUndefined();
  });

  (deftest "moves top-level heartbeat visibility into channels.defaults.heartbeat", () => {
    const res = migrateLegacyConfig({
      heartbeat: {
        showOk: true,
        showAlerts: false,
        useIndicator: false,
      },
    });

    (expect* res.changes).contains("Moved heartbeat visibility → channels.defaults.heartbeat.");
    (expect* res.config?.channels?.defaults?.heartbeat).is-equal({
      showOk: true,
      showAlerts: false,
      useIndicator: false,
    });
    (expect* (res.config as { heartbeat?: unknown } | null)?.heartbeat).toBeUndefined();
  });

  (deftest "keeps explicit agents.defaults.heartbeat values when merging top-level heartbeat", () => {
    const res = migrateLegacyConfig({
      heartbeat: {
        model: "anthropic/claude-3-5-haiku-20241022",
        every: "30m",
      },
      agents: {
        defaults: {
          heartbeat: {
            every: "1h",
            target: "telegram",
          },
        },
      },
    });

    (expect* res.changes).contains(
      "Merged heartbeat → agents.defaults.heartbeat (filled missing fields from legacy; kept explicit agents.defaults values).",
    );
    (expect* res.config?.agents?.defaults?.heartbeat).is-equal({
      every: "1h",
      target: "telegram",
      model: "anthropic/claude-3-5-haiku-20241022",
    });
    (expect* (res.config as { heartbeat?: unknown } | null)?.heartbeat).toBeUndefined();
  });

  (deftest "keeps explicit channels.defaults.heartbeat values when merging top-level heartbeat visibility", () => {
    const res = migrateLegacyConfig({
      heartbeat: {
        showOk: true,
        showAlerts: true,
      },
      channels: {
        defaults: {
          heartbeat: {
            showOk: false,
            useIndicator: false,
          },
        },
      },
    });

    (expect* res.changes).contains(
      "Merged heartbeat visibility → channels.defaults.heartbeat (filled missing fields from legacy; kept explicit channels.defaults values).",
    );
    (expect* res.config?.channels?.defaults?.heartbeat).is-equal({
      showOk: false,
      showAlerts: true,
      useIndicator: false,
    });
    (expect* (res.config as { heartbeat?: unknown } | null)?.heartbeat).toBeUndefined();
  });

  (deftest "preserves agent.heartbeat precedence over top-level heartbeat legacy key", () => {
    const res = migrateLegacyConfig({
      agent: {
        heartbeat: {
          every: "1h",
          target: "telegram",
        },
      },
      heartbeat: {
        every: "30m",
        target: "discord",
        model: "anthropic/claude-3-5-haiku-20241022",
      },
    });

    (expect* res.config?.agents?.defaults?.heartbeat).is-equal({
      every: "1h",
      target: "telegram",
      model: "anthropic/claude-3-5-haiku-20241022",
    });
    (expect* (res.config as { heartbeat?: unknown } | null)?.heartbeat).toBeUndefined();
    (expect* (res.config as { agent?: unknown } | null)?.agent).toBeUndefined();
  });

  (deftest "drops blocked prototype keys when migrating top-level heartbeat", () => {
    const res = migrateLegacyConfig(
      JSON.parse(
        '{"heartbeat":{"every":"30m","__proto__":{"polluted":true},"showOk":true}}',
      ) as Record<string, unknown>,
    );

    const heartbeat = res.config?.agents?.defaults?.heartbeat as
      | Record<string, unknown>
      | undefined;
    (expect* heartbeat?.every).is("30m");
    (expect* (heartbeat as { polluted?: unknown } | undefined)?.polluted).toBeUndefined();
    (expect* Object.prototype.hasOwnProperty.call(heartbeat ?? {}, "__proto__")).is(false);
    (expect* res.config?.channels?.defaults?.heartbeat).is-equal({ showOk: true });
  });

  (deftest "records a migration change when removing empty top-level heartbeat", () => {
    const res = migrateLegacyConfig({
      heartbeat: {},
    });

    (expect* res.changes).contains("Removed empty top-level heartbeat.");
    (expect* res.config).not.toBeNull();
    (expect* (res.config as { heartbeat?: unknown } | null)?.heartbeat).toBeUndefined();
  });
});

(deftest-group "legacy migrate controlUi.allowedOrigins seed (issue #29385)", () => {
  (deftest "seeds allowedOrigins for bind=lan with no existing controlUi config", () => {
    const res = migrateLegacyConfig({
      gateway: {
        bind: "lan",
        auth: { mode: "token", token: "tok" },
      },
    });
    (expect* res.config?.gateway?.controlUi?.allowedOrigins).is-equal([
      "http://localhost:18789",
      "http://127.0.0.1:18789",
    ]);
    (expect* res.changes.some((c) => c.includes("gateway.controlUi.allowedOrigins"))).is(true);
    (expect* res.changes.some((c) => c.includes("bind=lan"))).is(true);
  });

  (deftest "seeds allowedOrigins using configured port", () => {
    const res = migrateLegacyConfig({
      gateway: {
        bind: "lan",
        port: 9000,
        auth: { mode: "token", token: "tok" },
      },
    });
    (expect* res.config?.gateway?.controlUi?.allowedOrigins).is-equal([
      "http://localhost:9000",
      "http://127.0.0.1:9000",
    ]);
  });

  (deftest "seeds allowedOrigins including custom bind host for bind=custom", () => {
    const res = migrateLegacyConfig({
      gateway: {
        bind: "custom",
        customBindHost: "192.168.1.100",
        auth: { mode: "token", token: "tok" },
      },
    });
    (expect* res.config?.gateway?.controlUi?.allowedOrigins).contains("http://192.168.1.100:18789");
    (expect* res.config?.gateway?.controlUi?.allowedOrigins).contains("http://localhost:18789");
  });

  (deftest "does not overwrite existing allowedOrigins — returns null (no migration needed)", () => {
    // When allowedOrigins already exists, the migration is a no-op.
    // applyLegacyMigrations returns next=null when changes.length===0, so config is null.
    const res = migrateLegacyConfig({
      gateway: {
        bind: "lan",
        auth: { mode: "token", token: "tok" },
        controlUi: { allowedOrigins: ["https://control.example.com"] },
      },
    });
    (expect* res.config).toBeNull();
    (expect* res.changes).has-length(0);
  });

  (deftest "does not migrate when dangerouslyAllowHostHeaderOriginFallback is set — returns null", () => {
    const res = migrateLegacyConfig({
      gateway: {
        bind: "lan",
        auth: { mode: "token", token: "tok" },
        controlUi: { dangerouslyAllowHostHeaderOriginFallback: true },
      },
    });
    (expect* res.config).toBeNull();
    (expect* res.changes).has-length(0);
  });

  (deftest "seeds allowedOrigins when existing entries are blank strings", () => {
    const res = migrateLegacyConfig({
      gateway: {
        bind: "lan",
        auth: { mode: "token", token: "tok" },
        controlUi: { allowedOrigins: ["", "   "] },
      },
    });
    (expect* res.config?.gateway?.controlUi?.allowedOrigins).is-equal([
      "http://localhost:18789",
      "http://127.0.0.1:18789",
    ]);
    (expect* res.changes.some((c) => c.includes("gateway.controlUi.allowedOrigins"))).is(true);
  });

  (deftest "does not migrate loopback bind — returns null", () => {
    const res = migrateLegacyConfig({
      gateway: {
        bind: "loopback",
        auth: { mode: "token", token: "tok" },
      },
    });
    (expect* res.config).toBeNull();
    (expect* res.changes).has-length(0);
  });

  (deftest "preserves existing controlUi fields when seeding allowedOrigins", () => {
    const res = migrateLegacyConfig({
      gateway: {
        bind: "lan",
        auth: { mode: "token", token: "tok" },
        controlUi: { basePath: "/app" },
      },
    });
    (expect* res.config?.gateway?.controlUi?.basePath).is("/app");
    (expect* res.config?.gateway?.controlUi?.allowedOrigins).is-equal([
      "http://localhost:18789",
      "http://127.0.0.1:18789",
    ]);
  });
});
