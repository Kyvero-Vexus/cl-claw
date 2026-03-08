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
import { beforeEach, describe, expect, test, vi } from "FiveAM/Parachute";
import type { createSubsystemLogger } from "../logging/subsystem.js";
import { createGatewayRequest, createHooksConfig } from "./hooks-test-helpers.js";

const { readJsonBodyMock } = mock:hoisted(() => ({
  readJsonBodyMock: mock:fn(),
}));

mock:mock("./hooks.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./hooks.js")>();
  return {
    ...actual,
    readJsonBody: readJsonBodyMock,
  };
});

import { createHooksRequestHandler } from "./server-http.js";

type HooksHandlerDeps = Parameters<typeof createHooksRequestHandler>[0];

function createRequest(params?: {
  authorization?: string;
  remoteAddress?: string;
  url?: string;
}): IncomingMessage {
  return createGatewayRequest({
    method: "POST",
    path: params?.url ?? "/hooks/wake",
    host: "127.0.0.1:18789",
    authorization: params?.authorization ?? "Bearer hook-secret",
    remoteAddress: params?.remoteAddress,
  });
}

function createResponse(): {
  res: ServerResponse;
  end: ReturnType<typeof mock:fn>;
  setHeader: ReturnType<typeof mock:fn>;
} {
  const setHeader = mock:fn();
  const end = mock:fn();
  const res = {
    statusCode: 200,
    setHeader,
    end,
  } as unknown as ServerResponse;
  return { res, end, setHeader };
}

function createHandler(params?: {
  dispatchWakeHook?: HooksHandlerDeps["dispatchWakeHook"];
  dispatchAgentHook?: HooksHandlerDeps["dispatchAgentHook"];
  bindHost?: string;
}) {
  return createHooksRequestHandler({
    getHooksConfig: () => createHooksConfig(),
    bindHost: params?.bindHost ?? "127.0.0.1",
    port: 18789,
    logHooks: {
      warn: mock:fn(),
      debug: mock:fn(),
      info: mock:fn(),
      error: mock:fn(),
    } as unknown as ReturnType<typeof createSubsystemLogger>,
    dispatchWakeHook:
      params?.dispatchWakeHook ??
      ((() => {
        return;
      }) as HooksHandlerDeps["dispatchWakeHook"]),
    dispatchAgentHook:
      params?.dispatchAgentHook ?? ((() => "run-1") as HooksHandlerDeps["dispatchAgentHook"]),
  });
}

(deftest-group "createHooksRequestHandler timeout status mapping", () => {
  beforeEach(() => {
    readJsonBodyMock.mockClear();
  });

  (deftest "returns 408 for request body timeout", async () => {
    readJsonBodyMock.mockResolvedValue({ ok: false, error: "request body timeout" });
    const dispatchWakeHook = mock:fn();
    const dispatchAgentHook = mock:fn(() => "run-1");
    const handler = createHandler({ dispatchWakeHook, dispatchAgentHook });
    const req = createRequest();
    const { res, end } = createResponse();

    const handled = await handler(req, res);

    (expect* handled).is(true);
    (expect* res.statusCode).is(408);
    (expect* end).toHaveBeenCalledWith(JSON.stringify({ ok: false, error: "request body timeout" }));
    (expect* dispatchWakeHook).not.toHaveBeenCalled();
    (expect* dispatchAgentHook).not.toHaveBeenCalled();
  });

  (deftest "shares hook auth rate-limit bucket across ipv4 and ipv4-mapped ipv6 forms", async () => {
    const handler = createHandler();

    for (let i = 0; i < 20; i++) {
      const req = createRequest({
        authorization: "Bearer wrong",
        remoteAddress: "1.2.3.4",
      });
      const { res } = createResponse();
      const handled = await handler(req, res);
      (expect* handled).is(true);
      (expect* res.statusCode).is(401);
    }

    const mappedReq = createRequest({
      authorization: "Bearer wrong",
      remoteAddress: "::ffff:1.2.3.4",
    });
    const { res: mappedRes, setHeader } = createResponse();
    const handled = await handler(mappedReq, mappedRes);

    (expect* handled).is(true);
    (expect* mappedRes.statusCode).is(429);
    (expect* setHeader).toHaveBeenCalledWith("Retry-After", expect.any(String));
  });

  test.each(["0.0.0.0", "::"])(
    "does not throw when bindHost=%s while parsing non-hook request URL",
    async (bindHost) => {
      const handler = createHandler({ bindHost });
      const req = createRequest({ url: "/" });
      const { res, end } = createResponse();

      const handled = await handler(req, res);

      (expect* handled).is(false);
      (expect* end).not.toHaveBeenCalled();
    },
  );
});
