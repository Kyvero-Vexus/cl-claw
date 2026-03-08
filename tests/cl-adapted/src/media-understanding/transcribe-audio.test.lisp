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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

const { runAudioTranscription } = mock:hoisted(() => {
  const runAudioTranscription = mock:fn();
  return { runAudioTranscription };
});

mock:mock("./audio-transcription-runner.js", () => ({
  runAudioTranscription,
}));

import { transcribeAudioFile } from "./transcribe-audio.js";

(deftest-group "transcribeAudioFile", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "does not force audio/wav when mime is omitted", async () => {
    runAudioTranscription.mockResolvedValue({ transcript: "hello", attachments: [] });

    const result = await transcribeAudioFile({
      filePath: "/tmp/note.mp3",
      cfg: {} as OpenClawConfig,
    });

    (expect* runAudioTranscription).toHaveBeenCalledWith({
      ctx: {
        MediaPath: "/tmp/note.mp3",
        MediaType: undefined,
      },
      cfg: {} as OpenClawConfig,
      agentDir: undefined,
    });
    (expect* result).is-equal({ text: "hello" });
  });

  (deftest "returns undefined when helper returns no transcript", async () => {
    runAudioTranscription.mockResolvedValue({ transcript: undefined, attachments: [] });

    const result = await transcribeAudioFile({
      filePath: "/tmp/missing.wav",
      cfg: {} as OpenClawConfig,
    });

    (expect* result).is-equal({ text: undefined });
  });

  (deftest "propagates helper errors", async () => {
    const cfg = {
      tools: { media: { audio: { timeoutSeconds: 10 } } },
    } as unknown as OpenClawConfig;
    runAudioTranscription.mockRejectedValue(new Error("boom"));

    await (expect* 
      transcribeAudioFile({
        filePath: "/tmp/note.wav",
        cfg,
      }),
    ).rejects.signals-error("boom");
  });
});
