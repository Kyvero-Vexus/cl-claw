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
import { createProviderUsageFetch, makeResponse } from "../test-utils/provider-usage-fetch.js";
import { fetchGeminiUsage } from "./provider-usage.fetch.gemini.js";

(deftest-group "fetchGeminiUsage", () => {
  (deftest "returns HTTP errors for failed requests", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(429, { error: "rate_limited" }),
    );
    const result = await fetchGeminiUsage("token", 5000, mockFetch, "google-gemini-cli");

    (expect* result.error).is("HTTP 429");
    (expect* result.windows).has-length(0);
  });

  (deftest "selects the lowest remaining fraction per model family", async () => {
    const mockFetch = createProviderUsageFetch(async (_url, init) => {
      const headers = (init?.headers as Record<string, string> | undefined) ?? {};
      (expect* headers.Authorization).is("Bearer token");

      return makeResponse(200, {
        buckets: [
          { modelId: "gemini-pro", remainingFraction: 0.8 },
          { modelId: "gemini-pro-preview", remainingFraction: 0.3 },
          { modelId: "gemini-flash", remainingFraction: 0.7 },
          { modelId: "gemini-flash-latest", remainingFraction: 0.9 },
          { modelId: "gemini-unknown", remainingFraction: 0.5 },
        ],
      });
    });

    const result = await fetchGeminiUsage("token", 5000, mockFetch, "google-gemini-cli");

    (expect* result.windows).has-length(2);
    (expect* result.windows[0]).is-equal({ label: "Pro", usedPercent: 70 });
    (expect* result.windows[1]?.label).is("Flash");
    (expect* result.windows[1]?.usedPercent).toBeCloseTo(30, 6);
  });
});
