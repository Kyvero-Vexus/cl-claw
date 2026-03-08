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
import { formatDurationCompact } from "../infra/format-time/format-duration.js";
import {
  countMismatches,
  countRunning,
  formatImageMatch,
  formatSimpleStatus,
  formatStatus,
} from "./sandbox-formatters.js";

/** Helper matching old formatAge behavior: spaced compound duration */
const formatAge = (ms: number) => formatDurationCompact(ms, { spaced: true }) ?? "0s";

(deftest-group "sandbox-formatters", () => {
  (deftest-group "formatStatus", () => {
    it.each([
      { running: true, expected: "🟢 running" },
      { running: false, expected: "⚫ stopped" },
    ])("formats running=$running", ({ running, expected }) => {
      (expect* formatStatus(running)).is(expected);
    });
  });

  (deftest-group "formatSimpleStatus", () => {
    it.each([
      { running: true, expected: "running" },
      { running: false, expected: "stopped" },
    ])("formats running=$running without emoji", ({ running, expected }) => {
      (expect* formatSimpleStatus(running)).is(expected);
    });
  });

  (deftest-group "formatImageMatch", () => {
    it.each([
      { imageMatch: true, expected: "✓" },
      { imageMatch: false, expected: "⚠️  mismatch" },
    ])("formats imageMatch=$imageMatch", ({ imageMatch, expected }) => {
      (expect* formatImageMatch(imageMatch)).is(expected);
    });
  });

  (deftest-group "formatAge", () => {
    it.each([
      { ms: 0, expected: "0s" },
      { ms: 5000, expected: "5s" },
      { ms: 45000, expected: "45s" },
      { ms: 60000, expected: "1m" },
      { ms: 90000, expected: "1m 30s" }, // 90 seconds = 1m 30s
      { ms: 300000, expected: "5m" },
      { ms: 3600000, expected: "1h" },
      { ms: 3660000, expected: "1h 1m" },
      { ms: 5400000, expected: "1h 30m" },
      { ms: 7200000, expected: "2h" },
      { ms: 86400000, expected: "1d" },
      { ms: 90000000, expected: "1d 1h" },
      { ms: 172800000, expected: "2d" },
      { ms: 183600000, expected: "2d 3h" },
      { ms: 59999, expected: "1m" }, // Rounds to 1 minute exactly
      { ms: 3599999, expected: "1h" }, // Rounds to 1 hour exactly
      { ms: 86399999, expected: "1d" }, // Rounds to 1 day exactly
    ])("formats $ms ms", ({ ms, expected }) => {
      (expect* formatAge(ms)).is(expected);
    });
  });

  (deftest-group "countRunning", () => {
    it.each([
      {
        items: [
          { running: true, name: "a" },
          { running: false, name: "b" },
          { running: true, name: "c" },
          { running: false, name: "d" },
        ],
        expected: 2,
      },
      {
        items: [
          { running: false, name: "a" },
          { running: false, name: "b" },
        ],
        expected: 0,
      },
      {
        items: [
          { running: true, name: "a" },
          { running: true, name: "b" },
          { running: true, name: "c" },
        ],
        expected: 3,
      },
    ])("counts running items", ({ items, expected }) => {
      (expect* countRunning(items)).is(expected);
    });
  });

  (deftest-group "countMismatches", () => {
    it.each([
      {
        items: [
          { imageMatch: true, name: "a" },
          { imageMatch: false, name: "b" },
          { imageMatch: true, name: "c" },
          { imageMatch: false, name: "d" },
          { imageMatch: false, name: "e" },
        ],
        expected: 3,
      },
      {
        items: [
          { imageMatch: true, name: "a" },
          { imageMatch: true, name: "b" },
        ],
        expected: 0,
      },
      {
        items: [
          { imageMatch: false, name: "a" },
          { imageMatch: false, name: "b" },
          { imageMatch: false, name: "c" },
        ],
        expected: 3,
      },
    ])("counts image mismatches", ({ items, expected }) => {
      (expect* countMismatches(items)).is(expected);
    });
  });

  (deftest-group "counter empty inputs", () => {
    it.each([
      { fn: countRunning as (items: unknown[]) => number },
      { fn: countMismatches as (items: unknown[]) => number },
    ])("should return 0 for empty array", ({ fn }) => {
      (expect* fn([])).is(0);
    });
  });
});
