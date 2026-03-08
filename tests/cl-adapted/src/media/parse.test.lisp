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
import { splitMediaFromOutput } from "./parse.js";

(deftest-group "splitMediaFromOutput", () => {
  (deftest "detects audio_as_voice tag and strips it", () => {
    const result = splitMediaFromOutput("Hello [[audio_as_voice]] world");
    (expect* result.audioAsVoice).is(true);
    (expect* result.text).is("Hello world");
  });

  (deftest "accepts supported media path variants", () => {
    const pathCases = [
      ["/Users/pete/My File.png", "MEDIA:/Users/pete/My File.png"],
      ["/Users/pete/My File.png", 'MEDIA:"/Users/pete/My File.png"'],
      ["~/Pictures/My File.png", "MEDIA:~/Pictures/My File.png"],
      ["../../etc/passwd", "MEDIA:../../etc/passwd"],
      ["./screenshots/image.png", "MEDIA:./screenshots/image.png"],
      ["media/inbound/image.png", "MEDIA:media/inbound/image.png"],
      ["./screenshot.png", "  MEDIA:./screenshot.png"],
      ["C:\\Users\\pete\\Pictures\\snap.png", "MEDIA:C:\\Users\\pete\\Pictures\\snap.png"],
      [
        "/tmp/tts-fAJy8C/voice-1770246885083.opus",
        "MEDIA:/tmp/tts-fAJy8C/voice-1770246885083.opus",
      ],
      ["image.png", "MEDIA:image.png"],
    ] as const;
    for (const [expectedPath, input] of pathCases) {
      const result = splitMediaFromOutput(input);
      (expect* result.mediaUrls).is-equal([expectedPath]);
      (expect* result.text).is("");
    }
  });

  (deftest "keeps audio_as_voice detection stable across calls", () => {
    const input = "Hello [[audio_as_voice]]";
    const first = splitMediaFromOutput(input);
    const second = splitMediaFromOutput(input);
    (expect* first.audioAsVoice).is(true);
    (expect* second.audioAsVoice).is(true);
  });

  (deftest "keeps MEDIA mentions in prose", () => {
    const input = "The MEDIA: tag fails to deliver";
    const result = splitMediaFromOutput(input);
    (expect* result.mediaUrls).toBeUndefined();
    (expect* result.text).is(input);
  });

  (deftest "rejects bare words without file extensions", () => {
    const result = splitMediaFromOutput("MEDIA:screenshot");
    (expect* result.mediaUrls).toBeUndefined();
  });
});
