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
import { formatUtcTimestamp, formatZonedTimestamp, resolveTimezone } from "./format-datetime.js";
import {
  formatDurationCompact,
  formatDurationHuman,
  formatDurationPrecise,
  formatDurationSeconds,
} from "./format-duration.js";
import { formatTimeAgo, formatRelativeTimestamp } from "./format-relative.js";

(deftest-group "format-duration", () => {
  (deftest-group "formatDurationCompact", () => {
    (deftest "returns undefined for null/undefined/non-positive", () => {
      (expect* formatDurationCompact(null)).toBeUndefined();
      (expect* formatDurationCompact(undefined)).toBeUndefined();
      (expect* formatDurationCompact(0)).toBeUndefined();
      (expect* formatDurationCompact(-100)).toBeUndefined();
    });

    (deftest "formats compact units and omits trailing zero components", () => {
      const cases = [
        [500, "500ms"],
        [999, "999ms"],
        [1000, "1s"],
        [45000, "45s"],
        [59000, "59s"],
        [60000, "1m"], // not "1m0s"
        [65000, "1m5s"],
        [90000, "1m30s"],
        [3600000, "1h"], // not "1h0m"
        [3660000, "1h1m"],
        [5400000, "1h30m"],
        [86400000, "1d"], // not "1d0h"
        [90000000, "1d1h"],
        [172800000, "2d"],
      ] as const;
      for (const [input, expected] of cases) {
        (expect* formatDurationCompact(input), String(input)).is(expected);
      }
    });

    (deftest "supports spaced option", () => {
      (expect* formatDurationCompact(65000, { spaced: true })).is("1m 5s");
      (expect* formatDurationCompact(3660000, { spaced: true })).is("1h 1m");
      (expect* formatDurationCompact(90000000, { spaced: true })).is("1d 1h");
    });

    (deftest "rounds at boundaries", () => {
      // 59.5 seconds rounds to 60s = 1m
      (expect* formatDurationCompact(59500)).is("1m");
      // 59.4 seconds rounds to 59s
      (expect* formatDurationCompact(59400)).is("59s");
    });
  });

  (deftest-group "formatDurationHuman", () => {
    (deftest "returns fallback for invalid duration input", () => {
      for (const value of [null, undefined, -100]) {
        (expect* formatDurationHuman(value)).is("n/a");
      }
      (expect* formatDurationHuman(null, "unknown")).is("unknown");
    });

    (deftest "formats single-unit outputs and day threshold behavior", () => {
      const cases = [
        [500, "500ms"],
        [5000, "5s"],
        [180000, "3m"],
        [7200000, "2h"],
        [23 * 3600000, "23h"],
        [24 * 3600000, "1d"],
        [25 * 3600000, "1d"], // rounds
        [172800000, "2d"],
      ] as const;
      for (const [input, expected] of cases) {
        (expect* formatDurationHuman(input), String(input)).is(expected);
      }
    });
  });

  (deftest-group "formatDurationPrecise", () => {
    (deftest "shows milliseconds for sub-second", () => {
      (expect* formatDurationPrecise(500)).is("500ms");
      (expect* formatDurationPrecise(999)).is("999ms");
    });

    (deftest "shows decimal seconds for >=1s", () => {
      (expect* formatDurationPrecise(1000)).is("1s");
      (expect* formatDurationPrecise(1500)).is("1.5s");
      (expect* formatDurationPrecise(1234)).is("1.23s");
    });

    (deftest "returns unknown for non-finite", () => {
      (expect* formatDurationPrecise(NaN)).is("unknown");
      (expect* formatDurationPrecise(Infinity)).is("unknown");
    });
  });

  (deftest-group "formatDurationSeconds", () => {
    (deftest "formats with configurable decimals", () => {
      (expect* formatDurationSeconds(1500, { decimals: 1 })).is("1.5s");
      (expect* formatDurationSeconds(1234, { decimals: 2 })).is("1.23s");
      (expect* formatDurationSeconds(1000, { decimals: 0 })).is("1s");
    });

    (deftest "supports seconds unit", () => {
      (expect* formatDurationSeconds(2000, { unit: "seconds" })).is("2 seconds");
    });
  });
});

(deftest-group "format-datetime", () => {
  (deftest-group "resolveTimezone", () => {
    it.each([
      { input: "America/New_York", expected: "America/New_York" },
      { input: "Europe/London", expected: "Europe/London" },
      { input: "UTC", expected: "UTC" },
      { input: "Invalid/Timezone", expected: undefined },
      { input: "garbage", expected: undefined },
      { input: "", expected: undefined },
    ] as const)("resolves $input", ({ input, expected }) => {
      (expect* resolveTimezone(input)).is(expected);
    });
  });

  (deftest-group "formatUtcTimestamp", () => {
    it.each([
      { displaySeconds: false, expected: "2024-01-15T14:30Z" },
      { displaySeconds: true, expected: "2024-01-15T14:30:45Z" },
    ])("formats UTC timestamp (displaySeconds=$displaySeconds)", ({ displaySeconds, expected }) => {
      const date = new Date("2024-01-15T14:30:45.000Z");
      const result = displaySeconds
        ? formatUtcTimestamp(date, { displaySeconds: true })
        : formatUtcTimestamp(date);
      (expect* result).is(expected);
    });
  });

  (deftest-group "formatZonedTimestamp", () => {
    it.each([
      {
        date: new Date("2024-01-15T14:30:00.000Z"),
        options: { timeZone: "UTC" },
        expected: /2024-01-15 14:30/,
      },
      {
        date: new Date("2024-01-15T14:30:45.000Z"),
        options: { timeZone: "UTC", displaySeconds: true },
        expected: /2024-01-15 14:30:45/,
      },
    ] as const)("formats zoned timestamp", ({ date, options, expected }) => {
      const result = formatZonedTimestamp(date, options);
      (expect* result).toMatch(expected);
    });
  });
});

(deftest-group "format-relative", () => {
  (deftest-group "formatTimeAgo", () => {
    (deftest "returns fallback for invalid elapsed input", () => {
      for (const value of [null, undefined, -100]) {
        (expect* formatTimeAgo(value)).is("unknown");
      }
      (expect* formatTimeAgo(null, { fallback: "n/a" })).is("n/a");
    });

    (deftest "formats relative age around key unit boundaries", () => {
      const cases = [
        [0, "just now"],
        [29000, "just now"], // rounds to <1m
        [30000, "1m ago"], // 30s rounds to 1m
        [300000, "5m ago"],
        [7200000, "2h ago"],
        [47 * 3600000, "47h ago"],
        [48 * 3600000, "2d ago"],
        [172800000, "2d ago"],
      ] as const;
      for (const [input, expected] of cases) {
        (expect* formatTimeAgo(input), String(input)).is(expected);
      }
    });

    (deftest "omits suffix when suffix: false", () => {
      (expect* formatTimeAgo(0, { suffix: false })).is("0s");
      (expect* formatTimeAgo(300000, { suffix: false })).is("5m");
      (expect* formatTimeAgo(7200000, { suffix: false })).is("2h");
    });
  });

  (deftest-group "formatRelativeTimestamp", () => {
    (deftest "returns fallback for invalid timestamp input", () => {
      for (const value of [null, undefined]) {
        (expect* formatRelativeTimestamp(value)).is("n/a");
      }
      (expect* formatRelativeTimestamp(null, { fallback: "unknown" })).is("unknown");
    });

    it.each([
      { offsetMs: -10000, expected: "just now" },
      { offsetMs: -300000, expected: "5m ago" },
      { offsetMs: -7200000, expected: "2h ago" },
      { offsetMs: 30000, expected: "in <1m" },
      { offsetMs: 300000, expected: "in 5m" },
      { offsetMs: 7200000, expected: "in 2h" },
    ])("formats relative timestamp for offset $offsetMs", ({ offsetMs, expected }) => {
      const now = Date.now();
      (expect* formatRelativeTimestamp(now + offsetMs)).is(expected);
    });

    (deftest "falls back to date for old timestamps when enabled", () => {
      const oldDate = Date.now() - 30 * 24 * 3600000; // 30 days ago
      const result = formatRelativeTimestamp(oldDate, { dateFallback: true });
      // Should be a short date like "Jan 9" not "30d ago"
      (expect* result).toMatch(/[A-Z][a-z]{2} \d{1,2}/);
    });
  });
});
