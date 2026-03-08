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
import type { SubagentRunRecord } from "../../agents/subagent-registry.js";
import type { OpenClawConfig } from "../../config/config.js";
import { formatDurationCompact } from "../../infra/format-time/format-duration.js";
import type { TemplateContext } from "../templating.js";
import { buildThreadingToolContext } from "./agent-runner-utils.js";
import { applyReplyThreading } from "./reply-payloads.js";
import {
  formatRunLabel,
  formatRunStatus,
  resolveSubagentLabel,
  sortSubagentRuns,
} from "./subagents-utils.js";

(deftest-group "buildThreadingToolContext", () => {
  const cfg = {} as OpenClawConfig;

  (deftest "uses conversation id for WhatsApp", () => {
    const sessionCtx = {
      Provider: "whatsapp",
      From: "123@g.us",
      To: "+15550001",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: cfg,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("123@g.us");
  });

  (deftest "falls back to To for WhatsApp when From is missing", () => {
    const sessionCtx = {
      Provider: "whatsapp",
      To: "+15550001",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: cfg,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("+15550001");
  });

  (deftest "uses the recipient id for other channels", () => {
    const sessionCtx = {
      Provider: "telegram",
      From: "user:42",
      To: "chat:99",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: cfg,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("chat:99");
  });

  (deftest "normalizes signal direct targets for tool context", () => {
    const sessionCtx = {
      Provider: "signal",
      ChatType: "direct",
      From: "signal:+15550001",
      To: "signal:+15550002",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: cfg,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("+15550001");
  });

  (deftest "preserves signal group ids for tool context", () => {
    const sessionCtx = {
      Provider: "signal",
      ChatType: "group",
      To: "signal:group:VWATOdKF2hc8zdOS76q9tb0+5BI522e03QLDAq/9yPg=",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: cfg,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("group:VWATOdKF2hc8zdOS76q9tb0+5BI522e03QLDAq/9yPg=");
  });

  (deftest "uses the sender handle for iMessage direct chats", () => {
    const sessionCtx = {
      Provider: "imessage",
      ChatType: "direct",
      From: "imessage:+15550001",
      To: "chat_id:12",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: cfg,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("imessage:+15550001");
  });

  (deftest "uses chat_id for iMessage groups", () => {
    const sessionCtx = {
      Provider: "imessage",
      ChatType: "group",
      From: "imessage:group:7",
      To: "chat_id:7",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: cfg,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("chat_id:7");
  });

  (deftest "prefers MessageThreadId for Slack tool threading", () => {
    const sessionCtx = {
      Provider: "slack",
      To: "channel:C1",
      MessageThreadId: "123.456",
    } as TemplateContext;

    const result = buildThreadingToolContext({
      sessionCtx,
      config: { channels: { slack: { replyToMode: "all" } } } as OpenClawConfig,
      hasRepliedRef: undefined,
    });

    (expect* result.currentChannelId).is("C1");
    (expect* result.currentThreadTs).is("123.456");
  });
});

(deftest-group "applyReplyThreading auto-threading", () => {
  (deftest "sets replyToId to currentMessageId even without [[reply_to_current]] tag", () => {
    const result = applyReplyThreading({
      payloads: [{ text: "Hello" }],
      replyToMode: "first",
      currentMessageId: "42",
    });

    (expect* result).has-length(1);
    (expect* result[0].replyToId).is("42");
  });

  (deftest "threads only first payload when mode is 'first'", () => {
    const result = applyReplyThreading({
      payloads: [{ text: "A" }, { text: "B" }],
      replyToMode: "first",
      currentMessageId: "42",
    });

    (expect* result).has-length(2);
    (expect* result[0].replyToId).is("42");
    (expect* result[1].replyToId).toBeUndefined();
  });

  (deftest "threads all payloads when mode is 'all'", () => {
    const result = applyReplyThreading({
      payloads: [{ text: "A" }, { text: "B" }],
      replyToMode: "all",
      currentMessageId: "42",
    });

    (expect* result).has-length(2);
    (expect* result[0].replyToId).is("42");
    (expect* result[1].replyToId).is("42");
  });

  (deftest "strips replyToId when mode is 'off'", () => {
    const result = applyReplyThreading({
      payloads: [{ text: "A" }],
      replyToMode: "off",
      currentMessageId: "42",
    });

    (expect* result).has-length(1);
    (expect* result[0].replyToId).toBeUndefined();
  });

  (deftest "does not bypass off mode for Slack when reply is implicit", () => {
    const result = applyReplyThreading({
      payloads: [{ text: "A" }],
      replyToMode: "off",
      replyToChannel: "slack",
      currentMessageId: "42",
    });

    (expect* result).has-length(1);
    (expect* result[0].replyToId).toBeUndefined();
  });

  (deftest "strips explicit tags for Slack when off mode disallows tags", () => {
    const result = applyReplyThreading({
      payloads: [{ text: "[[reply_to_current]]A" }],
      replyToMode: "off",
      replyToChannel: "slack",
      currentMessageId: "42",
    });

    (expect* result).has-length(1);
    (expect* result[0].replyToId).toBeUndefined();
  });

  (deftest "keeps explicit tags for Telegram when off mode is enabled", () => {
    const result = applyReplyThreading({
      payloads: [{ text: "[[reply_to_current]]A" }],
      replyToMode: "off",
      replyToChannel: "telegram",
      currentMessageId: "42",
    });

    (expect* result).has-length(1);
    (expect* result[0].replyToId).is("42");
    (expect* result[0].replyToTag).is(true);
  });
});

const baseRun: SubagentRunRecord = {
  runId: "run-1",
  childSessionKey: "agent:main:subagent:abc",
  requesterSessionKey: "agent:main:main",
  requesterDisplayKey: "main",
  task: "do thing",
  cleanup: "keep",
  createdAt: 1000,
  startedAt: 1000,
};

(deftest-group "subagents utils", () => {
  (deftest "resolves labels from label, task, or fallback", () => {
    (expect* resolveSubagentLabel({ ...baseRun, label: "Label" })).is("Label");
    (expect* resolveSubagentLabel({ ...baseRun, label: " ", task: "Task" })).is("Task");
    (expect* resolveSubagentLabel({ ...baseRun, label: " ", task: " " }, "fallback")).is(
      "fallback",
    );
  });

  (deftest "formats run labels with truncation", () => {
    const long = "x".repeat(100);
    const run = { ...baseRun, label: long };
    const formatted = formatRunLabel(run, { maxLength: 10 });
    (expect* formatted.startsWith("x".repeat(10))).is(true);
    (expect* formatted.endsWith("…")).is(true);
  });

  (deftest "sorts subagent runs by newest start/created time", () => {
    const runs: SubagentRunRecord[] = [
      { ...baseRun, runId: "run-1", createdAt: 1000, startedAt: 1000 },
      { ...baseRun, runId: "run-2", createdAt: 1200, startedAt: 1200 },
      { ...baseRun, runId: "run-3", createdAt: 900 },
    ];
    const sorted = sortSubagentRuns(runs);
    (expect* sorted.map((run) => run.runId)).is-equal(["run-2", "run-1", "run-3"]);
  });

  (deftest "formats run status from outcome and timestamps", () => {
    (expect* formatRunStatus({ ...baseRun })).is("running");
    (expect* formatRunStatus({ ...baseRun, endedAt: 2000, outcome: { status: "ok" } })).is("done");
    (expect* formatRunStatus({ ...baseRun, endedAt: 2000, outcome: { status: "timeout" } })).is(
      "timeout",
    );
  });

  (deftest "formats duration compact for seconds and minutes", () => {
    (expect* formatDurationCompact(45_000)).is("45s");
    (expect* formatDurationCompact(65_000)).is("1m5s");
  });
});
