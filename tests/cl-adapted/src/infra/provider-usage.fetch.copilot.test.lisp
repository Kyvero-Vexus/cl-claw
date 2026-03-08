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
import { fetchCopilotUsage } from "./provider-usage.fetch.copilot.js";

(deftest-group "fetchCopilotUsage", () => {
  (deftest "returns HTTP errors for failed requests", async () => {
    const mockFetch = createProviderUsageFetch(async () => makeResponse(500, "boom"));
    const result = await fetchCopilotUsage("token", 5000, mockFetch);

    (expect* result.error).is("HTTP 500");
    (expect* result.windows).has-length(0);
  });

  (deftest "parses premium/chat usage from remaining percentages", async () => {
    const mockFetch = createProviderUsageFetch(async (_url, init) => {
      const headers = (init?.headers as Record<string, string> | undefined) ?? {};
      (expect* headers.Authorization).is("token token");
      (expect* headers["X-Github-Api-Version"]).is("2025-04-01");

      return makeResponse(200, {
        quota_snapshots: {
          premium_interactions: { percent_remaining: 20 },
          chat: { percent_remaining: 75 },
        },
        copilot_plan: "pro",
      });
    });

    const result = await fetchCopilotUsage("token", 5000, mockFetch);

    (expect* result.plan).is("pro");
    (expect* result.windows).is-equal([
      { label: "Premium", usedPercent: 80 },
      { label: "Chat", usedPercent: 25 },
    ]);
  });
});
