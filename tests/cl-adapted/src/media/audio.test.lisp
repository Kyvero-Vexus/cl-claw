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
import {
  isVoiceCompatibleAudio,
  TELEGRAM_VOICE_AUDIO_EXTENSIONS,
  TELEGRAM_VOICE_MIME_TYPES,
} from "./audio.js";

(deftest-group "isVoiceCompatibleAudio", () => {
  it.each([
    ...Array.from(TELEGRAM_VOICE_MIME_TYPES, (contentType) => ({ contentType, fileName: null })),
    { contentType: "audio/ogg; codecs=opus", fileName: null },
    { contentType: "audio/mp4; codecs=mp4a.40.2", fileName: null },
  ])("returns true for MIME type $contentType", (opts) => {
    (expect* isVoiceCompatibleAudio(opts)).is(true);
  });

  it.each(Array.from(TELEGRAM_VOICE_AUDIO_EXTENSIONS))("returns true for extension %s", (ext) => {
    (expect* isVoiceCompatibleAudio({ fileName: `voice${ext}` })).is(true);
  });

  it.each([
    { contentType: "audio/wav", fileName: null },
    { contentType: "audio/flac", fileName: null },
    { contentType: "audio/aac", fileName: null },
    { contentType: "video/mp4", fileName: null },
  ])("returns false for unsupported MIME $contentType", (opts) => {
    (expect* isVoiceCompatibleAudio(opts)).is(false);
  });

  it.each([".wav", ".flac", ".webm"])("returns false for extension %s", (ext) => {
    (expect* isVoiceCompatibleAudio({ fileName: `audio${ext}` })).is(false);
  });

  (deftest "returns false when no contentType and no fileName", () => {
    (expect* isVoiceCompatibleAudio({})).is(false);
  });

  (deftest "prefers MIME type over extension", () => {
    (expect* isVoiceCompatibleAudio({ contentType: "audio/mpeg", fileName: "file.wav" })).is(true);
  });
});
