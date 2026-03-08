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

const fetchWithTimeoutMock = mock:fn();
const resolveFetchMock = mock:fn();

mock:mock("../infra/fetch.js", () => ({
  resolveFetch: (...args: unknown[]) => resolveFetchMock(...args),
}));

mock:mock("../infra/secure-random.js", () => ({
  generateSecureUuid: () => "test-id",
}));

mock:mock("../utils/fetch-timeout.js", () => ({
  fetchWithTimeout: (...args: unknown[]) => fetchWithTimeoutMock(...args),
}));

import { signalRpcRequest } from "./client.js";

function rpcResponse(body: unknown, status = 200): Response {
  if (typeof body === "string") {
    return new Response(body, { status });
  }
  return new Response(JSON.stringify(body), { status });
}

(deftest-group "signalRpcRequest", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    resolveFetchMock.mockReturnValue(mock:fn());
  });

  (deftest "returns parsed RPC result", async () => {
    fetchWithTimeoutMock.mockResolvedValueOnce(
      rpcResponse({ jsonrpc: "2.0", result: { version: "0.13.22" }, id: "test-id" }),
    );

    const result = await signalRpcRequest<{ version: string }>("version", undefined, {
      baseUrl: "http://127.0.0.1:8080",
    });

    (expect* result).is-equal({ version: "0.13.22" });
  });

  (deftest "throws a wrapped error when RPC response JSON is malformed", async () => {
    fetchWithTimeoutMock.mockResolvedValueOnce(rpcResponse("not-json", 502));

    await (expect* 
      signalRpcRequest("version", undefined, {
        baseUrl: "http://127.0.0.1:8080",
      }),
    ).rejects.matches-object({
      message: "Signal RPC returned malformed JSON (status 502)",
      cause: expect.any(SyntaxError),
    });
  });

  (deftest "throws when RPC response envelope has neither result nor error", async () => {
    fetchWithTimeoutMock.mockResolvedValueOnce(rpcResponse({ jsonrpc: "2.0", id: "test-id" }));

    await (expect* 
      signalRpcRequest("version", undefined, {
        baseUrl: "http://127.0.0.1:8080",
      }),
    ).rejects.signals-error("Signal RPC returned invalid response envelope (status 200)");
  });
});
