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
  formatUsageReportLines,
  formatUsageSummaryLine,
  formatUsageWindowSummary,
} from "./provider-usage.format.js";
import type { ProviderUsageSnapshot, UsageSummary } from "./provider-usage.types.js";

const now = Date.UTC(2026, 0, 7, 12, 0, 0);

function makeSnapshot(windows: ProviderUsageSnapshot["windows"]): ProviderUsageSnapshot {
  return {
    provider: "anthropic",
    displayName: "Claude",
    windows,
  };
}

(deftest-group "provider-usage.format", () => {
  (deftest "returns null summary for errored or empty snapshots", () => {
    (expect* formatUsageWindowSummary({ ...makeSnapshot([]), error: "HTTP 401" })).toBeNull();
    (expect* formatUsageWindowSummary(makeSnapshot([]))).toBeNull();
  });

  (deftest "formats reset windows across now/minute/hour/day/date buckets", () => {
    const summary = formatUsageWindowSummary(
      makeSnapshot([
        { label: "Now", usedPercent: 10, resetAt: now - 1 },
        { label: "Minute", usedPercent: 20, resetAt: now + 30 * 60_000 },
        { label: "Hour", usedPercent: 30, resetAt: now + 2 * 60 * 60_000 + 15 * 60_000 },
        { label: "Day", usedPercent: 40, resetAt: now + (2 * 24 + 3) * 60 * 60_000 },
        { label: "Date", usedPercent: 50, resetAt: Date.UTC(2026, 0, 20, 12, 0, 0) },
      ]),
      { now, includeResets: true },
    );

    (expect* summary).contains("Now 90% left ⏱now");
    (expect* summary).contains("Minute 80% left ⏱30m");
    (expect* summary).contains("Hour 70% left ⏱2h 15m");
    (expect* summary).contains("Day 60% left ⏱2d 3h");
    (expect* summary).toMatch(/Date 50% left ⏱[A-Z][a-z]{2} \d{1,2}/);
  });

  (deftest "honors max windows and reset toggle", () => {
    const summary = formatUsageWindowSummary(
      makeSnapshot([
        { label: "A", usedPercent: 10, resetAt: now + 60_000 },
        { label: "B", usedPercent: 20, resetAt: now + 120_000 },
        { label: "C", usedPercent: 30, resetAt: now + 180_000 },
      ]),
      { now, maxWindows: 2, includeResets: false },
    );

    (expect* summary).is("A 90% left · B 80% left");
  });

  (deftest "formats summary line from highest-usage window and provider cap", () => {
    const summary: UsageSummary = {
      updatedAt: now,
      providers: [
        {
          provider: "anthropic",
          displayName: "Claude",
          windows: [
            { label: "5h", usedPercent: 20 },
            { label: "Week", usedPercent: 70 },
          ],
        },
        {
          provider: "zai",
          displayName: "z.ai",
          windows: [{ label: "Day", usedPercent: 10 }],
        },
      ],
    };

    (expect* formatUsageSummaryLine(summary, { now, maxProviders: 1 })).is(
      "📊 Usage: Claude 30% left (Week)",
    );
  });

  (deftest "formats report output for empty, error, no-data, and plan entries", () => {
    (expect* formatUsageReportLines({ updatedAt: now, providers: [] })).is-equal([
      "Usage: no provider usage available.",
    ]);

    const summary: UsageSummary = {
      updatedAt: now,
      providers: [
        {
          provider: "openai-codex",
          displayName: "Codex",
          windows: [],
          error: "Token expired",
          plan: "Plus",
        },
        {
          provider: "xiaomi",
          displayName: "Xiaomi",
          windows: [],
        },
      ],
    };
    (expect* formatUsageReportLines(summary)).is-equal([
      "Usage:",
      "  Codex (Plus): Token expired",
      "  Xiaomi: no data",
    ]);
  });
});
