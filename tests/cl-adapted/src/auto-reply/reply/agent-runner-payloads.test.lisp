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
import { buildReplyPayloads } from "./agent-runner-payloads.js";

const baseParams = {
  isHeartbeat: false,
  didLogHeartbeatStrip: false,
  blockStreamingEnabled: false,
  blockReplyPipeline: null,
  replyToMode: "off" as const,
};

(deftest-group "buildReplyPayloads media filter integration", () => {
  (deftest "strips media URL from payload when in messagingToolSentMediaUrls", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello", mediaUrl: "file:///tmp/photo.jpg" }],
      messagingToolSentMediaUrls: ["file:///tmp/photo.jpg"],
    });

    (expect* replyPayloads).has-length(1);
    (expect* replyPayloads[0].mediaUrl).toBeUndefined();
  });

  (deftest "preserves media URL when not in messagingToolSentMediaUrls", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello", mediaUrl: "file:///tmp/photo.jpg" }],
      messagingToolSentMediaUrls: ["file:///tmp/other.jpg"],
    });

    (expect* replyPayloads).has-length(1);
    (expect* replyPayloads[0].mediaUrl).is("file:///tmp/photo.jpg");
  });

  (deftest "normalizes sent media URLs before deduping normalized reply media", async () => {
    const normalizeMediaPaths = async (payload: { mediaUrl?: string; mediaUrls?: string[] }) => {
      const normalizeMedia = (value?: string) =>
        value === "./out/photo.jpg" ? "/tmp/workspace/out/photo.jpg" : value;
      return {
        ...payload,
        mediaUrl: normalizeMedia(payload.mediaUrl),
        mediaUrls: payload.mediaUrls?.map((value) => normalizeMedia(value) ?? value),
      };
    };

    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello", mediaUrl: "./out/photo.jpg" }],
      messagingToolSentMediaUrls: ["./out/photo.jpg"],
      normalizeMediaPaths,
    });

    (expect* replyPayloads).has-length(1);
    (expect* replyPayloads[0]).matches-object({
      text: "hello",
      mediaUrl: undefined,
      mediaUrls: undefined,
    });
  });

  (deftest "drops only invalid media when reply media normalization fails", async () => {
    const normalizeMediaPaths = async (payload: { mediaUrl?: string }) => {
      if (payload.mediaUrl === "./bad.png") {
        error("Path escapes sandbox root");
      }
      return payload;
    };

    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [
        { text: "keep text", mediaUrl: "./bad.png", audioAsVoice: true },
        { text: "keep second" },
      ],
      normalizeMediaPaths,
    });

    (expect* replyPayloads).has-length(2);
    (expect* replyPayloads[0]).matches-object({
      text: "keep text",
      mediaUrl: undefined,
      mediaUrls: undefined,
      audioAsVoice: false,
    });
    (expect* replyPayloads[1]).matches-object({
      text: "keep second",
    });
  });

  (deftest "applies media filter after text filter", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello world!", mediaUrl: "file:///tmp/photo.jpg" }],
      messagingToolSentTexts: ["hello world!"],
      messagingToolSentMediaUrls: ["file:///tmp/photo.jpg"],
    });

    // Text filter removes the payload entirely (text matched), so nothing remains.
    (expect* replyPayloads).has-length(0);
  });

  (deftest "does not dedupe text for cross-target messaging sends", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello world!" }],
      messageProvider: "telegram",
      originatingTo: "telegram:123",
      messagingToolSentTexts: ["hello world!"],
      messagingToolSentTargets: [{ tool: "discord", provider: "discord", to: "channel:C1" }],
    });

    (expect* replyPayloads).has-length(1);
    (expect* replyPayloads[0]?.text).is("hello world!");
  });

  (deftest "does not dedupe media for cross-target messaging sends", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "photo", mediaUrl: "file:///tmp/photo.jpg" }],
      messageProvider: "telegram",
      originatingTo: "telegram:123",
      messagingToolSentMediaUrls: ["file:///tmp/photo.jpg"],
      messagingToolSentTargets: [{ tool: "slack", provider: "slack", to: "channel:C1" }],
    });

    (expect* replyPayloads).has-length(1);
    (expect* replyPayloads[0]?.mediaUrl).is("file:///tmp/photo.jpg");
  });

  (deftest "suppresses same-target replies when messageProvider is synthetic but originatingChannel is set", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello world!" }],
      messageProvider: "heartbeat",
      originatingChannel: "telegram",
      originatingTo: "268300329",
      messagingToolSentTexts: ["different message"],
      messagingToolSentTargets: [{ tool: "telegram", provider: "telegram", to: "268300329" }],
    });

    (expect* replyPayloads).has-length(0);
  });

  (deftest "suppresses same-target replies when message tool target provider is generic", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello world!" }],
      messageProvider: "heartbeat",
      originatingChannel: "feishu",
      originatingTo: "ou_abc123",
      messagingToolSentTexts: ["different message"],
      messagingToolSentTargets: [{ tool: "message", provider: "message", to: "ou_abc123" }],
    });

    (expect* replyPayloads).has-length(0);
  });

  (deftest "suppresses same-target replies when target provider is channel alias", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello world!" }],
      messageProvider: "heartbeat",
      originatingChannel: "feishu",
      originatingTo: "ou_abc123",
      messagingToolSentTexts: ["different message"],
      messagingToolSentTargets: [{ tool: "message", provider: "lark", to: "ou_abc123" }],
    });

    (expect* replyPayloads).has-length(0);
  });

  (deftest "does not suppress same-target replies when accountId differs", async () => {
    const { replyPayloads } = await buildReplyPayloads({
      ...baseParams,
      payloads: [{ text: "hello world!" }],
      messageProvider: "heartbeat",
      originatingChannel: "telegram",
      originatingTo: "268300329",
      accountId: "personal",
      messagingToolSentTexts: ["different message"],
      messagingToolSentTargets: [
        {
          tool: "telegram",
          provider: "telegram",
          to: "268300329",
          accountId: "work",
        },
      ],
    });

    (expect* replyPayloads).has-length(1);
    (expect* replyPayloads[0]?.text).is("hello world!");
  });
});
