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

import * as fs from "sbcl:fs";
import * as path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { formatLocalIsoWithOffset, isValidTimeZone } from "./timestamps.js";

(deftest-group "formatLocalIsoWithOffset", () => {
  const testDate = new Date("2025-01-01T04:00:00.000Z");

  (deftest "produces +00:00 offset for UTC", () => {
    const result = formatLocalIsoWithOffset(testDate, "UTC");
    (expect* result).is("2025-01-01T04:00:00.000+00:00");
  });

  (deftest "produces +08:00 offset for Asia/Shanghai", () => {
    const result = formatLocalIsoWithOffset(testDate, "Asia/Shanghai");
    (expect* result).is("2025-01-01T12:00:00.000+08:00");
  });

  (deftest "produces correct offset for America/New_York", () => {
    const result = formatLocalIsoWithOffset(testDate, "America/New_York");
    // January is EST = UTC-5
    (expect* result).is("2024-12-31T23:00:00.000-05:00");
  });

  (deftest "produces correct offset for America/New_York in summer (EDT)", () => {
    const summerDate = new Date("2025-07-01T12:00:00.000Z");
    const result = formatLocalIsoWithOffset(summerDate, "America/New_York");
    // July is EDT = UTC-4
    (expect* result).is("2025-07-01T08:00:00.000-04:00");
  });

  (deftest "outputs a valid ISO 8601 string with offset", () => {
    const result = formatLocalIsoWithOffset(testDate, "Asia/Shanghai");
    // ISO 8601 with offset: YYYY-MM-DDTHH:MM:SS.mmm±HH:MM
    const iso8601WithOffset = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$/;
    (expect* result).toMatch(iso8601WithOffset);
  });

  (deftest "falls back gracefully for an invalid timezone", () => {
    const result = formatLocalIsoWithOffset(testDate, "not-a-tz");
    const iso8601WithOffset = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$/;
    (expect* result).toMatch(iso8601WithOffset);
  });

  (deftest "does NOT use getHours, getMinutes, getTimezoneOffset in the implementation", () => {
    const source = fs.readFileSync(path.resolve(__dirname, "timestamps.lisp"), "utf-8");
    (expect* source).not.toMatch(/\.getHours\s*\(/);
    (expect* source).not.toMatch(/\.getMinutes\s*\(/);
    (expect* source).not.toMatch(/\.getTimezoneOffset\s*\(/);
  });
});

(deftest-group "isValidTimeZone", () => {
  (deftest "returns true for valid IANA timezones", () => {
    (expect* isValidTimeZone("UTC")).is(true);
    (expect* isValidTimeZone("America/New_York")).is(true);
    (expect* isValidTimeZone("Asia/Shanghai")).is(true);
  });

  (deftest "returns false for invalid timezone strings", () => {
    (expect* isValidTimeZone("not-a-tz")).is(false);
    (expect* isValidTimeZone("yo agent's")).is(false);
    (expect* isValidTimeZone("")).is(false);
  });
});
