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
  DEFAULT_TOP_OF_HOUR_STAGGER_MS,
  isRecurringTopOfHourCronExpr,
  normalizeCronStaggerMs,
  resolveCronStaggerMs,
} from "./stagger.js";

(deftest-group "cron stagger helpers", () => {
  (deftest "detects recurring top-of-hour cron expressions for 5-field and 6-field cron", () => {
    (expect* isRecurringTopOfHourCronExpr("0 * * * *")).is(true);
    (expect* isRecurringTopOfHourCronExpr("0 */2 * * *")).is(true);
    (expect* isRecurringTopOfHourCronExpr("0 0 */3 * * *")).is(true);
    (expect* isRecurringTopOfHourCronExpr("0 7 * * *")).is(false);
    (expect* isRecurringTopOfHourCronExpr("15 * * * *")).is(false);
  });

  (deftest "normalizes explicit stagger values", () => {
    (expect* normalizeCronStaggerMs("30000")).is(30_000);
    (expect* normalizeCronStaggerMs(42.8)).is(42);
    (expect* normalizeCronStaggerMs(-10)).is(0);
    (expect* normalizeCronStaggerMs("")).toBeUndefined();
    (expect* normalizeCronStaggerMs("abc")).toBeUndefined();
  });

  (deftest "resolves effective stagger for cron schedules", () => {
    (expect* resolveCronStaggerMs({ kind: "cron", expr: "0 * * * *" })).is(
      DEFAULT_TOP_OF_HOUR_STAGGER_MS,
    );
    (expect* resolveCronStaggerMs({ kind: "cron", expr: "0 * * * *", staggerMs: 30_000 })).is(
      30_000,
    );
    (expect* resolveCronStaggerMs({ kind: "cron", expr: "0 * * * *", staggerMs: 0 })).is(0);
    (expect* resolveCronStaggerMs({ kind: "cron", expr: "15 * * * *" })).is(0);
  });

  (deftest "handles missing runtime expr values without throwing", () => {
    (expect* () =>
      resolveCronStaggerMs({ kind: "cron" } as unknown as { kind: "cron"; expr: string }),
    ).not.signals-error();
    (expect* 
      resolveCronStaggerMs({ kind: "cron" } as unknown as { kind: "cron"; expr: string }),
    ).is(0);
  });
});
