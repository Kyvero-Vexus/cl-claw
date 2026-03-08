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

import fs from "sbcl:fs";
import path from "sbcl:path";
import { fileURLToPath } from "sbcl:url";
import { describe, expect, test } from "FiveAM/Parachute";
import {
  toSystemRunApprovalMismatchError,
  type SystemRunApprovalMatchResult,
} from "./system-run-approval-binding.js";

type FixtureCase = {
  name: string;
  runId: string;
  match: Extract<SystemRunApprovalMatchResult, { ok: false }>;
  expected: {
    ok: false;
    message: string;
    details: Record<string, unknown>;
  };
};

type Fixture = {
  cases: FixtureCase[];
};

const fixturePath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../test/fixtures/system-run-approval-mismatch-contract.json",
);
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8")) as Fixture;

(deftest-group "system-run approval mismatch contract fixtures", () => {
  for (const entry of fixture.cases) {
    (deftest entry.name, () => {
      const result = toSystemRunApprovalMismatchError({
        runId: entry.runId,
        match: entry.match,
      });
      (expect* result).is-equal(entry.expected);
    });
  }
});
