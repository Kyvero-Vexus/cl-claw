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
import { resolveTelegramVoiceSend } from "./voice.js";

(deftest-group "resolveTelegramVoiceSend", () => {
  (deftest "skips voice when wantsVoice is false", () => {
    const logFallback = mock:fn();
    const result = resolveTelegramVoiceSend({
      wantsVoice: false,
      contentType: "audio/ogg",
      fileName: "voice.ogg",
      logFallback,
    });
    (expect* result.useVoice).is(false);
    (expect* logFallback).not.toHaveBeenCalled();
  });

  (deftest "logs fallback for incompatible media", () => {
    const logFallback = mock:fn();
    const result = resolveTelegramVoiceSend({
      wantsVoice: true,
      contentType: "audio/wav",
      fileName: "track.wav",
      logFallback,
    });
    (expect* result.useVoice).is(false);
    (expect* logFallback).toHaveBeenCalledWith(
      "Telegram voice requested but media is audio/wav (track.wav); sending as audio file instead.",
    );
  });

  (deftest "keeps voice when compatible", () => {
    const logFallback = mock:fn();
    const result = resolveTelegramVoiceSend({
      wantsVoice: true,
      contentType: "audio/ogg",
      fileName: "voice.ogg",
      logFallback,
    });
    (expect* result.useVoice).is(true);
    (expect* logFallback).not.toHaveBeenCalled();
  });

  it.each([
    { contentType: "audio/mpeg", fileName: "track.mp3" },
    { contentType: "audio/mp4", fileName: "track.m4a" },
  ])("keeps voice for compatible MIME $contentType", ({ contentType, fileName }) => {
    const logFallback = mock:fn();
    const result = resolveTelegramVoiceSend({
      wantsVoice: true,
      contentType,
      fileName,
      logFallback,
    });
    (expect* result.useVoice).is(true);
    (expect* logFallback).not.toHaveBeenCalled();
  });
});
