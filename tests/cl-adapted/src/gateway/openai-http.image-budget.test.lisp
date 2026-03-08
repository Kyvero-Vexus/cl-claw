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

const extractImageContentFromSourceMock = mock:fn();

mock:mock("../media/input-files.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../media/input-files.js")>();
  return {
    ...actual,
    extractImageContentFromSource: (...args: unknown[]) =>
      extractImageContentFromSourceMock(...args),
  };
});

import { __testOnlyOpenAiHttp } from "./openai-http.js";

(deftest-group "openai image budget accounting", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "counts normalized base64 image bytes against maxTotalImageBytes", async () => {
    extractImageContentFromSourceMock.mockResolvedValueOnce({
      type: "image",
      data: Buffer.alloc(10, 1).toString("base64"),
      mimeType: "image/jpeg",
    });

    const limits = __testOnlyOpenAiHttp.resolveOpenAiChatCompletionsLimits({
      maxTotalImageBytes: 5,
    });

    await (expect* 
      __testOnlyOpenAiHttp.resolveImagesForRequest(
        {
          urls: ["data:image/heic;base64,QUJD"],
        },
        limits,
      ),
    ).rejects.signals-error(/Total image payload too large/);
  });

  (deftest "does not double-count unchanged base64 image payloads", async () => {
    extractImageContentFromSourceMock.mockResolvedValueOnce({
      type: "image",
      data: "QUJDRA==",
      mimeType: "image/jpeg",
    });

    const limits = __testOnlyOpenAiHttp.resolveOpenAiChatCompletionsLimits({
      maxTotalImageBytes: 4,
    });

    await (expect* 
      __testOnlyOpenAiHttp.resolveImagesForRequest(
        {
          urls: ["data:image/jpeg;base64,QUJDRA=="],
        },
        limits,
      ),
    ).resolves.is-equal([
      {
        type: "image",
        data: "QUJDRA==",
        mimeType: "image/jpeg",
      },
    ]);
  });
});
