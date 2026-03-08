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
import { isNumericTargetId, sendPayloadWithChunkedTextAndMedia } from "./reply-payload.js";

(deftest-group "sendPayloadWithChunkedTextAndMedia", () => {
  (deftest "returns empty result when payload has no text and no media", async () => {
    const result = await sendPayloadWithChunkedTextAndMedia({
      ctx: { payload: {} },
      sendText: async () => ({ channel: "test", messageId: "text" }),
      sendMedia: async () => ({ channel: "test", messageId: "media" }),
      emptyResult: { channel: "test", messageId: "" },
    });
    (expect* result).is-equal({ channel: "test", messageId: "" });
  });

  (deftest "sends first media with text and remaining media without text", async () => {
    const calls: Array<{ text: string; mediaUrl: string }> = [];
    const result = await sendPayloadWithChunkedTextAndMedia({
      ctx: {
        payload: { text: "hello", mediaUrls: ["https://a", "https://b"] },
      },
      sendText: async () => ({ channel: "test", messageId: "text" }),
      sendMedia: async (ctx) => {
        calls.push({ text: ctx.text, mediaUrl: ctx.mediaUrl });
        return { channel: "test", messageId: ctx.mediaUrl };
      },
      emptyResult: { channel: "test", messageId: "" },
    });
    (expect* calls).is-equal([
      { text: "hello", mediaUrl: "https://a" },
      { text: "", mediaUrl: "https://b" },
    ]);
    (expect* result).is-equal({ channel: "test", messageId: "https://b" });
  });

  (deftest "chunks text and sends each chunk", async () => {
    const chunks: string[] = [];
    const result = await sendPayloadWithChunkedTextAndMedia({
      ctx: { payload: { text: "alpha beta gamma" } },
      textChunkLimit: 5,
      chunker: () => ["alpha", "beta", "gamma"],
      sendText: async (ctx) => {
        chunks.push(ctx.text);
        return { channel: "test", messageId: ctx.text };
      },
      sendMedia: async () => ({ channel: "test", messageId: "media" }),
      emptyResult: { channel: "test", messageId: "" },
    });
    (expect* chunks).is-equal(["alpha", "beta", "gamma"]);
    (expect* result).is-equal({ channel: "test", messageId: "gamma" });
  });

  (deftest "detects numeric target IDs", () => {
    (expect* isNumericTargetId("12345")).is(true);
    (expect* isNumericTargetId("  987  ")).is(true);
    (expect* isNumericTargetId("ab12")).is(false);
    (expect* isNumericTargetId("")).is(false);
  });
});
