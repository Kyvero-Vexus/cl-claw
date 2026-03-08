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
import { validateConfigObject } from "./config.js";

(deftest-group "meta.lastTouchedAt numeric timestamp coercion", () => {
  (deftest "accepts a numeric Unix timestamp and coerces it to an ISO string", () => {
    const numericTimestamp = 1770394758161;
    const res = validateConfigObject({
      meta: {
        lastTouchedAt: numericTimestamp,
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* typeof res.config.meta?.lastTouchedAt).is("string");
      (expect* res.config.meta?.lastTouchedAt).is(new Date(numericTimestamp).toISOString());
    }
  });

  (deftest "still accepts a string ISO timestamp unchanged", () => {
    const isoTimestamp = "2026-02-07T01:39:18.161Z";
    const res = validateConfigObject({
      meta: {
        lastTouchedAt: isoTimestamp,
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.meta?.lastTouchedAt).is(isoTimestamp);
    }
  });

  (deftest "rejects out-of-range numeric timestamps without throwing", () => {
    const res = validateConfigObject({
      meta: {
        lastTouchedAt: 1e20,
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "passes non-date strings through unchanged (backwards-compatible)", () => {
    const res = validateConfigObject({
      meta: {
        lastTouchedAt: "not-a-date",
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.meta?.lastTouchedAt).is("not-a-date");
    }
  });

  (deftest "accepts meta with only lastTouchedVersion (no lastTouchedAt)", () => {
    const res = validateConfigObject({
      meta: {
        lastTouchedVersion: "2026.2.6",
      },
    });
    (expect* res.ok).is(true);
  });
});
