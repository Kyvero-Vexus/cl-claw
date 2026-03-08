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
  resolveBatchCompletionFromStatus,
  resolveCompletedBatchResult,
  throwIfBatchTerminalFailure,
} from "./batch-status.js";

(deftest-group "batch-status helpers", () => {
  (deftest "resolves completion payload from completed status", () => {
    (expect* 
      resolveBatchCompletionFromStatus({
        provider: "openai",
        batchId: "b1",
        status: {
          output_file_id: "out-1",
          error_file_id: "err-1",
        },
      }),
    ).is-equal({
      outputFileId: "out-1",
      errorFileId: "err-1",
    });
  });

  (deftest "throws for terminal failure states", async () => {
    await (expect* 
      throwIfBatchTerminalFailure({
        provider: "voyage",
        status: { id: "b2", status: "failed", error_file_id: "err-file" },
        readError: async () => "bad input",
      }),
    ).rejects.signals-error("voyage batch b2 failed: bad input");
  });

  (deftest "returns completed result directly without waiting", async () => {
    const waitForBatch = async () => ({ outputFileId: "out-2" });
    const result = await resolveCompletedBatchResult({
      provider: "openai",
      status: {
        id: "b3",
        status: "completed",
        output_file_id: "out-3",
      },
      wait: false,
      waitForBatch,
    });
    (expect* result).is-equal({ outputFileId: "out-3", errorFileId: undefined });
  });

  (deftest "throws when wait disabled and batch is not complete", async () => {
    await (expect* 
      resolveCompletedBatchResult({
        provider: "openai",
        status: { id: "b4", status: "pending" },
        wait: false,
        waitForBatch: async () => ({ outputFileId: "out" }),
      }),
    ).rejects.signals-error("openai batch b4 submitted; enable remote.batch.wait to await completion");
  });
});
