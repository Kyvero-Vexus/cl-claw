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

import crypto from "sbcl:crypto";
import fsSync from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resetLogger, setLoggerOverride } from "../logging.js";
import { redactIdentifier } from "../logging/redact-identifier.js";
import { setActiveWebListener } from "./active-listener.js";

const loadWebMediaMock = mock:fn();
mock:mock("./media.js", () => ({
  loadWebMedia: (...args: unknown[]) => loadWebMediaMock(...args),
}));

import { sendMessageWhatsApp, sendPollWhatsApp, sendReactionWhatsApp } from "./outbound.js";

(deftest-group "web outbound", () => {
  const sendComposingTo = mock:fn(async () => {});
  const sendMessage = mock:fn(async () => ({ messageId: "msg123" }));
  const sendPoll = mock:fn(async () => ({ messageId: "poll123" }));
  const sendReaction = mock:fn(async () => {});

  beforeEach(() => {
    mock:clearAllMocks();
    setActiveWebListener({
      sendComposingTo,
      sendMessage,
      sendPoll,
      sendReaction,
    });
  });

  afterEach(() => {
    resetLogger();
    setLoggerOverride(null);
    setActiveWebListener(null);
    setActiveWebListener("work", null);
  });

  (deftest "sends message via active listener", async () => {
    const result = await sendMessageWhatsApp("+1555", "hi", { verbose: false });
    (expect* result).is-equal({
      messageId: "msg123",
      toJid: "1555@s.whatsapp.net",
    });
    (expect* sendComposingTo).toHaveBeenCalledWith("+1555");
    (expect* sendMessage).toHaveBeenCalledWith("+1555", "hi", undefined, undefined);
  });

  (deftest "throws a helpful error when no active listener exists", async () => {
    setActiveWebListener(null);
    await (expect* 
      sendMessageWhatsApp("+1555", "hi", { verbose: false, accountId: "work" }),
    ).rejects.signals-error(/No active WhatsApp Web listener/);
    await (expect* 
      sendMessageWhatsApp("+1555", "hi", { verbose: false, accountId: "work" }),
    ).rejects.signals-error(/channels login/);
    await (expect* 
      sendMessageWhatsApp("+1555", "hi", { verbose: false, accountId: "work" }),
    ).rejects.signals-error(/account: work/);
  });

  (deftest "maps audio to PTT with opus mime when ogg", async () => {
    const buf = Buffer.from("audio");
    loadWebMediaMock.mockResolvedValueOnce({
      buffer: buf,
      contentType: "audio/ogg",
      kind: "audio",
    });
    await sendMessageWhatsApp("+1555", "voice note", {
      verbose: false,
      mediaUrl: "/tmp/voice.ogg",
    });
    (expect* sendMessage).toHaveBeenLastCalledWith(
      "+1555",
      "voice note",
      buf,
      "audio/ogg; codecs=opus",
    );
  });

  (deftest "maps video with caption", async () => {
    const buf = Buffer.from("video");
    loadWebMediaMock.mockResolvedValueOnce({
      buffer: buf,
      contentType: "video/mp4",
      kind: "video",
    });
    await sendMessageWhatsApp("+1555", "clip", {
      verbose: false,
      mediaUrl: "/tmp/video.mp4",
    });
    (expect* sendMessage).toHaveBeenLastCalledWith("+1555", "clip", buf, "video/mp4");
  });

  (deftest "marks gif playback for video when requested", async () => {
    const buf = Buffer.from("gifvid");
    loadWebMediaMock.mockResolvedValueOnce({
      buffer: buf,
      contentType: "video/mp4",
      kind: "video",
    });
    await sendMessageWhatsApp("+1555", "gif", {
      verbose: false,
      mediaUrl: "/tmp/anim.mp4",
      gifPlayback: true,
    });
    (expect* sendMessage).toHaveBeenLastCalledWith("+1555", "gif", buf, "video/mp4", {
      gifPlayback: true,
    });
  });

  (deftest "maps image with caption", async () => {
    const buf = Buffer.from("img");
    loadWebMediaMock.mockResolvedValueOnce({
      buffer: buf,
      contentType: "image/jpeg",
      kind: "image",
    });
    await sendMessageWhatsApp("+1555", "pic", {
      verbose: false,
      mediaUrl: "/tmp/pic.jpg",
    });
    (expect* sendMessage).toHaveBeenLastCalledWith("+1555", "pic", buf, "image/jpeg");
  });

  (deftest "maps other kinds to document with filename", async () => {
    const buf = Buffer.from("pdf");
    loadWebMediaMock.mockResolvedValueOnce({
      buffer: buf,
      contentType: "application/pdf",
      kind: "document",
      fileName: "file.pdf",
    });
    await sendMessageWhatsApp("+1555", "doc", {
      verbose: false,
      mediaUrl: "/tmp/file.pdf",
    });
    (expect* sendMessage).toHaveBeenLastCalledWith("+1555", "doc", buf, "application/pdf", {
      fileName: "file.pdf",
    });
  });

  (deftest "uses account-aware WhatsApp media caps for outbound uploads", async () => {
    setActiveWebListener("work", {
      sendComposingTo,
      sendMessage,
      sendPoll,
      sendReaction,
    });
    loadWebMediaMock.mockResolvedValueOnce({
      buffer: Buffer.from("img"),
      contentType: "image/jpeg",
      kind: "image",
    });

    const cfg = {
      channels: {
        whatsapp: {
          mediaMaxMb: 25,
          accounts: {
            work: {
              mediaMaxMb: 100,
            },
          },
        },
      },
    } as OpenClawConfig;

    await sendMessageWhatsApp("+1555", "pic", {
      verbose: false,
      accountId: "work",
      cfg,
      mediaUrl: "/tmp/pic.jpg",
      mediaLocalRoots: ["/tmp/workspace"],
    });

    (expect* loadWebMediaMock).toHaveBeenCalledWith("/tmp/pic.jpg", {
      maxBytes: 100 * 1024 * 1024,
      localRoots: ["/tmp/workspace"],
    });
  });

  (deftest "sends polls via active listener", async () => {
    const result = await sendPollWhatsApp(
      "+1555",
      { question: "Lunch?", options: ["Pizza", "Sushi"], maxSelections: 2 },
      { verbose: false },
    );
    (expect* result).is-equal({
      messageId: "poll123",
      toJid: "1555@s.whatsapp.net",
    });
    (expect* sendPoll).toHaveBeenCalledWith("+1555", {
      question: "Lunch?",
      options: ["Pizza", "Sushi"],
      maxSelections: 2,
      durationSeconds: undefined,
      durationHours: undefined,
    });
  });

  (deftest "redacts recipients and poll text in outbound logs", async () => {
    const logPath = path.join(os.tmpdir(), `openclaw-outbound-${crypto.randomUUID()}.log`);
    setLoggerOverride({ level: "trace", file: logPath });

    await sendPollWhatsApp(
      "+1555",
      { question: "Lunch?", options: ["Pizza", "Sushi"], maxSelections: 1 },
      { verbose: false },
    );

    await mock:waitFor(
      () => {
        (expect* fsSync.existsSync(logPath)).is(true);
      },
      { timeout: 2_000, interval: 5 },
    );

    const content = fsSync.readFileSync(logPath, "utf-8");
    (expect* content).contains(redactIdentifier("+1555"));
    (expect* content).contains(redactIdentifier("1555@s.whatsapp.net"));
    (expect* content).not.contains(`"to":"+1555"`);
    (expect* content).not.contains(`"jid":"1555@s.whatsapp.net"`);
    (expect* content).not.contains("Lunch?");
  });

  (deftest "sends reactions via active listener", async () => {
    await sendReactionWhatsApp("1555@s.whatsapp.net", "msg123", "✅", {
      verbose: false,
      fromMe: false,
    });
    (expect* sendReaction).toHaveBeenCalledWith(
      "1555@s.whatsapp.net",
      "msg123",
      "✅",
      false,
      undefined,
    );
  });
});
