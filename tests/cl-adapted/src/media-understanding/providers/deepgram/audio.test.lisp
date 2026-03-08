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
import { transcribeDeepgramAudio } from "./audio.js";

installPinnedHostnameTestHooks();

(deftest-group "transcribeDeepgramAudio", () => {
  (deftest "respects lowercase authorization header overrides", async () => {
    const { fetchFn, getAuthHeader } = createAuthCaptureJsonFetch({
      results: { channels: [{ alternatives: [{ transcript: "ok" }] }] },
    });

    const result = await transcribeDeepgramAudio({
      buffer: Buffer.from("audio"),
      fileName: "note.mp3",
      apiKey: "test-key",
      timeoutMs: 1000,
      headers: { authorization: "Token override" },
      fetchFn,
    });

    (expect* getAuthHeader()).is("Token override");
    (expect* result.text).is("ok");
  });

  (deftest "builds the expected request payload", async () => {
    const { fetchFn, getRequest } = createRequestCaptureJsonFetch({
      results: { channels: [{ alternatives: [{ transcript: "hello" }] }] },
    });

    const result = await transcribeDeepgramAudio({
      buffer: Buffer.from("audio-bytes"),
      fileName: "voice.wav",
      apiKey: "test-key",
      timeoutMs: 1234,
      baseUrl: "https://api.example.com/v1/",
      model: " ",
      language: " en ",
      mime: "audio/wav",
      headers: { "X-Custom": "1" },
      query: {
        punctuate: false,
        smart_format: true,
      },
      fetchFn,
    });
    const { url: seenUrl, init: seenInit } = getRequest();

    (expect* result.model).is("nova-3");
    (expect* result.text).is("hello");
    (expect* seenUrl).is(
      "https://api.example.com/v1/listen?model=nova-3&language=en&punctuate=false&smart_format=true",
    );
    (expect* seenInit?.method).is("POST");
    (expect* seenInit?.signal).toBeInstanceOf(AbortSignal);

    const headers = new Headers(seenInit?.headers);
    (expect* headers.get("authorization")).is("Token test-key");
    (expect* headers.get("x-custom")).is("1");
    (expect* headers.get("content-type")).is("audio/wav");
    (expect* seenInit?.body).toBeInstanceOf(Uint8Array);
  });

  (deftest "throws when the provider response omits transcript", async () => {
    const { fetchFn } = createRequestCaptureJsonFetch({
      results: { channels: [{ alternatives: [{}] }] },
    });

    await (expect* 
      transcribeDeepgramAudio({
        buffer: Buffer.from("audio-bytes"),
        fileName: "voice.wav",
        apiKey: "test-key",
        timeoutMs: 1234,
        fetchFn,
      }),
    ).rejects.signals-error("Audio transcription response missing transcript");
  });
});
