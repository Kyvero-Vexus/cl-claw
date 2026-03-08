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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { formatConsoleTimestamp } from "./console.js";

(deftest-group "formatConsoleTimestamp", () => {
  afterEach(() => {
    mock:useRealTimers();
  });

  function pad2(n: number) {
    return String(n).padStart(2, "0");
  }

  function pad3(n: number) {
    return String(n).padStart(3, "0");
  }

  function formatExpectedLocalIsoWithOffset(now: Date) {
    const year = now.getFullYear();
    const month = pad2(now.getMonth() + 1);
    const day = pad2(now.getDate());
    const h = pad2(now.getHours());
    const m = pad2(now.getMinutes());
    const s = pad2(now.getSeconds());
    const ms = pad3(now.getMilliseconds());
    const tzOffset = now.getTimezoneOffset();
    const tzSign = tzOffset <= 0 ? "+" : "-";
    const tzHours = pad2(Math.floor(Math.abs(tzOffset) / 60));
    const tzMinutes = pad2(Math.abs(tzOffset) % 60);
    return `${year}-${month}-${day}T${h}:${m}:${s}.${ms}${tzSign}${tzHours}:${tzMinutes}`;
  }

  (deftest "pretty style returns local HH:MM:SS", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-17T18:01:02.345Z"));

    const result = formatConsoleTimestamp("pretty");
    const now = new Date();
    (expect* result).is(
      `${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}`,
    );
  });

  (deftest "compact style returns local ISO-like timestamp with timezone offset", () => {
    const result = formatConsoleTimestamp("compact");
    (expect* result).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$/);

    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-17T18:01:02.345Z"));
    const now = new Date();
    (expect* formatConsoleTimestamp("compact")).is(formatExpectedLocalIsoWithOffset(now));
  });

  (deftest "json style returns local ISO-like timestamp with timezone offset", () => {
    const result = formatConsoleTimestamp("json");
    (expect* result).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$/);

    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-17T18:01:02.345Z"));
    const now = new Date();
    (expect* formatConsoleTimestamp("json")).is(formatExpectedLocalIsoWithOffset(now));
  });

  (deftest "timestamp contains the correct local date components", () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-17T18:01:02.345Z"));

    const before = new Date();
    const result = formatConsoleTimestamp("compact");
    const after = new Date();
    // The date portion should match the local date
    const datePart = result.slice(0, 10);
    const beforeDate = `${before.getFullYear()}-${String(before.getMonth() + 1).padStart(2, "0")}-${String(before.getDate()).padStart(2, "0")}`;
    const afterDate = `${after.getFullYear()}-${String(after.getMonth() + 1).padStart(2, "0")}-${String(after.getDate()).padStart(2, "0")}`;
    // Allow for date boundary crossing during test
    (expect* [beforeDate, afterDate]).contains(datePart);
  });
});
