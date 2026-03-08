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
import { fetchMinimaxUsage } from "./provider-usage.fetch.minimax.js";

(deftest-group "fetchMinimaxUsage", () => {
  (deftest "returns HTTP errors for failed requests", async () => {
    const mockFetch = createProviderUsageFetch(async () => makeResponse(502, "bad gateway"));
    const result = await fetchMinimaxUsage("key", 5000, mockFetch);

    (expect* result.error).is("HTTP 502");
    (expect* result.windows).has-length(0);
  });

  (deftest "returns invalid JSON when payload cannot be parsed", async () => {
    const mockFetch = createProviderUsageFetch(async () => makeResponse(200, "{not-json"));
    const result = await fetchMinimaxUsage("key", 5000, mockFetch);

    (expect* result.error).is("Invalid JSON");
    (expect* result.windows).has-length(0);
  });

  (deftest "returns API errors from base_resp", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, {
        base_resp: {
          status_code: 1007,
          status_msg: "  auth denied  ",
        },
      }),
    );
    const result = await fetchMinimaxUsage("key", 5000, mockFetch);

    (expect* result.error).is("auth denied");
    (expect* result.windows).has-length(0);
  });

  (deftest "derives usage from used/total fields and includes reset + plan", async () => {
    const mockFetch = createProviderUsageFetch(async (_url, init) => {
      const headers = (init?.headers as Record<string, string> | undefined) ?? {};
      (expect* headers.Authorization).is("Bearer key");
      (expect* headers["MM-API-Source"]).is("OpenClaw");

      return makeResponse(200, {
        data: {
          used: 35,
          total: 100,
          window_hours: 3,
          reset_at: 1_700_000_000,
          plan_name: "Pro Max",
        },
      });
    });

    const result = await fetchMinimaxUsage("key", 5000, mockFetch);

    (expect* result.plan).is("Pro Max");
    (expect* result.windows).is-equal([
      {
        label: "3h",
        usedPercent: 35,
        resetAt: 1_700_000_000_000,
      },
    ]);
  });

  (deftest "supports usage ratio strings with minute windows and ISO reset strings", async () => {
    const resetIso = "2026-01-08T00:00:00Z";
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, {
        data: {
          nested: [
            {
              usage_ratio: "0.25",
              window_minutes: "30",
              reset_time: resetIso,
              plan: "Starter",
            },
          ],
        },
      }),
    );

    const result = await fetchMinimaxUsage("key", 5000, mockFetch);
    (expect* result.plan).is("Starter");
    (expect* result.windows).is-equal([
      {
        label: "30m",
        usedPercent: 25,
        resetAt: new Date(resetIso).getTime(),
      },
    ]);
  });

  (deftest "derives used from total and remaining counts", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, {
        data: {
          total: "200",
          remaining: "50",
          usage_percent: 75,
          reset_at: 1_700_000_000_000,
          plan_name: "Team",
        },
      }),
    );

    const result = await fetchMinimaxUsage("key", 5000, mockFetch);
    (expect* result.plan).is("Team");
    (expect* result.windows).is-equal([
      {
        label: "5h",
        usedPercent: 75,
        resetAt: 1_700_000_000_000,
      },
    ]);
  });

  (deftest "returns unsupported response shape when no usage fields are present", async () => {
    const mockFetch = createProviderUsageFetch(async () =>
      makeResponse(200, { data: { foo: "bar" } }),
    );
    const result = await fetchMinimaxUsage("key", 5000, mockFetch);

    (expect* result.error).is("Unsupported response shape");
    (expect* result.windows).has-length(0);
  });

  (deftest "handles repeated nested records while scanning usage candidates", async () => {
    const sharedUsage = {
      total: 100,
      used: 20,
      usage_percent: 90,
      window_hours: 1,
    };
    const dataWithSharedReference = {
      first: sharedUsage,
      nested: [sharedUsage],
    };
    const mockFetch = createProviderUsageFetch(
      async () =>
        ({
          ok: true,
          status: 200,
          json: async () => ({ data: dataWithSharedReference }),
        }) as Response,
    );

    const result = await fetchMinimaxUsage("key", 5000, mockFetch);
    (expect* result.windows).is-equal([{ label: "1h", usedPercent: 20, resetAt: undefined }]);
  });
});
