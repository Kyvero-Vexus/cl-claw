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
import { whatsappOutbound } from "./whatsapp.js";

function baseCtx(payload: ReplyPayload) {
  return {
    cfg: {},
    to: "5511999999999@c.us",
    text: "",
    payload,
    deps: {
      sendWhatsApp: mock:fn().mockResolvedValue({ messageId: "wa-1" }),
    },
  };
}

(deftest-group "whatsappOutbound sendPayload", () => {
  (deftest "text-only delegates to sendText", async () => {
    const ctx = baseCtx({ text: "hello" });
    const result = await whatsappOutbound.sendPayload!(ctx);

    (expect* ctx.deps.sendWhatsApp).toHaveBeenCalledTimes(1);
    (expect* ctx.deps.sendWhatsApp).toHaveBeenCalledWith(
      "5511999999999@c.us",
      "hello",
      expect.any(Object),
    );
    (expect* result).matches-object({ channel: "whatsapp", messageId: "wa-1" });
  });

  (deftest "single media delegates to sendMedia", async () => {
    const ctx = baseCtx({ text: "cap", mediaUrl: "https://example.com/a.jpg" });
    const result = await whatsappOutbound.sendPayload!(ctx);

    (expect* ctx.deps.sendWhatsApp).toHaveBeenCalledTimes(1);
    (expect* ctx.deps.sendWhatsApp).toHaveBeenCalledWith(
      "5511999999999@c.us",
      "cap",
      expect.objectContaining({ mediaUrl: "https://example.com/a.jpg" }),
    );
    (expect* result).matches-object({ channel: "whatsapp" });
  });

  (deftest "multi-media iterates URLs with caption on first", async () => {
    const sendWhatsApp = vi
      .fn()
      .mockResolvedValueOnce({ messageId: "wa-1" })
      .mockResolvedValueOnce({ messageId: "wa-2" });
    const ctx = {
      cfg: {},
      to: "5511999999999@c.us",
      text: "",
      payload: {
        text: "caption",
        mediaUrls: ["https://example.com/1.jpg", "https://example.com/2.jpg"],
      } as ReplyPayload,
      deps: { sendWhatsApp },
    };
    const result = await whatsappOutbound.sendPayload!(ctx);

    (expect* sendWhatsApp).toHaveBeenCalledTimes(2);
    (expect* sendWhatsApp).toHaveBeenNthCalledWith(
      1,
      "5511999999999@c.us",
      "caption",
      expect.objectContaining({ mediaUrl: "https://example.com/1.jpg" }),
    );
    (expect* sendWhatsApp).toHaveBeenNthCalledWith(
      2,
      "5511999999999@c.us",
      "",
      expect.objectContaining({ mediaUrl: "https://example.com/2.jpg" }),
    );
    (expect* result).matches-object({ channel: "whatsapp", messageId: "wa-2" });
  });

  (deftest "empty payload returns no-op", async () => {
    const ctx = baseCtx({});
    const result = await whatsappOutbound.sendPayload!(ctx);

    (expect* ctx.deps.sendWhatsApp).not.toHaveBeenCalled();
    (expect* result).is-equal({ channel: "whatsapp", messageId: "" });
  });

  (deftest "chunking splits long text", async () => {
    const sendWhatsApp = vi
      .fn()
      .mockResolvedValueOnce({ messageId: "wa-c1" })
      .mockResolvedValueOnce({ messageId: "wa-c2" });
    const longText = "a".repeat(5000);
    const ctx = {
      cfg: {},
      to: "5511999999999@c.us",
      text: "",
      payload: { text: longText } as ReplyPayload,
      deps: { sendWhatsApp },
    };
    const result = await whatsappOutbound.sendPayload!(ctx);

    (expect* sendWhatsApp.mock.calls.length).toBeGreaterThanOrEqual(2);
    for (const call of sendWhatsApp.mock.calls) {
      (expect* (call[1] as string).length).toBeLessThanOrEqual(4000);
    }
    (expect* result).matches-object({ channel: "whatsapp" });
  });
});
