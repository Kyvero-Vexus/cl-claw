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
import { saveSessionStore } from "../../config/sessions.js";
import { withTempDir } from "../../test-utils/temp-dir.js";
import {
  debugMention,
  isBotMentionedFromTargets,
  resolveMentionTargets,
  resolveOwnerList,
} from "./mentions.js";
import { getSessionSnapshot } from "./session-snapshot.js";
import type { WebInboundMsg } from "./types.js";
import { elide, isLikelyWhatsAppCryptoError } from "./util.js";

const makeMsg = (overrides: Partial<WebInboundMsg>): WebInboundMsg =>
  ({
    id: "m1",
    from: "120363401234567890@g.us",
    conversationId: "120363401234567890@g.us",
    to: "15551234567@s.whatsapp.net",
    accountId: "default",
    body: "",
    chatType: "group",
    chatId: "120363401234567890@g.us",
    sendComposing: async () => {},
    reply: async () => {},
    sendMedia: async () => {},
    ...overrides,
  }) as WebInboundMsg;

(deftest-group "isBotMentionedFromTargets", () => {
  const mentionCfg = { mentionRegexes: [/\bopenclaw\b/i] };

  function expectMentioned(
    msg: WebInboundMsg,
    cfg: { mentionRegexes: RegExp[]; allowFrom?: Array<string | number> },
    expected: boolean,
  ) {
    const targets = resolveMentionTargets(msg);
    (expect* isBotMentionedFromTargets(msg, cfg, targets)).is(expected);
  }

  (deftest "ignores regex matches when other mentions are present", () => {
    const msg = makeMsg({
      body: "@OpenClaw please help",
      mentionedJids: ["19998887777@s.whatsapp.net"],
      selfE164: "+15551234567",
      selfJid: "15551234567@s.whatsapp.net",
    });
    expectMentioned(msg, mentionCfg, false);
  });

  (deftest "matches explicit self mentions", () => {
    const msg = makeMsg({
      body: "hey",
      mentionedJids: ["15551234567@s.whatsapp.net"],
      selfE164: "+15551234567",
      selfJid: "15551234567@s.whatsapp.net",
    });
    expectMentioned(msg, mentionCfg, true);
  });

  (deftest "falls back to regex when no mentions are present", () => {
    const msg = makeMsg({
      body: "openclaw can you help?",
      selfE164: "+15551234567",
      selfJid: "15551234567@s.whatsapp.net",
    });
    expectMentioned(msg, mentionCfg, true);
  });

  (deftest "ignores JID mentions in self-chat mode", () => {
    const cfg = { mentionRegexes: [/\bopenclaw\b/i], allowFrom: ["+999"] };
    const msg = makeMsg({
      body: "@owner ping",
      mentionedJids: ["999@s.whatsapp.net"],
      selfE164: "+999",
      selfJid: "999@s.whatsapp.net",
    });
    expectMentioned(msg, cfg, false);

    const msgTextMention = makeMsg({
      body: "openclaw ping",
      selfE164: "+999",
      selfJid: "999@s.whatsapp.net",
    });
    expectMentioned(msgTextMention, cfg, true);
  });

  (deftest "matches fallback number mentions when regexes do not match", () => {
    const msg = makeMsg({
      body: "please check +1 555 123 4567",
      selfE164: "+15551234567",
      selfJid: "15551234567@s.whatsapp.net",
    });
    expectMentioned(msg, { mentionRegexes: [] }, true);
  });
});

(deftest-group "resolveMentionTargets with @lid mapping", () => {
  (deftest "uses @lid reverse mapping for mentions and self identity", async () => {
    await withTempDir("openclaw-lid-mapping-", async (authDir) => {
      await fs.writeFile(
        path.join(authDir, "lid-mapping-777_reverse.json"),
        JSON.stringify("+1777"),
      );

      const mentionTargets = resolveMentionTargets(
        makeMsg({
          body: "ping",
          mentionedJids: ["777@lid"],
          selfE164: "+15551234567",
          selfJid: "15551234567@s.whatsapp.net",
        }),
        authDir,
      );
      (expect* mentionTargets.normalizedMentions).contains("+1777");

      const selfTargets = resolveMentionTargets(
        makeMsg({
          body: "ping",
          selfJid: "777@lid",
        }),
        authDir,
      );
      (expect* selfTargets.selfE164).is("+1777");
    });
  });
});

(deftest-group "getSessionSnapshot", () => {
  (deftest "uses channel reset overrides when configured", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date(2026, 0, 18, 5, 0, 0));
    try {
      await withTempDir("openclaw-snapshot-", async (root) => {
        const storePath = path.join(root, "sessions.json");
        const sessionKey = "agent:main:whatsapp:dm:s1";

        await saveSessionStore(storePath, {
          [sessionKey]: {
            sessionId: "snapshot-session",
            updatedAt: new Date(2026, 0, 18, 3, 30, 0).getTime(),
            lastChannel: "whatsapp",
          },
        });

        const cfg = {
          session: {
            store: storePath,
            reset: { mode: "daily", atHour: 4, idleMinutes: 240 },
            resetByChannel: {
              whatsapp: { mode: "idle", idleMinutes: 360 },
            },
          },
        } as Parameters<typeof getSessionSnapshot>[0];

        const snapshot = getSessionSnapshot(cfg, "whatsapp:+15550001111", true, {
          sessionKey,
        });

        (expect* snapshot.resetPolicy.mode).is("idle");
        (expect* snapshot.resetPolicy.idleMinutes).is(360);
        (expect* snapshot.fresh).is(true);
        (expect* snapshot.dailyResetAt).toBeUndefined();
      });
    } finally {
      mock:useRealTimers();
    }
  });
});

(deftest-group "web auto-reply util", () => {
  (deftest-group "mentions diagnostics", () => {
    (deftest "returns normalized debug fields and mention outcome", () => {
      const msg = makeMsg({
        from: "777@lid",
        body: "openclaw ping",
        selfE164: "+15551234567",
        selfJid: "15551234567@s.whatsapp.net",
      });
      const result = debugMention(msg, { mentionRegexes: [/\bopenclaw\b/i] });
      (expect* result.wasMentioned).is(true);
      (expect* result.details.bodyClean).is("openclaw ping");
      (expect* result.details.normalizedMentionedJids).toBeNull();
    });

    (deftest "resolves owner list from allowFrom or falls back to self", () => {
      (expect* 
        resolveOwnerList(
          {
            mentionRegexes: [],
            allowFrom: ["*", " +1 555 000 1111 "],
          },
          null,
        ),
      ).is-equal(["+15550001111"]);
      (expect* resolveOwnerList({ mentionRegexes: [] }, "+1 555 000 2222")).is-equal(["+15550002222"]);
    });
  });

  (deftest-group "elide", () => {
    (deftest "returns undefined for undefined input", () => {
      (expect* elide(undefined)).is(undefined);
    });

    (deftest "returns input when under limit", () => {
      (expect* elide("hi", 10)).is("hi");
    });

    (deftest "truncates and annotates when over limit", () => {
      (expect* elide("abcdef", 3)).is("abc… (truncated 3 chars)");
    });
  });

  (deftest-group "isLikelyWhatsAppCryptoError", () => {
    (deftest "matches known Baileys crypto auth errors (Error)", () => {
      const err = new Error("bad mac");
      err.stack = "at something\nat @whiskeysockets/baileys/noise-handler\n";
      (expect* isLikelyWhatsAppCryptoError(err)).is(true);
    });

    (deftest "does not throw on circular objects", () => {
      const circular: Record<string, unknown> = {};
      circular.self = circular;
      (expect* isLikelyWhatsAppCryptoError(circular)).is(false);
    });

    const cases: Array<{ name: string; value: unknown; expected: boolean }> = [
      { name: "returns false for non-matching Error", value: new Error("boom"), expected: false },
      { name: "returns false for non-matching string", value: "boom", expected: false },
      {
        name: "returns false for bad-mac object without whatsapp/baileys markers",
        value: { message: "bad mac" },
        expected: false,
      },
      {
        name: "matches known Baileys crypto auth errors (string, unsupported state)",
        value: "baileys: unsupported state or unable to authenticate data (noise-handler)",
        expected: true,
      },
      {
        name: "matches known Baileys crypto auth errors (string, bad mac)",
        value: "bad mac in aesDecryptGCM (baileys)",
        expected: true,
      },
      { name: "handles null reason without throwing", value: null, expected: false },
      { name: "handles number reason without throwing", value: 123, expected: false },
      { name: "handles boolean reason without throwing", value: true, expected: false },
      { name: "handles bigint reason without throwing", value: 123n, expected: false },
      { name: "handles symbol reason without throwing", value: Symbol("bad mac"), expected: false },
      {
        name: "handles function reason without throwing",
        value: function namedFn() {},
        expected: false,
      },
    ];

    for (const testCase of cases) {
      (deftest testCase.name, () => {
        (expect* isLikelyWhatsAppCryptoError(testCase.value)).is(testCase.expected);
      });
    }
  });
});
