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
import { describeMoonshotVideo } from "./video.js";

installPinnedHostnameTestHooks();

(deftest-group "describeMoonshotVideo", () => {
  (deftest "builds an OpenAI-compatible video request", async () => {
    const { fetchFn, getRequest } = createRequestCaptureJsonFetch({
      choices: [{ message: { content: "video ok" } }],
    });

    const result = await describeMoonshotVideo({
      buffer: Buffer.from("video-bytes"),
      fileName: "clip.mp4",
      apiKey: "moonshot-test", // pragma: allowlist secret
      timeoutMs: 1500,
      baseUrl: "https://api.moonshot.ai/v1/",
      model: "kimi-k2.5",
      headers: { "X-Trace": "1" },
      fetchFn,
    });
    const { url, init } = getRequest();

    (expect* result.text).is("video ok");
    (expect* result.model).is("kimi-k2.5");
    (expect* url).is("https://api.moonshot.ai/v1/chat/completions");
    (expect* init?.method).is("POST");
    (expect* init?.signal).toBeInstanceOf(AbortSignal);

    const headers = new Headers(init?.headers);
    (expect* headers.get("authorization")).is("Bearer moonshot-test");
    (expect* headers.get("content-type")).is("application/json");
    (expect* headers.get("x-trace")).is("1");

    const body = JSON.parse(typeof init?.body === "string" ? init.body : "{}") as {
      model?: string;
      messages?: Array<{
        content?: Array<{ type?: string; text?: string; video_url?: { url?: string } }>;
      }>;
    };
    (expect* body.model).is("kimi-k2.5");
    (expect* body.messages?.[0]?.content?.[0]).matches-object({
      type: "text",
      text: "Describe the video.",
    });
    (expect* body.messages?.[0]?.content?.[1]?.type).is("video_url");
    (expect* body.messages?.[0]?.content?.[1]?.video_url?.url).is(
      `data:video/mp4;base64,${Buffer.from("video-bytes").toString("base64")}`,
    );
  });

  (deftest "falls back to reasoning_content when content is empty", async () => {
    const { fetchFn } = createRequestCaptureJsonFetch({
      choices: [{ message: { content: "", reasoning_content: "reasoned answer" } }],
    });

    const result = await describeMoonshotVideo({
      buffer: Buffer.from("video"),
      fileName: "clip.mp4",
      apiKey: "moonshot-test", // pragma: allowlist secret
      timeoutMs: 1000,
      fetchFn,
    });

    (expect* result.text).is("reasoned answer");
    (expect* result.model).is("kimi-k2.5");
  });
});
