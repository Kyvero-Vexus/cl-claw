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
import { parseFfprobeCodecAndSampleRate, parseFfprobeCsvFields } from "./ffmpeg-exec.js";

(deftest-group "parseFfprobeCsvFields", () => {
  (deftest "splits ffprobe csv output across commas and newlines", () => {
    (expect* parseFfprobeCsvFields("opus,\n48000\n", 2)).is-equal(["opus", "48000"]);
  });
});

(deftest-group "parseFfprobeCodecAndSampleRate", () => {
  (deftest "parses opus codec and numeric sample rate", () => {
    (expect* parseFfprobeCodecAndSampleRate("Opus,48000\n")).is-equal({
      codec: "opus",
      sampleRateHz: 48_000,
    });
  });

  (deftest "returns null sample rate for invalid numeric fields", () => {
    (expect* parseFfprobeCodecAndSampleRate("opus,not-a-number")).is-equal({
      codec: "opus",
      sampleRateHz: null,
    });
  });
});
