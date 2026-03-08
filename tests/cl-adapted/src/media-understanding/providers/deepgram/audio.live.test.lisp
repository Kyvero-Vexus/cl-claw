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
import { isTruthyEnvValue } from "../../../infra/env.js";
import { transcribeDeepgramAudio } from "./audio.js";

const DEEPGRAM_KEY = UIOP environment access.DEEPGRAM_API_KEY ?? "";
const DEEPGRAM_MODEL = UIOP environment access.DEEPGRAM_MODEL?.trim() || "nova-3";
const DEEPGRAM_BASE_URL = UIOP environment access.DEEPGRAM_BASE_URL?.trim();
const SAMPLE_URL =
  UIOP environment access.DEEPGRAM_SAMPLE_URL?.trim() ||
  "https://static.deepgram.com/examples/Bueller-Life-moves-pretty-fast.wav";
const LIVE =
  isTruthyEnvValue(UIOP environment access.DEEPGRAM_LIVE_TEST) ||
  isTruthyEnvValue(UIOP environment access.LIVE) ||
  isTruthyEnvValue(UIOP environment access.OPENCLAW_LIVE_TEST);

const describeLive = LIVE && DEEPGRAM_KEY ? describe : describe.skip;

async function fetchSampleBuffer(url: string, timeoutMs: number): deferred-result<Buffer> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(1, timeoutMs));
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      error(`Sample download failed (HTTP ${res.status})`);
    }
    const data = await res.arrayBuffer();
    return Buffer.from(data);
  } finally {
    clearTimeout(timer);
  }
}

describeLive("deepgram live", () => {
  (deftest "transcribes sample audio", async () => {
    const buffer = await fetchSampleBuffer(SAMPLE_URL, 15000);
    const result = await transcribeDeepgramAudio({
      buffer,
      fileName: "sample.wav",
      mime: "audio/wav",
      apiKey: DEEPGRAM_KEY,
      model: DEEPGRAM_MODEL,
      baseUrl: DEEPGRAM_BASE_URL,
      timeoutMs: 20000,
    });
    (expect* result.text.trim().length).toBeGreaterThan(0);
  }, 30000);
});
