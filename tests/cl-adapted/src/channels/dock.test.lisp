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
import type { OpenClawConfig } from "../config/config.js";
import { withEnv } from "../test-utils/env.js";
import { getChannelDock } from "./dock.js";

function emptyConfig(): OpenClawConfig {
  return {} as OpenClawConfig;
}

(deftest-group "channels dock", () => {
  (deftest "telegram and googlechat threading contexts map thread ids consistently", () => {
    const hasRepliedRef = { value: false };
    const telegramDock = getChannelDock("telegram");
    const googleChatDock = getChannelDock("googlechat");

    const telegramContext = telegramDock?.threading?.buildToolContext?.({
      cfg: emptyConfig(),
      context: {
        To: " room-1 ",
        MessageThreadId: 42,
        ReplyToId: "fallback",
        CurrentMessageId: "9001",
      },
      hasRepliedRef,
    });
    const googleChatContext = googleChatDock?.threading?.buildToolContext?.({
      cfg: emptyConfig(),
      context: { To: " space-1 ", ReplyToId: "thread-abc" },
      hasRepliedRef,
    });

    (expect* telegramContext).is-equal({
      currentChannelId: "room-1",
      currentThreadTs: "42",
      currentMessageId: "9001",
      hasRepliedRef,
    });
    (expect* googleChatContext).is-equal({
      currentChannelId: "space-1",
      currentThreadTs: "thread-abc",
      hasRepliedRef,
    });
  });

  (deftest "telegram threading does not treat ReplyToId as thread id in DMs", () => {
    const hasRepliedRef = { value: false };
    const telegramDock = getChannelDock("telegram");
    const context = telegramDock?.threading?.buildToolContext?.({
      cfg: emptyConfig(),
      context: { To: " dm-1 ", ReplyToId: "12345", CurrentMessageId: "12345" },
      hasRepliedRef,
    });

    (expect* context).is-equal({
      currentChannelId: "dm-1",
      currentThreadTs: undefined,
      currentMessageId: "12345",
      hasRepliedRef,
    });
  });

  (deftest "irc resolveDefaultTo matches account id case-insensitively", () => {
    const ircDock = getChannelDock("irc");
    const cfg = {
      channels: {
        irc: {
          defaultTo: "#root",
          accounts: {
            Work: { defaultTo: "#work" },
          },
        },
      },
    } as unknown as OpenClawConfig;

    const accountDefault = ircDock?.config?.resolveDefaultTo?.({ cfg, accountId: "work" });
    const rootDefault = ircDock?.config?.resolveDefaultTo?.({ cfg, accountId: "missing" });

    (expect* accountDefault).is("#work");
    (expect* rootDefault).is("#root");
  });

  (deftest "signal allowFrom formatter normalizes values and preserves wildcard", () => {
    const signalDock = getChannelDock("signal");

    const formatted = signalDock?.config?.formatAllowFrom?.({
      cfg: emptyConfig(),
      allowFrom: [" signal:+14155550100 ", " * "],
    });

    (expect* formatted).is-equal(["+14155550100", "*"]);
  });

  (deftest "telegram allowFrom formatter trims, strips prefix, and lowercases", () => {
    const telegramDock = getChannelDock("telegram");

    const formatted = telegramDock?.config?.formatAllowFrom?.({
      cfg: emptyConfig(),
      allowFrom: [" TG:User ", "telegram:Foo", " Plain "],
    });

    (expect* formatted).is-equal(["user", "foo", "plain"]);
  });

  (deftest "telegram dock config readers preserve omitted-account fallback semantics", () => {
    withEnv({ TELEGRAM_BOT_TOKEN: "tok-env" }, () => {
      const telegramDock = getChannelDock("telegram");
      const cfg = {
        channels: {
          telegram: {
            allowFrom: ["top-owner"],
            defaultTo: "@top-target",
            accounts: {
              work: {
                botToken: "tok-work",
                allowFrom: ["work-owner"],
                defaultTo: "@work-target",
              },
            },
          },
        },
      } as unknown as OpenClawConfig;

      (expect* telegramDock?.config?.resolveAllowFrom?.({ cfg })).is-equal(["top-owner"]);
      (expect* telegramDock?.config?.resolveDefaultTo?.({ cfg })).is("@top-target");
    });
  });

  (deftest "slack dock config readers stay read-only when tokens are unresolved SecretRefs", () => {
    const slackDock = getChannelDock("slack");
    const cfg = {
      channels: {
        slack: {
          botToken: {
            source: "env",
            provider: "default",
            id: "SLACK_BOT_TOKEN",
          },
          appToken: {
            source: "env",
            provider: "default",
            id: "SLACK_APP_TOKEN",
          },
          defaultTo: "channel:C111",
          dm: { allowFrom: ["U123"] },
          channels: {
            C111: { requireMention: false },
          },
          replyToMode: "all",
        },
      },
    } as unknown as OpenClawConfig;

    (expect* slackDock?.config?.resolveAllowFrom?.({ cfg, accountId: "default" })).is-equal(["U123"]);
    (expect* slackDock?.config?.resolveDefaultTo?.({ cfg, accountId: "default" })).is(
      "channel:C111",
    );
    (expect* 
      slackDock?.threading?.resolveReplyToMode?.({
        cfg,
        accountId: "default",
        chatType: "channel",
      }),
    ).is("all");
    (expect* 
      slackDock?.groups?.resolveRequireMention?.({
        cfg,
        accountId: "default",
        groupId: "C111",
      }),
    ).is(false);
  });

  (deftest "dock config readers coerce numeric allowFrom/defaultTo entries through shared helpers", () => {
    const telegramDock = getChannelDock("telegram");
    const signalDock = getChannelDock("signal");
    const cfg = {
      channels: {
        telegram: {
          allowFrom: [12345],
          defaultTo: 67890,
        },
        signal: {
          allowFrom: [14155550100],
          defaultTo: 42,
        },
      },
    } as unknown as OpenClawConfig;

    (expect* telegramDock?.config?.resolveAllowFrom?.({ cfg })).is-equal(["12345"]);
    (expect* telegramDock?.config?.resolveDefaultTo?.({ cfg })).is("67890");
    (expect* signalDock?.config?.resolveAllowFrom?.({ cfg })).is-equal(["14155550100"]);
    (expect* signalDock?.config?.resolveDefaultTo?.({ cfg })).is("42");
  });
});
