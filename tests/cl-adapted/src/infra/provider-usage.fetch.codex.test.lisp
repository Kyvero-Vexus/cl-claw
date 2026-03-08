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
import { fetchCodexUsage } from "./provider-usage.fetch.codex.js";

(deftest-group "fetchCodexUsage", () => {
  (deftest "returns token expired for auth failures", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(401, { error: "unauthorized" }),
    );

    const result = await fetchCodexUsage("token", undefined, 5000, mockFetch);
    (expect* result.error).is("Token expired");
    (expect* result.windows).has-length(0);
  });

  (deftest "returns HTTP status errors for non-auth failures", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(429, { error: "throttled" }),
    );

    const result = await fetchCodexUsage("token", undefined, 5000, mockFetch);
    (expect* result.error).is("HTTP 429");
    (expect* result.windows).has-length(0);
  });

  (deftest "parses windows, reset times, and plan balance", async () => {
    const mockFetch = createProviderUsageFetch(async (_url, init) => {
      const headers = (init?.headers as Record<string, string> | undefined) ?? {};
      (expect* headers["ChatGPT-Account-Id"]).is("acct-1");
      return makeResponse(200, {
        rate_limit: {
          primary_window: {
            limit_window_seconds: 10_800,
            used_percent: 35.5,
            reset_at: 1_700_000_000,
          },
          secondary_window: {
            limit_window_seconds: 86_400,
            used_percent: 75,
            reset_at: 1_700_050_000,
          },
        },
        plan_type: "Plus",
        credits: { balance: "12.5" },
      });
    });

    const result = await fetchCodexUsage("token", "acct-1", 5000, mockFetch);

    (expect* result.provider).is("openai-codex");
    (expect* result.plan).is("Plus ($12.50)");
    (expect* result.windows).is-equal([
      { label: "3h", usedPercent: 35.5, resetAt: 1_700_000_000_000 },
      { label: "Day", usedPercent: 75, resetAt: 1_700_050_000_000 },
    ]);
  });

  (deftest "labels weekly secondary window as Week", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, {
        rate_limit: {
          primary_window: {
            limit_window_seconds: 10_800,
            used_percent: 7,
            reset_at: 1_700_000_000,
          },
          secondary_window: {
            limit_window_seconds: 604_800,
            used_percent: 10,
            reset_at: 1_700_500_000,
          },
        },
      }),
    );

    const result = await fetchCodexUsage("token", undefined, 5000, mockFetch);
    (expect* result.windows).is-equal([
      { label: "3h", usedPercent: 7, resetAt: 1_700_000_000_000 },
      { label: "Week", usedPercent: 10, resetAt: 1_700_500_000_000 },
    ]);
  });

  (deftest "labels secondary window as Week when reset cadence clearly exceeds one day", async () => {
    const primaryReset = 1_700_000_000;
    const weeklyLikeSecondaryReset = primaryReset + 5 * 24 * 60 * 60;
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, {
        rate_limit: {
          primary_window: {
            limit_window_seconds: 10_800,
            used_percent: 14,
            reset_at: primaryReset,
          },
          secondary_window: {
            // Observed in production: API reports 24h, but dashboard shows a weekly window.
            limit_window_seconds: 86_400,
            used_percent: 20,
            reset_at: weeklyLikeSecondaryReset,
          },
        },
      }),
    );

    const result = await fetchCodexUsage("token", undefined, 5000, mockFetch);
    (expect* result.windows).is-equal([
      { label: "3h", usedPercent: 14, resetAt: 1_700_000_000_000 },
      { label: "Week", usedPercent: 20, resetAt: weeklyLikeSecondaryReset * 1000 },
    ]);
  });
});
