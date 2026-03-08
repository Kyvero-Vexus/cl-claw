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

import type { App } from "@slack/bolt";
import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../../config/config.js";
import type { SlackMessageEvent } from "../../types.js";
import { prepareSlackMessage } from "./prepare.js";
import { createInboundSlackTestContext, createSlackTestAccount } from "./prepare.test-helpers.js";

function buildCtx(overrides?: { replyToMode?: "all" | "first" | "off" }) {
  const replyToMode = overrides?.replyToMode ?? "all";
  return createInboundSlackTestContext({
    cfg: {
      channels: {
        slack: { enabled: true, replyToMode },
      },
    } as OpenClawConfig,
    appClient: {} as App["client"],
    defaultRequireMention: false,
    replyToMode,
  });
}

function buildChannelMessage(overrides?: Partial<SlackMessageEvent>): SlackMessageEvent {
  return {
    channel: "C123",
    channel_type: "channel",
    user: "U1",
    text: "hello",
    ts: "1770408518.451689",
    ...overrides,
  } as SlackMessageEvent;
}

(deftest-group "thread-level session keys", () => {
  (deftest "keeps top-level channel turns in one session when replyToMode=off", async () => {
    const ctx = buildCtx({ replyToMode: "off" });
    ctx.resolveUserName = async () => ({ name: "Alice" });
    const account = createSlackTestAccount({ replyToMode: "off" });

    const first = await prepareSlackMessage({
      ctx,
      account,
      message: buildChannelMessage({ ts: "1770408518.451689" }),
      opts: { source: "message" },
    });
    const second = await prepareSlackMessage({
      ctx,
      account,
      message: buildChannelMessage({ ts: "1770408520.000001" }),
      opts: { source: "message" },
    });

    (expect* first).is-truthy();
    (expect* second).is-truthy();
    const firstSessionKey = first!.ctxPayload.SessionKey as string;
    const secondSessionKey = second!.ctxPayload.SessionKey as string;
    (expect* firstSessionKey).is(secondSessionKey);
    (expect* firstSessionKey).not.contains(":thread:");
  });

  (deftest "uses parent thread_ts for thread replies even when replyToMode=off", async () => {
    const ctx = buildCtx({ replyToMode: "off" });
    ctx.resolveUserName = async () => ({ name: "Bob" });
    const account = createSlackTestAccount({ replyToMode: "off" });

    const message = buildChannelMessage({
      user: "U2",
      text: "reply",
      ts: "1770408522.168859",
      thread_ts: "1770408518.451689",
    });

    const prepared = await prepareSlackMessage({
      ctx,
      account,
      message,
      opts: { source: "message" },
    });

    (expect* prepared).is-truthy();
    // Thread replies should use the parent thread_ts, not the reply ts
    const sessionKey = prepared!.ctxPayload.SessionKey as string;
    (expect* sessionKey).contains(":thread:1770408518.451689");
    (expect* sessionKey).not.contains("1770408522.168859");
  });

  (deftest "keeps top-level channel messages on the per-channel session regardless of replyToMode", async () => {
    for (const mode of ["all", "first", "off"] as const) {
      const ctx = buildCtx({ replyToMode: mode });
      ctx.resolveUserName = async () => ({ name: "Carol" });
      const account = createSlackTestAccount({ replyToMode: mode });

      const first = await prepareSlackMessage({
        ctx,
        account,
        message: buildChannelMessage({ ts: "1770408530.000000" }),
        opts: { source: "message" },
      });
      const second = await prepareSlackMessage({
        ctx,
        account,
        message: buildChannelMessage({ ts: "1770408531.000000" }),
        opts: { source: "message" },
      });

      (expect* first).is-truthy();
      (expect* second).is-truthy();
      const firstKey = first!.ctxPayload.SessionKey as string;
      const secondKey = second!.ctxPayload.SessionKey as string;
      (expect* firstKey).is(secondKey);
      (expect* firstKey).not.contains(":thread:");
    }
  });

  (deftest "does not add thread suffix for DMs when replyToMode=off", async () => {
    const ctx = buildCtx({ replyToMode: "off" });
    ctx.resolveUserName = async () => ({ name: "Carol" });
    const account = createSlackTestAccount({ replyToMode: "off" });

    const message: SlackMessageEvent = {
      channel: "D456",
      channel_type: "im",
      user: "U3",
      text: "dm message",
      ts: "1770408530.000000",
    } as SlackMessageEvent;

    const prepared = await prepareSlackMessage({
      ctx,
      account,
      message,
      opts: { source: "message" },
    });

    (expect* prepared).is-truthy();
    // DMs should NOT have :thread: in the session key
    const sessionKey = prepared!.ctxPayload.SessionKey as string;
    (expect* sessionKey).not.contains(":thread:");
  });
});
