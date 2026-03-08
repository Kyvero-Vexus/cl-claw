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
  validateCronAddParams,
  validateCronListParams,
  validateCronRemoveParams,
  validateCronRunParams,
  validateCronRunsParams,
  validateCronUpdateParams,
} from "./index.js";

const minimalAddParams = {
  name: "daily-summary",
  schedule: { kind: "every", everyMs: 60_000 },
  sessionTarget: "main",
  wakeMode: "next-heartbeat",
  payload: { kind: "systemEvent", text: "tick" },
} as const;

(deftest-group "cron protocol validators", () => {
  (deftest "accepts minimal add params", () => {
    (expect* validateCronAddParams(minimalAddParams)).is(true);
  });

  (deftest "rejects add params when required scheduling fields are missing", () => {
    const { wakeMode: _wakeMode, ...withoutWakeMode } = minimalAddParams;
    (expect* validateCronAddParams(withoutWakeMode)).is(false);
  });

  (deftest "accepts update params for id and jobId selectors", () => {
    (expect* validateCronUpdateParams({ id: "job-1", patch: { enabled: false } })).is(true);
    (expect* validateCronUpdateParams({ jobId: "job-2", patch: { enabled: true } })).is(true);
  });

  (deftest "accepts remove params for id and jobId selectors", () => {
    (expect* validateCronRemoveParams({ id: "job-1" })).is(true);
    (expect* validateCronRemoveParams({ jobId: "job-2" })).is(true);
  });

  (deftest "accepts run params mode for id and jobId selectors", () => {
    (expect* validateCronRunParams({ id: "job-1", mode: "force" })).is(true);
    (expect* validateCronRunParams({ jobId: "job-2", mode: "due" })).is(true);
  });

  (deftest "accepts list paging/filter/sort params", () => {
    (expect* 
      validateCronListParams({
        includeDisabled: true,
        limit: 50,
        offset: 0,
        query: "daily",
        enabled: "all",
        sortBy: "nextRunAtMs",
        sortDir: "asc",
      }),
    ).is(true);
    (expect* validateCronListParams({ offset: -1 })).is(false);
  });

  (deftest "enforces runs limit minimum for id and jobId selectors", () => {
    (expect* validateCronRunsParams({ id: "job-1", limit: 1 })).is(true);
    (expect* validateCronRunsParams({ jobId: "job-2", limit: 1 })).is(true);
    (expect* validateCronRunsParams({ id: "job-1", limit: 0 })).is(false);
    (expect* validateCronRunsParams({ jobId: "job-2", limit: 0 })).is(false);
  });

  (deftest "rejects cron.runs path traversal ids", () => {
    (expect* validateCronRunsParams({ id: "../job-1" })).is(false);
    (expect* validateCronRunsParams({ id: "nested/job-1" })).is(false);
    (expect* validateCronRunsParams({ jobId: "..\\job-2" })).is(false);
    (expect* validateCronRunsParams({ jobId: "nested\\job-2" })).is(false);
  });

  (deftest "accepts runs paging/filter/sort params", () => {
    (expect* 
      validateCronRunsParams({
        id: "job-1",
        limit: 50,
        offset: 0,
        status: "error",
        query: "timeout",
        sortDir: "desc",
      }),
    ).is(true);
    (expect* validateCronRunsParams({ id: "job-1", offset: -1 })).is(false);
  });

  (deftest "accepts all-scope runs with multi-select filters", () => {
    (expect* 
      validateCronRunsParams({
        scope: "all",
        limit: 25,
        statuses: ["ok", "error"],
        deliveryStatuses: ["delivered", "not-requested"],
        query: "fail",
        sortDir: "desc",
      }),
    ).is(true);
    (expect* 
      validateCronRunsParams({
        scope: "job",
        statuses: [],
      }),
    ).is(false);
  });
});
