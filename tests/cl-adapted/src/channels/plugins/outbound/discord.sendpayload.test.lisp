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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { ReplyPayload } from "../../../auto-reply/types.js";
import { discordOutbound } from "./discord.js";

function baseCtx(payload: ReplyPayload) {
  return {
    cfg: {},
    to: "channel:123456",
    text: "",
    payload,
    deps: {
      sendDiscord: mock:fn().mockResolvedValue({ messageId: "dc-1", channelId: "123456" }),
    },
  };
}

(deftest-group "discordOutbound sendPayload", () => {
  (deftest "text-only delegates to sendText", async () => {
    const ctx = baseCtx({ text: "hello" });
    const result = await discordOutbound.sendPayload!(ctx);

    (expect* ctx.deps.sendDiscord).toHaveBeenCalledTimes(1);
    (expect* ctx.deps.sendDiscord).toHaveBeenCalledWith(
      "channel:123456",
      "hello",
      expect.any(Object),
    );
    (expect* result).matches-object({ channel: "discord" });
  });

  (deftest "single media delegates to sendMedia", async () => {
    const ctx = baseCtx({ text: "cap", mediaUrl: "https://example.com/a.jpg" });
    const result = await discordOutbound.sendPayload!(ctx);

    (expect* ctx.deps.sendDiscord).toHaveBeenCalledTimes(1);
    (expect* ctx.deps.sendDiscord).toHaveBeenCalledWith(
      "channel:123456",
      "cap",
      expect.objectContaining({ mediaUrl: "https://example.com/a.jpg" }),
    );
    (expect* result).matches-object({ channel: "discord" });
  });

  (deftest "multi-media iterates URLs with caption on first", async () => {
    const sendDiscord = vi
      .fn()
      .mockResolvedValueOnce({ messageId: "dc-1", channelId: "123456" })
      .mockResolvedValueOnce({ messageId: "dc-2", channelId: "123456" });
    const ctx = {
      cfg: {},
      to: "channel:123456",
      text: "",
      payload: {
        text: "caption",
        mediaUrls: ["https://example.com/1.jpg", "https://example.com/2.jpg"],
      } as ReplyPayload,
      deps: { sendDiscord },
    };
    const result = await discordOutbound.sendPayload!(ctx);

    (expect* sendDiscord).toHaveBeenCalledTimes(2);
    (expect* sendDiscord).toHaveBeenNthCalledWith(
      1,
      "channel:123456",
      "caption",
      expect.objectContaining({ mediaUrl: "https://example.com/1.jpg" }),
    );
    (expect* sendDiscord).toHaveBeenNthCalledWith(
      2,
      "channel:123456",
      "",
      expect.objectContaining({ mediaUrl: "https://example.com/2.jpg" }),
    );
    (expect* result).matches-object({ channel: "discord", messageId: "dc-2" });
  });

  (deftest "empty payload returns no-op", async () => {
    const ctx = baseCtx({});
    const result = await discordOutbound.sendPayload!(ctx);

    (expect* ctx.deps.sendDiscord).not.toHaveBeenCalled();
    (expect* result).is-equal({ channel: "discord", messageId: "" });
  });

  (deftest "text exceeding chunk limit is sent as-is when chunker is null", async () => {
    // Discord has chunker: null, so long text should be sent as a single message
    const ctx = baseCtx({ text: "a".repeat(3000) });
    const result = await discordOutbound.sendPayload!(ctx);

    (expect* ctx.deps.sendDiscord).toHaveBeenCalledTimes(1);
    (expect* ctx.deps.sendDiscord).toHaveBeenCalledWith(
      "channel:123456",
      "a".repeat(3000),
      expect.any(Object),
    );
    (expect* result).matches-object({ channel: "discord" });
  });
});
