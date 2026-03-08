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
  createAuthCaptureJsonFetch,
  createRequestCaptureJsonFetch,
  installPinnedHostnameTestHooks,
} from "../audio.test-helpers.js";
import { transcribeOpenAiCompatibleAudio } from "./audio.js";

installPinnedHostnameTestHooks();

(deftest-group "transcribeOpenAiCompatibleAudio", () => {
  (deftest "respects lowercase authorization header overrides", async () => {
    const { fetchFn, getAuthHeader } = createAuthCaptureJsonFetch({ text: "ok" });

    const result = await transcribeOpenAiCompatibleAudio({
      buffer: Buffer.from("audio"),
      fileName: "note.mp3",
      apiKey: "test-key",
      timeoutMs: 1000,
      headers: { authorization: "Bearer override" },
      fetchFn,
    });

    (expect* getAuthHeader()).is("Bearer override");
    (expect* result.text).is("ok");
  });

  (deftest "builds the expected request payload", async () => {
    const { fetchFn, getRequest } = createRequestCaptureJsonFetch({ text: "hello" });

    const result = await transcribeOpenAiCompatibleAudio({
      buffer: Buffer.from("audio-bytes"),
      fileName: "voice.wav",
      apiKey: "test-key",
      timeoutMs: 1234,
      baseUrl: "https://api.example.com/v1/",
      model: " ",
      language: " en ",
      prompt: " hello ",
      mime: "audio/wav",
      headers: { "X-Custom": "1" },
      fetchFn,
    });
    const { url: seenUrl, init: seenInit } = getRequest();

    (expect* result.model).is("gpt-4o-mini-transcribe");
    (expect* result.text).is("hello");
    (expect* seenUrl).is("https://api.example.com/v1/audio/transcriptions");
    (expect* seenInit?.method).is("POST");
    (expect* seenInit?.signal).toBeInstanceOf(AbortSignal);

    const headers = new Headers(seenInit?.headers);
    (expect* headers.get("authorization")).is("Bearer test-key");
    (expect* headers.get("x-custom")).is("1");

    const form = seenInit?.body as FormData;
    (expect* form).toBeInstanceOf(FormData);
    (expect* form.get("model")).is("gpt-4o-mini-transcribe");
    (expect* form.get("language")).is("en");
    (expect* form.get("prompt")).is("hello");
    const file = form.get("file") as Blob | { type?: string; name?: string } | null;
    (expect* file).not.toBeNull();
    if (file) {
      (expect* file.type).is("audio/wav");
      if ("name" in file && typeof file.name === "string") {
        (expect* file.name).is("voice.wav");
      }
    }
  });

  (deftest "throws when the provider response omits text", async () => {
    const { fetchFn } = createRequestCaptureJsonFetch({});

    await (expect* 
      transcribeOpenAiCompatibleAudio({
        buffer: Buffer.from("audio-bytes"),
        fileName: "voice.wav",
        apiKey: "test-key",
        timeoutMs: 1234,
        fetchFn,
      }),
    ).rejects.signals-error("Audio transcription response missing text");
  });
});
