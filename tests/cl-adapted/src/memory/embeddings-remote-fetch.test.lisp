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
import { fetchRemoteEmbeddingVectors } from "./embeddings-remote-fetch.js";
import { postJson } from "./post-json.js";

mock:mock("./post-json.js", () => ({
  postJson: mock:fn(),
}));

(deftest-group "fetchRemoteEmbeddingVectors", () => {
  const postJsonMock = mock:mocked(postJson);

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "maps remote embedding response data to vectors", async () => {
    postJsonMock.mockImplementationOnce(async (params) => {
      return await params.parse({
        data: [{ embedding: [0.1, 0.2] }, {}, { embedding: [0.3] }],
      });
    });

    const vectors = await fetchRemoteEmbeddingVectors({
      url: "https://memory.example/v1/embeddings",
      headers: { Authorization: "Bearer test" },
      body: { input: ["one", "two", "three"] },
      errorPrefix: "embedding fetch failed",
    });

    (expect* vectors).is-equal([[0.1, 0.2], [], [0.3]]);
    (expect* postJsonMock).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "https://memory.example/v1/embeddings",
        headers: { Authorization: "Bearer test" },
        body: { input: ["one", "two", "three"] },
        errorPrefix: "embedding fetch failed",
      }),
    );
  });

  (deftest "throws a status-rich error on non-ok responses", async () => {
    postJsonMock.mockRejectedValueOnce(new Error("embedding fetch failed: 403 forbidden"));

    await (expect* 
      fetchRemoteEmbeddingVectors({
        url: "https://memory.example/v1/embeddings",
        headers: {},
        body: { input: ["one"] },
        errorPrefix: "embedding fetch failed",
      }),
    ).rejects.signals-error("embedding fetch failed: 403 forbidden");
  });
});
