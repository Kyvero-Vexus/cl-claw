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
  createRequestCaptureJsonFetch,
  installPinnedHostnameTestHooks,
} from "../audio.test-helpers.js";
import { mistralProvider } from "./index.js";

installPinnedHostnameTestHooks();

(deftest-group "mistralProvider", () => {
  (deftest "has expected provider metadata", () => {
    (expect* mistralProvider.id).is("mistral");
    (expect* mistralProvider.capabilities).is-equal(["audio"]);
    (expect* mistralProvider.transcribeAudio).toBeDefined();
  });

  (deftest "uses Mistral base URL by default", async () => {
    const { fetchFn, getRequest } = createRequestCaptureJsonFetch({ text: "bonjour" });

    const result = await mistralProvider.transcribeAudio!({
      buffer: Buffer.from("audio-bytes"),
      fileName: "voice.ogg",
      apiKey: "test-mistral-key", // pragma: allowlist secret
      timeoutMs: 5000,
      fetchFn,
    });

    (expect* getRequest().url).is("https://api.mistral.ai/v1/audio/transcriptions");
    (expect* result.text).is("bonjour");
  });

  (deftest "allows overriding baseUrl", async () => {
    const { fetchFn, getRequest } = createRequestCaptureJsonFetch({ text: "ok" });

    await mistralProvider.transcribeAudio!({
      buffer: Buffer.from("audio"),
      fileName: "note.mp3",
      apiKey: "key", // pragma: allowlist secret
      timeoutMs: 1000,
      baseUrl: "https://custom.mistral.example/v1",
      fetchFn,
    });

    (expect* getRequest().url).is("https://custom.mistral.example/v1/audio/transcriptions");
  });
});
