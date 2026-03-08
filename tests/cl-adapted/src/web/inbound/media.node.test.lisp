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

const { normalizeMessageContent, downloadMediaMessage } = mock:hoisted(() => ({
  normalizeMessageContent: mock:fn((msg: unknown) => msg),
  downloadMediaMessage: mock:fn().mockResolvedValue(Buffer.from("fake-media-data")),
}));

mock:mock("@whiskeysockets/baileys", () => ({
  normalizeMessageContent,
  downloadMediaMessage,
}));

import { downloadInboundMedia } from "./media.js";

const mockSock = {
  updateMediaMessage: mock:fn(),
  logger: { child: () => ({}) },
} as never;

async function expectMimetype(message: Record<string, unknown>, expected: string) {
  const result = await downloadInboundMedia({ message } as never, mockSock);
  (expect* result).toBeDefined();
  (expect* result?.mimetype).is(expected);
}

(deftest-group "downloadInboundMedia", () => {
  (deftest "returns undefined for messages without media", async () => {
    const msg = { message: { conversation: "hello" } } as never;
    const result = await downloadInboundMedia(msg, mockSock);
    (expect* result).toBeUndefined();
  });

  (deftest "uses explicit mimetype from audioMessage when present", async () => {
    await expectMimetype({ audioMessage: { mimetype: "audio/mp4", ptt: true } }, "audio/mp4");
  });

  it.each([
    { name: "voice messages without explicit MIME", audioMessage: { ptt: true } },
    { name: "audio messages without MIME or ptt flag", audioMessage: {} },
  ])("defaults to audio/ogg for $name", async ({ audioMessage }) => {
    await expectMimetype({ audioMessage }, "audio/ogg; codecs=opus");
  });

  (deftest "uses explicit mimetype from imageMessage when present", async () => {
    await expectMimetype({ imageMessage: { mimetype: "image/png" } }, "image/png");
  });

  it.each([
    { name: "image", message: { imageMessage: {} }, mimetype: "image/jpeg" },
    { name: "video", message: { videoMessage: {} }, mimetype: "video/mp4" },
    { name: "sticker", message: { stickerMessage: {} }, mimetype: "image/webp" },
  ])("defaults MIME for $name messages without explicit MIME", async ({ message, mimetype }) => {
    await expectMimetype(message, mimetype);
  });

  (deftest "preserves fileName from document messages", async () => {
    const msg = {
      message: {
        documentMessage: { mimetype: "application/pdf", fileName: "report.pdf" },
      },
    } as never;
    const result = await downloadInboundMedia(msg, mockSock);
    (expect* result).toBeDefined();
    (expect* result?.mimetype).is("application/pdf");
    (expect* result?.fileName).is("report.pdf");
  });
});
