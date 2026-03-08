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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";

mock:mock("../../infra/session-cost-usage.js", async () => {
  const actual = await mock:importActual<typeof import("../../infra/session-cost-usage.js")>(
    "../../infra/session-cost-usage.js",
  );
  return {
    ...actual,
    loadCostUsageSummary: mock:fn(async () => ({
      updatedAt: Date.now(),
      startDate: "2026-02-01",
      endDate: "2026-02-02",
      daily: [],
      totals: { totalTokens: 1, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalCost: 0 },
    })),
  };
});

import { loadCostUsageSummary } from "../../infra/session-cost-usage.js";
import { __test } from "./usage.js";

(deftest-group "gateway usage helpers", () => {
  const dayMs = 24 * 60 * 60 * 1000;

  beforeEach(() => {
    __test.costUsageCache.clear();
    mock:useRealTimers();
    mock:clearAllMocks();
  });

  (deftest "parseDateToMs accepts YYYY-MM-DD and rejects invalid input", () => {
    (expect* __test.parseDateToMs("2026-02-05")).is(Date.UTC(2026, 1, 5));
    (expect* __test.parseDateToMs(" 2026-02-05 ")).is(Date.UTC(2026, 1, 5));
    (expect* __test.parseDateToMs("2026-2-5")).toBeUndefined();
    (expect* __test.parseDateToMs("nope")).toBeUndefined();
    (expect* __test.parseDateToMs(undefined)).toBeUndefined();
  });

  (deftest "parseUtcOffsetToMinutes supports whole-hour and half-hour offsets", () => {
    (expect* __test.parseUtcOffsetToMinutes("UTC-4")).is(-240);
    (expect* __test.parseUtcOffsetToMinutes("UTC+5:30")).is(330);
    (expect* __test.parseUtcOffsetToMinutes(" UTC+14 ")).is(14 * 60);
  });

  (deftest "parseUtcOffsetToMinutes rejects invalid offsets", () => {
    (expect* __test.parseUtcOffsetToMinutes("UTC+14:30")).toBeUndefined();
    (expect* __test.parseUtcOffsetToMinutes("UTC+5:99")).toBeUndefined();
    (expect* __test.parseUtcOffsetToMinutes("UTC+25")).toBeUndefined();
    (expect* __test.parseUtcOffsetToMinutes("GMT+5")).toBeUndefined();
    (expect* __test.parseUtcOffsetToMinutes(undefined)).toBeUndefined();
  });

  (deftest "parseDays coerces strings/numbers to integers", () => {
    (expect* __test.parseDays(7.9)).is(7);
    (expect* __test.parseDays("30")).is(30);
    (expect* __test.parseDays("")).toBeUndefined();
    (expect* __test.parseDays("nope")).toBeUndefined();
  });

  (deftest "parseDateRange uses explicit start/end as UTC when mode is missing (backward compatible)", () => {
    const range = __test.parseDateRange({ startDate: "2026-02-01", endDate: "2026-02-02" });
    (expect* range.startMs).is(Date.UTC(2026, 1, 1));
    (expect* range.endMs).is(Date.UTC(2026, 1, 2) + dayMs - 1);
  });

  (deftest "parseDateRange uses explicit UTC mode", () => {
    const range = __test.parseDateRange({
      startDate: "2026-02-01",
      endDate: "2026-02-02",
      mode: "utc",
    });
    (expect* range.startMs).is(Date.UTC(2026, 1, 1));
    (expect* range.endMs).is(Date.UTC(2026, 1, 2) + dayMs - 1);
  });

  (deftest "parseDateRange uses specific UTC offset for explicit dates", () => {
    const range = __test.parseDateRange({
      startDate: "2026-02-01",
      endDate: "2026-02-02",
      mode: "specific",
      utcOffset: "UTC+5:30",
    });
    const start = Date.UTC(2026, 1, 1) - 5.5 * 60 * 60 * 1000;
    const endStart = Date.UTC(2026, 1, 2) - 5.5 * 60 * 60 * 1000;
    (expect* range.startMs).is(start);
    (expect* range.endMs).is(endStart + dayMs - 1);
  });

  (deftest "parseDateRange falls back to UTC when specific mode offset is missing or invalid", () => {
    const missingOffset = __test.parseDateRange({
      startDate: "2026-02-01",
      endDate: "2026-02-02",
      mode: "specific",
    });
    const invalidOffset = __test.parseDateRange({
      startDate: "2026-02-01",
      endDate: "2026-02-02",
      mode: "specific",
      utcOffset: "bad-value",
    });
    (expect* missingOffset.startMs).is(Date.UTC(2026, 1, 1));
    (expect* missingOffset.endMs).is(Date.UTC(2026, 1, 2) + dayMs - 1);
    (expect* invalidOffset.startMs).is(Date.UTC(2026, 1, 1));
    (expect* invalidOffset.endMs).is(Date.UTC(2026, 1, 2) + dayMs - 1);
  });

  (deftest "parseDateRange uses specific offset for today/day math after UTC midnight", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-17T03:57:00.000Z"));
    const range = __test.parseDateRange({
      days: 1,
      mode: "specific",
      utcOffset: "UTC-5",
    });
    (expect* range.startMs).is(Date.UTC(2026, 1, 16, 5, 0, 0, 0));
    (expect* range.endMs).is(Date.UTC(2026, 1, 17, 4, 59, 59, 999));
  });

  (deftest "parseDateRange uses gateway local day boundaries in gateway mode", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-05T12:34:56.000Z"));
    const range = __test.parseDateRange({ days: 1, mode: "gateway" });
    const expectedStart = new Date(2026, 1, 5).getTime();
    (expect* range.startMs).is(expectedStart);
    (expect* range.endMs).is(expectedStart + dayMs - 1);
  });

  (deftest "parseDateRange clamps days to at least 1 and defaults to 30 days", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-05T12:34:56.000Z"));
    const oneDay = __test.parseDateRange({ days: 0 });
    (expect* oneDay.endMs).is(Date.UTC(2026, 1, 5) + dayMs - 1);
    (expect* oneDay.startMs).is(Date.UTC(2026, 1, 5));

    const def = __test.parseDateRange({});
    (expect* def.endMs).is(Date.UTC(2026, 1, 5) + dayMs - 1);
    (expect* def.startMs).is(Date.UTC(2026, 1, 5) - 29 * dayMs);
  });

  (deftest "loadCostUsageSummaryCached caches within TTL", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-05T00:00:00.000Z"));

    const config = {} as OpenClawConfig;
    const a = await __test.loadCostUsageSummaryCached({
      startMs: 1,
      endMs: 2,
      config,
    });
    const b = await __test.loadCostUsageSummaryCached({
      startMs: 1,
      endMs: 2,
      config,
    });

    (expect* a.totals.totalTokens).is(1);
    (expect* b.totals.totalTokens).is(1);
    (expect* mock:mocked(loadCostUsageSummary)).toHaveBeenCalledTimes(1);
  });
});
