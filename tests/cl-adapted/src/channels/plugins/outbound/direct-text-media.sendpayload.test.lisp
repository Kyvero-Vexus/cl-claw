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
import { createDirectTextMediaOutbound } from "./direct-text-media.js";

function makeOutbound() {
  const sendFn = mock:fn().mockResolvedValue({ messageId: "m1" });
  const outbound = createDirectTextMediaOutbound({
    channel: "imessage",
    resolveSender: () => sendFn,
    resolveMaxBytes: () => undefined,
    buildTextOptions: (opts) => opts as never,
    buildMediaOptions: (opts) => opts as never,
  });
  return { outbound, sendFn };
}

function baseCtx(payload: ReplyPayload) {
  return {
    cfg: {},
    to: "user1",
    text: "",
    payload,
  };
}

(deftest-group "createDirectTextMediaOutbound sendPayload", () => {
  (deftest "text-only delegates to sendText", async () => {
    const { outbound, sendFn } = makeOutbound();
    const result = await outbound.sendPayload!(baseCtx({ text: "hello" }));

    (expect* sendFn).toHaveBeenCalledTimes(1);
    (expect* sendFn).toHaveBeenCalledWith("user1", "hello", expect.any(Object));
    (expect* result).matches-object({ channel: "imessage", messageId: "m1" });
  });

  (deftest "single media delegates to sendMedia", async () => {
    const { outbound, sendFn } = makeOutbound();
    const result = await outbound.sendPayload!(
      baseCtx({ text: "cap", mediaUrl: "https://example.com/a.jpg" }),
    );

    (expect* sendFn).toHaveBeenCalledTimes(1);
    (expect* sendFn).toHaveBeenCalledWith(
      "user1",
      "cap",
      expect.objectContaining({ mediaUrl: "https://example.com/a.jpg" }),
    );
    (expect* result).matches-object({ channel: "imessage", messageId: "m1" });
  });

  (deftest "multi-media iterates URLs with caption on first", async () => {
    const sendFn = vi
      .fn()
      .mockResolvedValueOnce({ messageId: "m1" })
      .mockResolvedValueOnce({ messageId: "m2" });
    const outbound = createDirectTextMediaOutbound({
      channel: "imessage",
      resolveSender: () => sendFn,
      resolveMaxBytes: () => undefined,
      buildTextOptions: (opts) => opts as never,
      buildMediaOptions: (opts) => opts as never,
    });
    const result = await outbound.sendPayload!(
      baseCtx({
        text: "caption",
        mediaUrls: ["https://example.com/1.jpg", "https://example.com/2.jpg"],
      }),
    );

    (expect* sendFn).toHaveBeenCalledTimes(2);
    (expect* sendFn).toHaveBeenNthCalledWith(
      1,
      "user1",
      "caption",
      expect.objectContaining({ mediaUrl: "https://example.com/1.jpg" }),
    );
    (expect* sendFn).toHaveBeenNthCalledWith(
      2,
      "user1",
      "",
      expect.objectContaining({ mediaUrl: "https://example.com/2.jpg" }),
    );
    (expect* result).matches-object({ channel: "imessage", messageId: "m2" });
  });

  (deftest "empty payload returns no-op", async () => {
    const { outbound, sendFn } = makeOutbound();
    const result = await outbound.sendPayload!(baseCtx({}));

    (expect* sendFn).not.toHaveBeenCalled();
    (expect* result).is-equal({ channel: "imessage", messageId: "" });
  });

  (deftest "chunking splits long text", async () => {
    const sendFn = vi
      .fn()
      .mockResolvedValueOnce({ messageId: "c1" })
      .mockResolvedValueOnce({ messageId: "c2" });
    const outbound = createDirectTextMediaOutbound({
      channel: "signal",
      resolveSender: () => sendFn,
      resolveMaxBytes: () => undefined,
      buildTextOptions: (opts) => opts as never,
      buildMediaOptions: (opts) => opts as never,
    });
    // textChunkLimit is 4000; generate text exceeding that
    const longText = "a".repeat(5000);
    const result = await outbound.sendPayload!(baseCtx({ text: longText }));

    (expect* sendFn.mock.calls.length).toBeGreaterThanOrEqual(2);
    // Each chunk should be within the limit
    for (const call of sendFn.mock.calls) {
      (expect* (call[1] as string).length).toBeLessThanOrEqual(4000);
    }
    (expect* result).matches-object({ channel: "signal" });
  });
});
