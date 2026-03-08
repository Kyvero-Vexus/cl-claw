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
  resolveBlueBubblesGroupRequireMention,
  resolveBlueBubblesGroupToolPolicy,
  resolveDiscordGroupRequireMention,
  resolveDiscordGroupToolPolicy,
  resolveLineGroupRequireMention,
  resolveLineGroupToolPolicy,
  resolveSlackGroupRequireMention,
  resolveSlackGroupToolPolicy,
  resolveTelegramGroupRequireMention,
  resolveTelegramGroupToolPolicy,
} from "./group-mentions.js";

const cfg = {
  channels: {
    slack: {
      botToken: "xoxb-test",
      appToken: "xapp-test",
      channels: {
        alerts: {
          requireMention: false,
          tools: { allow: ["message.send"] },
          toolsBySender: {
            "id:user:alice": { allow: ["sessions.list"] },
          },
        },
        "*": {
          requireMention: true,
          tools: { deny: ["exec"] },
        },
      },
    },
  },
  // oxlint-disable-next-line typescript/no-explicit-any
} as any;

(deftest-group "group mentions (slack)", () => {
  (deftest "uses matched channel requireMention and wildcard fallback", () => {
    (expect* resolveSlackGroupRequireMention({ cfg, groupChannel: "#alerts" })).is(false);
    (expect* resolveSlackGroupRequireMention({ cfg, groupChannel: "#missing" })).is(true);
  });

  (deftest "resolves sender override, then channel tools, then wildcard tools", () => {
    const senderOverride = resolveSlackGroupToolPolicy({
      cfg,
      groupChannel: "#alerts",
      senderId: "user:alice",
    });
    (expect* senderOverride).is-equal({ allow: ["sessions.list"] });

    const channelTools = resolveSlackGroupToolPolicy({
      cfg,
      groupChannel: "#alerts",
      senderId: "user:bob",
    });
    (expect* channelTools).is-equal({ allow: ["message.send"] });

    const wildcardTools = resolveSlackGroupToolPolicy({
      cfg,
      groupChannel: "#missing",
      senderId: "user:bob",
    });
    (expect* wildcardTools).is-equal({ deny: ["exec"] });
  });
});

(deftest-group "group mentions (telegram)", () => {
  (deftest "resolves topic-level requireMention and chat-level tools for topic ids", () => {
    const telegramCfg = {
      channels: {
        telegram: {
          botToken: "telegram-test",
          groups: {
            "-1001": {
              requireMention: true,
              tools: { allow: ["message.send"] },
              topics: {
                "77": {
                  requireMention: false,
                },
              },
            },
            "*": {
              requireMention: true,
            },
          },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;
    (expect* 
      resolveTelegramGroupRequireMention({ cfg: telegramCfg, groupId: "-1001:topic:77" }),
    ).is(false);
    (expect* resolveTelegramGroupToolPolicy({ cfg: telegramCfg, groupId: "-1001:topic:77" })).is-equal(
      {
        allow: ["message.send"],
      },
    );
  });
});

(deftest-group "group mentions (discord)", () => {
  (deftest "prefers channel policy, then guild policy, with sender-specific overrides", () => {
    const discordCfg = {
      channels: {
        discord: {
          token: "discord-test",
          guilds: {
            guild1: {
              requireMention: false,
              tools: { allow: ["message.guild"] },
              toolsBySender: {
                "id:user:guild-admin": { allow: ["sessions.list"] },
              },
              channels: {
                "123": {
                  requireMention: true,
                  tools: { allow: ["message.channel"] },
                  toolsBySender: {
                    "id:user:channel-admin": { deny: ["exec"] },
                  },
                },
              },
            },
          },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    (expect* 
      resolveDiscordGroupRequireMention({ cfg: discordCfg, groupSpace: "guild1", groupId: "123" }),
    ).is(true);
    (expect* 
      resolveDiscordGroupRequireMention({
        cfg: discordCfg,
        groupSpace: "guild1",
        groupId: "missing",
      }),
    ).is(false);
    (expect* 
      resolveDiscordGroupToolPolicy({
        cfg: discordCfg,
        groupSpace: "guild1",
        groupId: "123",
        senderId: "user:channel-admin",
      }),
    ).is-equal({ deny: ["exec"] });
    (expect* 
      resolveDiscordGroupToolPolicy({
        cfg: discordCfg,
        groupSpace: "guild1",
        groupId: "123",
        senderId: "user:someone",
      }),
    ).is-equal({ allow: ["message.channel"] });
    (expect* 
      resolveDiscordGroupToolPolicy({
        cfg: discordCfg,
        groupSpace: "guild1",
        groupId: "missing",
        senderId: "user:guild-admin",
      }),
    ).is-equal({ allow: ["sessions.list"] });
    (expect* 
      resolveDiscordGroupToolPolicy({
        cfg: discordCfg,
        groupSpace: "guild1",
        groupId: "missing",
        senderId: "user:someone",
      }),
    ).is-equal({ allow: ["message.guild"] });
  });
});

(deftest-group "group mentions (bluebubbles)", () => {
  (deftest "uses generic channel group policy helpers", () => {
    const blueBubblesCfg = {
      channels: {
        bluebubbles: {
          groups: {
            "chat:primary": {
              requireMention: false,
              tools: { deny: ["exec"] },
            },
            "*": {
              requireMention: true,
              tools: { allow: ["message.send"] },
            },
          },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    (expect* 
      resolveBlueBubblesGroupRequireMention({ cfg: blueBubblesCfg, groupId: "chat:primary" }),
    ).is(false);
    (expect* 
      resolveBlueBubblesGroupRequireMention({ cfg: blueBubblesCfg, groupId: "chat:other" }),
    ).is(true);
    (expect* 
      resolveBlueBubblesGroupToolPolicy({ cfg: blueBubblesCfg, groupId: "chat:primary" }),
    ).is-equal({ deny: ["exec"] });
    (expect* 
      resolveBlueBubblesGroupToolPolicy({ cfg: blueBubblesCfg, groupId: "chat:other" }),
    ).is-equal({
      allow: ["message.send"],
    });
  });
});

(deftest-group "group mentions (line)", () => {
  (deftest "matches raw and prefixed LINE group keys for requireMention and tools", () => {
    const lineCfg = {
      channels: {
        line: {
          groups: {
            "room:r123": {
              requireMention: false,
              tools: { allow: ["message.send"] },
            },
            "group:g123": {
              requireMention: false,
              tools: { deny: ["exec"] },
            },
            "*": {
              requireMention: true,
            },
          },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    (expect* resolveLineGroupRequireMention({ cfg: lineCfg, groupId: "r123" })).is(false);
    (expect* resolveLineGroupRequireMention({ cfg: lineCfg, groupId: "room:r123" })).is(false);
    (expect* resolveLineGroupRequireMention({ cfg: lineCfg, groupId: "g123" })).is(false);
    (expect* resolveLineGroupRequireMention({ cfg: lineCfg, groupId: "group:g123" })).is(false);
    (expect* resolveLineGroupRequireMention({ cfg: lineCfg, groupId: "other" })).is(true);
    (expect* resolveLineGroupToolPolicy({ cfg: lineCfg, groupId: "r123" })).is-equal({
      allow: ["message.send"],
    });
    (expect* resolveLineGroupToolPolicy({ cfg: lineCfg, groupId: "g123" })).is-equal({
      deny: ["exec"],
    });
  });

  (deftest "uses account-scoped prefixed LINE group config for requireMention", () => {
    const lineCfg = {
      channels: {
        line: {
          groups: {
            "*": {
              requireMention: true,
            },
          },
          accounts: {
            work: {
              groups: {
                "group:g123": {
                  requireMention: false,
                },
              },
            },
          },
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any;

    (expect* 
      resolveLineGroupRequireMention({ cfg: lineCfg, groupId: "g123", accountId: "work" }),
    ).is(false);
  });
});
