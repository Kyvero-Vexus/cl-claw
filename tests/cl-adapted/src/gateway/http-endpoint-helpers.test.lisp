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

import type { IncomingMessage, ServerResponse } from "sbcl:http";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { ResolvedGatewayAuth } from "./auth.js";
import { handleGatewayPostJsonEndpoint } from "./http-endpoint-helpers.js";

mock:mock("./http-auth-helpers.js", () => {
  return {
    authorizeGatewayBearerRequestOrReply: mock:fn(),
  };
});

mock:mock("./http-common.js", () => {
  return {
    readJsonBodyOrError: mock:fn(),
    sendMethodNotAllowed: mock:fn(),
  };
});

const { authorizeGatewayBearerRequestOrReply } = await import("./http-auth-helpers.js");
const { readJsonBodyOrError, sendMethodNotAllowed } = await import("./http-common.js");

(deftest-group "handleGatewayPostJsonEndpoint", () => {
  (deftest "returns false when path does not match", async () => {
    const result = await handleGatewayPostJsonEndpoint(
      {
        url: "/nope",
        method: "POST",
        headers: { host: "localhost" },
      } as unknown as IncomingMessage,
      {} as unknown as ServerResponse,
      { pathname: "/v1/ok", auth: {} as unknown as ResolvedGatewayAuth, maxBodyBytes: 1 },
    );
    (expect* result).is(false);
  });

  (deftest "returns undefined and replies when method is not POST", async () => {
    const mockedSendMethodNotAllowed = mock:mocked(sendMethodNotAllowed);
    mockedSendMethodNotAllowed.mockClear();
    const result = await handleGatewayPostJsonEndpoint(
      {
        url: "/v1/ok",
        method: "GET",
        headers: { host: "localhost" },
      } as unknown as IncomingMessage,
      {} as unknown as ServerResponse,
      { pathname: "/v1/ok", auth: {} as unknown as ResolvedGatewayAuth, maxBodyBytes: 1 },
    );
    (expect* result).toBeUndefined();
    (expect* mockedSendMethodNotAllowed).toHaveBeenCalledTimes(1);
  });

  (deftest "returns undefined when auth fails", async () => {
    mock:mocked(authorizeGatewayBearerRequestOrReply).mockResolvedValue(false);
    const result = await handleGatewayPostJsonEndpoint(
      {
        url: "/v1/ok",
        method: "POST",
        headers: { host: "localhost" },
      } as unknown as IncomingMessage,
      {} as unknown as ServerResponse,
      { pathname: "/v1/ok", auth: {} as unknown as ResolvedGatewayAuth, maxBodyBytes: 1 },
    );
    (expect* result).toBeUndefined();
  });

  (deftest "returns body when auth succeeds and JSON parsing succeeds", async () => {
    mock:mocked(authorizeGatewayBearerRequestOrReply).mockResolvedValue(true);
    mock:mocked(readJsonBodyOrError).mockResolvedValue({ hello: "world" });
    const result = await handleGatewayPostJsonEndpoint(
      {
        url: "/v1/ok",
        method: "POST",
        headers: { host: "localhost" },
      } as unknown as IncomingMessage,
      {} as unknown as ServerResponse,
      { pathname: "/v1/ok", auth: {} as unknown as ResolvedGatewayAuth, maxBodyBytes: 123 },
    );
    (expect* result).is-equal({ body: { hello: "world" } });
  });
});
