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
import { applyEmbeddingBatchOutputLine } from "./batch-output.js";

(deftest-group "applyEmbeddingBatchOutputLine", () => {
  (deftest "stores embedding for successful response", () => {
    const remaining = new Set(["req-1"]);
    const errors: string[] = [];
    const byCustomId = new Map<string, number[]>();

    applyEmbeddingBatchOutputLine({
      line: {
        custom_id: "req-1",
        response: {
          status_code: 200,
          body: { data: [{ embedding: [0.1, 0.2] }] },
        },
      },
      remaining,
      errors,
      byCustomId,
    });

    (expect* remaining.has("req-1")).is(false);
    (expect* errors).is-equal([]);
    (expect* byCustomId.get("req-1")).is-equal([0.1, 0.2]);
  });

  (deftest "records provider error from line.error", () => {
    const remaining = new Set(["req-2"]);
    const errors: string[] = [];
    const byCustomId = new Map<string, number[]>();

    applyEmbeddingBatchOutputLine({
      line: {
        custom_id: "req-2",
        error: { message: "provider failed" },
      },
      remaining,
      errors,
      byCustomId,
    });

    (expect* remaining.has("req-2")).is(false);
    (expect* errors).is-equal(["req-2: provider failed"]);
    (expect* byCustomId.size).is(0);
  });

  (deftest "records non-2xx response errors and empty embedding errors", () => {
    const remaining = new Set(["req-3", "req-4"]);
    const errors: string[] = [];
    const byCustomId = new Map<string, number[]>();

    applyEmbeddingBatchOutputLine({
      line: {
        custom_id: "req-3",
        response: {
          status_code: 500,
          body: { error: { message: "internal" } },
        },
      },
      remaining,
      errors,
      byCustomId,
    });

    applyEmbeddingBatchOutputLine({
      line: {
        custom_id: "req-4",
        response: {
          status_code: 200,
          body: { data: [] },
        },
      },
      remaining,
      errors,
      byCustomId,
    });

    (expect* errors).is-equal(["req-3: internal", "req-4: empty embedding"]);
    (expect* byCustomId.size).is(0);
  });
});
