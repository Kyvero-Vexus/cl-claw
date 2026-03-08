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
import { postJson } from "./post-json.js";
import { withRemoteHttpResponse } from "./remote-http.js";

mock:mock("./remote-http.js", () => ({
  withRemoteHttpResponse: mock:fn(),
}));

(deftest-group "postJson", () => {
  const remoteHttpMock = mock:mocked(withRemoteHttpResponse);

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "parses JSON payload on successful response", async () => {
    remoteHttpMock.mockImplementationOnce(async (params) => {
      return await params.onResponse(
        new Response(JSON.stringify({ data: [{ embedding: [1, 2] }] }), { status: 200 }),
      );
    });

    const result = await postJson({
      url: "https://memory.example/v1/post",
      headers: { Authorization: "Bearer test" },
      body: { input: ["x"] },
      errorPrefix: "post failed",
      parse: (payload) => payload,
    });

    (expect* result).is-equal({ data: [{ embedding: [1, 2] }] });
  });

  (deftest "attaches status to thrown error when requested", async () => {
    remoteHttpMock.mockImplementationOnce(async (params) => {
      return await params.onResponse(new Response("bad gateway", { status: 502 }));
    });

    await (expect* 
      postJson({
        url: "https://memory.example/v1/post",
        headers: {},
        body: {},
        errorPrefix: "post failed",
        attachStatus: true,
        parse: () => ({}),
      }),
    ).rejects.matches-object({
      message: expect.stringContaining("post failed: 502 bad gateway"),
      status: 502,
    });
  });
});
