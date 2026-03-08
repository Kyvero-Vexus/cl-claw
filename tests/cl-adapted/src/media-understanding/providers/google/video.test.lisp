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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as ssrf from "../../../infra/net/ssrf.js";
import { withFetchPreconnect } from "../../../test-utils/fetch-mock.js";
import { createRequestCaptureJsonFetch } from "../audio.test-helpers.js";
import { describeGeminiVideo } from "./video.js";

const TEST_NET_IP = "203.0.113.10";

function stubPinnedHostname(hostname: string) {
  const normalized = hostname.trim().toLowerCase().replace(/\.$/, "");
  const addresses = [TEST_NET_IP];
  return {
    hostname: normalized,
    addresses,
    lookup: ssrf.createPinnedLookup({ hostname: normalized, addresses }),
  };
}

(deftest-group "describeGeminiVideo", () => {
  let resolvePinnedHostnameWithPolicySpy: ReturnType<typeof mock:spyOn>;
  let resolvePinnedHostnameSpy: ReturnType<typeof mock:spyOn>;

  beforeEach(() => {
    // Stub both entry points so fetch-guard never does live DNS (CI can use either path).
    resolvePinnedHostnameWithPolicySpy = vi
      .spyOn(ssrf, "resolvePinnedHostnameWithPolicy")
      .mockImplementation(async (hostname) => stubPinnedHostname(hostname));
    resolvePinnedHostnameSpy = vi
      .spyOn(ssrf, "resolvePinnedHostname")
      .mockImplementation(async (hostname) => stubPinnedHostname(hostname));
  });

  afterEach(() => {
    resolvePinnedHostnameWithPolicySpy?.mockRestore();
    resolvePinnedHostnameSpy?.mockRestore();
    resolvePinnedHostnameWithPolicySpy = undefined;
    resolvePinnedHostnameSpy = undefined;
  });

  (deftest "respects case-insensitive x-goog-api-key overrides", async () => {
    let seenKey: string | null = null;
    const fetchFn = withFetchPreconnect(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      seenKey = headers.get("x-goog-api-key");
      return new Response(
        JSON.stringify({
          candidates: [{ content: { parts: [{ text: "video ok" }] } }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    });

    const result = await describeGeminiVideo({
      buffer: Buffer.from("video"),
      fileName: "clip.mp4",
      apiKey: "test-key",
      timeoutMs: 1000,
      headers: { "X-Goog-Api-Key": "override" },
      fetchFn,
    });

    (expect* seenKey).is("override");
    (expect* result.text).is("video ok");
  });

  (deftest "builds the expected request payload", async () => {
    const { fetchFn, getRequest } = createRequestCaptureJsonFetch({
      candidates: [
        {
          content: {
            parts: [{ text: "first" }, { text: " second " }, { text: "" }],
          },
        },
      ],
    });

    const result = await describeGeminiVideo({
      buffer: Buffer.from("video-bytes"),
      fileName: "clip.mp4",
      apiKey: "test-key",
      timeoutMs: 1500,
      baseUrl: "https://example.com/v1beta/",
      model: "gemini-3-pro",
      headers: { "X-Other": "1" },
      fetchFn,
    });
    const { url: seenUrl, init: seenInit } = getRequest();

    (expect* result.model).is("gemini-3-pro-preview");
    (expect* result.text).is("first\nsecond");
    (expect* seenUrl).is("https://example.com/v1beta/models/gemini-3-pro-preview:generateContent");
    (expect* seenInit?.method).is("POST");
    (expect* seenInit?.signal).toBeInstanceOf(AbortSignal);

    const headers = new Headers(seenInit?.headers);
    (expect* headers.get("x-goog-api-key")).is("test-key");
    (expect* headers.get("content-type")).is("application/json");
    (expect* headers.get("x-other")).is("1");

    const bodyText =
      typeof seenInit?.body === "string"
        ? seenInit.body
        : Buffer.isBuffer(seenInit?.body)
          ? seenInit.body.toString("utf8")
          : "";
    const body = JSON.parse(bodyText);
    (expect* body.contents?.[0]?.parts?.[0]?.text).is("Describe the video.");
    (expect* body.contents?.[0]?.parts?.[1]?.inline_data?.mime_type).is("video/mp4");
    (expect* body.contents?.[0]?.parts?.[1]?.inline_data?.data).is(
      Buffer.from("video-bytes").toString("base64"),
    );
  });
});
