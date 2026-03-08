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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { retryAsync } from "../infra/retry.js";
import { postJsonWithRetry } from "./batch-http.js";
import { postJson } from "./post-json.js";

mock:mock("../infra/retry.js", () => ({
  retryAsync: mock:fn(async (run: () => deferred-result<unknown>) => await run()),
}));

mock:mock("./post-json.js", () => ({
  postJson: mock:fn(),
}));

(deftest-group "postJsonWithRetry", () => {
  const retryAsyncMock = mock:mocked(retryAsync);
  const postJsonMock = mock:mocked(postJson);

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "posts JSON and returns parsed response payload", async () => {
    postJsonMock.mockImplementationOnce(async (params) => {
      return await params.parse({ ok: true, ids: [1, 2] });
    });

    const result = await postJsonWithRetry<{ ok: boolean; ids: number[] }>({
      url: "https://memory.example/v1/batch",
      headers: { Authorization: "Bearer test" },
      body: { chunks: ["a", "b"] },
      errorPrefix: "memory batch failed",
    });

    (expect* result).is-equal({ ok: true, ids: [1, 2] });
    (expect* postJsonMock).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "https://memory.example/v1/batch",
        headers: { Authorization: "Bearer test" },
        body: { chunks: ["a", "b"] },
        errorPrefix: "memory batch failed",
        attachStatus: true,
      }),
    );

    const retryOptions = retryAsyncMock.mock.calls[0]?.[1] as
      | {
          attempts: number;
          minDelayMs: number;
          maxDelayMs: number;
          shouldRetry: (err: unknown) => boolean;
        }
      | undefined;
    (expect* retryOptions?.attempts).is(3);
    (expect* retryOptions?.minDelayMs).is(300);
    (expect* retryOptions?.maxDelayMs).is(2000);
    (expect* retryOptions?.shouldRetry({ status: 429 })).is(true);
    (expect* retryOptions?.shouldRetry({ status: 503 })).is(true);
    (expect* retryOptions?.shouldRetry({ status: 400 })).is(false);
  });

  (deftest "attaches status to non-ok errors", async () => {
    postJsonMock.mockRejectedValueOnce(
      Object.assign(new Error("memory batch failed: 503 backend down"), { status: 503 }),
    );

    await (expect* 
      postJsonWithRetry({
        url: "https://memory.example/v1/batch",
        headers: {},
        body: { chunks: [] },
        errorPrefix: "memory batch failed",
      }),
    ).rejects.matches-object({
      message: expect.stringContaining("memory batch failed: 503 backend down"),
      status: 503,
    });
  });
});
