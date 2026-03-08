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
import { fetchZaiUsage } from "./provider-usage.fetch.zai.js";

(deftest-group "fetchZaiUsage", () => {
  (deftest "returns HTTP errors for failed requests", async () => {
    const mockFetch = createProviderUsageFetch(async () => makeResponse(503, "unavailable"));
    const result = await fetchZaiUsage("key", 5000, mockFetch);

    (expect* result.error).is("HTTP 503");
    (expect* result.windows).has-length(0);
  });

  (deftest "returns API message errors for unsuccessful payloads", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, {
        success: false,
        code: 500,
        msg: "quota endpoint disabled",
      }),
    );

    const result = await fetchZaiUsage("key", 5000, mockFetch);
    (expect* result.error).is("quota endpoint disabled");
    (expect* result.windows).has-length(0);
  });

  (deftest "parses token and monthly windows with reset times", async () => {
    const tokenReset = "2026-01-08T00:00:00Z";
    const minuteReset = "2026-01-08T00:30:00Z";
    const monthlyReset = "2026-01-31T12:00:00Z";
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, {
        success: true,
        code: 200,
        data: {
          planName: "Team",
          limits: [
            {
              type: "TOKENS_LIMIT",
              percentage: 32,
              unit: 3,
              number: 6,
              nextResetTime: tokenReset,
            },
            {
              type: "TOKENS_LIMIT",
              percentage: 8,
              unit: 5,
              number: 15,
              nextResetTime: minuteReset,
            },
            {
              type: "TIME_LIMIT",
              percentage: 12.5,
              unit: 1,
              number: 30,
              nextResetTime: monthlyReset,
            },
          ],
        },
      }),
    );

    const result = await fetchZaiUsage("key", 5000, mockFetch);

    (expect* result.plan).is("Team");
    (expect* result.windows).is-equal([
      {
        label: "Tokens (6h)",
        usedPercent: 32,
        resetAt: new Date(tokenReset).getTime(),
      },
      {
        label: "Tokens (15m)",
        usedPercent: 8,
        resetAt: new Date(minuteReset).getTime(),
      },
      {
        label: "Monthly",
        usedPercent: 12.5,
        resetAt: new Date(monthlyReset).getTime(),
      },
    ]);
  });
});
