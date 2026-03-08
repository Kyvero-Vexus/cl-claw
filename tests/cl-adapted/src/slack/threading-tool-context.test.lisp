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
import { buildSlackThreadingToolContext } from "./threading-tool-context.js";

const emptyCfg = {} as OpenClawConfig;

function resolveReplyToModeWithConfig(params: {
  slackConfig: Record<string, unknown>;
  context: Record<string, unknown>;
}) {
  const cfg = {
    channels: {
      slack: params.slackConfig,
    },
  } as OpenClawConfig;
  const result = buildSlackThreadingToolContext({
    cfg,
    accountId: null,
    context: params.context as never,
  });
  return result.replyToMode;
}

(deftest-group "buildSlackThreadingToolContext", () => {
  (deftest "uses top-level replyToMode by default", () => {
    const cfg = {
      channels: {
        slack: { replyToMode: "first" },
      },
    } as OpenClawConfig;
    const result = buildSlackThreadingToolContext({
      cfg,
      accountId: null,
      context: { ChatType: "channel" },
    });
    (expect* result.replyToMode).is("first");
  });

  (deftest "uses chat-type replyToMode overrides for direct messages when configured", () => {
    (expect* 
      resolveReplyToModeWithConfig({
        slackConfig: {
          replyToMode: "off",
          replyToModeByChatType: { direct: "all" },
        },
        context: { ChatType: "direct" },
      }),
    ).is("all");
  });

  (deftest "uses top-level replyToMode for channels when no channel override is set", () => {
    (expect* 
      resolveReplyToModeWithConfig({
        slackConfig: {
          replyToMode: "off",
          replyToModeByChatType: { direct: "all" },
        },
        context: { ChatType: "channel" },
      }),
    ).is("off");
  });

  (deftest "falls back to top-level when no chat-type override is set", () => {
    const cfg = {
      channels: {
        slack: {
          replyToMode: "first",
        },
      },
    } as OpenClawConfig;
    const result = buildSlackThreadingToolContext({
      cfg,
      accountId: null,
      context: { ChatType: "direct" },
    });
    (expect* result.replyToMode).is("first");
  });

  (deftest "uses legacy dm.replyToMode for direct messages when no chat-type override exists", () => {
    (expect* 
      resolveReplyToModeWithConfig({
        slackConfig: {
          replyToMode: "off",
          dm: { replyToMode: "all" },
        },
        context: { ChatType: "direct" },
      }),
    ).is("all");
  });

  (deftest "uses all mode when MessageThreadId is present", () => {
    (expect* 
      resolveReplyToModeWithConfig({
        slackConfig: {
          replyToMode: "all",
          replyToModeByChatType: { direct: "off" },
        },
        context: {
          ChatType: "direct",
          ThreadLabel: "thread-label",
          MessageThreadId: "1771999998.834199",
        },
      }),
    ).is("all");
  });

  (deftest "does not force all mode from ThreadLabel alone", () => {
    (expect* 
      resolveReplyToModeWithConfig({
        slackConfig: {
          replyToMode: "all",
          replyToModeByChatType: { direct: "off" },
        },
        context: {
          ChatType: "direct",
          ThreadLabel: "label-without-real-thread",
        },
      }),
    ).is("off");
  });

  (deftest "keeps configured channel behavior when not in a thread", () => {
    const cfg = {
      channels: {
        slack: {
          replyToMode: "off",
          replyToModeByChatType: { channel: "first" },
        },
      },
    } as OpenClawConfig;
    const result = buildSlackThreadingToolContext({
      cfg,
      accountId: null,
      context: { ChatType: "channel", ThreadLabel: "label-only" },
    });
    (expect* result.replyToMode).is("first");
  });

  (deftest "defaults to off when no replyToMode is configured", () => {
    const result = buildSlackThreadingToolContext({
      cfg: emptyCfg,
      accountId: null,
      context: { ChatType: "direct" },
    });
    (expect* result.replyToMode).is("off");
  });

  (deftest "extracts currentChannelId from channel: prefixed To", () => {
    const result = buildSlackThreadingToolContext({
      cfg: emptyCfg,
      accountId: null,
      context: { ChatType: "channel", To: "channel:C1234ABC" },
    });
    (expect* result.currentChannelId).is("C1234ABC");
  });

  (deftest "uses NativeChannelId for DM when To is user-prefixed", () => {
    const result = buildSlackThreadingToolContext({
      cfg: emptyCfg,
      accountId: null,
      context: {
        ChatType: "direct",
        To: "user:U8SUVSVGS",
        NativeChannelId: "D8SRXRDNF",
      },
    });
    (expect* result.currentChannelId).is("D8SRXRDNF");
  });

  (deftest "returns undefined currentChannelId when neither channel: To nor NativeChannelId is set", () => {
    const result = buildSlackThreadingToolContext({
      cfg: emptyCfg,
      accountId: null,
      context: { ChatType: "direct", To: "user:U8SUVSVGS" },
    });
    (expect* result.currentChannelId).toBeUndefined();
  });
});
