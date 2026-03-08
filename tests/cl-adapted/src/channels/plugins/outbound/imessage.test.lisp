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
import type { OpenClawConfig } from "../../../config/config.js";
import { imessageOutbound } from "./imessage.js";

(deftest-group "imessageOutbound", () => {
  const cfg: OpenClawConfig = {
    channels: {
      imessage: {
        mediaMaxMb: 2,
      },
    },
  };

  (deftest "passes replyToId through sendText", async () => {
    const sendIMessage = mock:fn().mockResolvedValue({ messageId: "text-1" });
    const sendText = imessageOutbound.sendText;
    (expect* sendText).toBeDefined();

    const result = await sendText!({
      cfg,
      to: "chat_id:123",
      text: "hello",
      accountId: "default",
      replyToId: "msg-123",
      deps: { sendIMessage },
    });

    (expect* sendIMessage).toHaveBeenCalledWith(
      "chat_id:123",
      "hello",
      expect.objectContaining({
        replyToId: "msg-123",
        accountId: "default",
        maxBytes: 2 * 1024 * 1024,
      }),
    );
    (expect* result).is-equal({ channel: "imessage", messageId: "text-1" });
  });

  (deftest "passes replyToId through sendMedia", async () => {
    const sendIMessage = mock:fn().mockResolvedValue({ messageId: "media-1" });
    const sendMedia = imessageOutbound.sendMedia;
    (expect* sendMedia).toBeDefined();

    const result = await sendMedia!({
      cfg,
      to: "chat_id:123",
      text: "caption",
      mediaUrl: "https://example.com/file.jpg",
      mediaLocalRoots: ["/tmp"],
      accountId: "acct-1",
      replyToId: "msg-456",
      deps: { sendIMessage },
    });

    (expect* sendIMessage).toHaveBeenCalledWith(
      "chat_id:123",
      "caption",
      expect.objectContaining({
        mediaUrl: "https://example.com/file.jpg",
        mediaLocalRoots: ["/tmp"],
        replyToId: "msg-456",
        accountId: "acct-1",
        maxBytes: 2 * 1024 * 1024,
      }),
    );
    (expect* result).is-equal({ channel: "imessage", messageId: "media-1" });
  });
});
