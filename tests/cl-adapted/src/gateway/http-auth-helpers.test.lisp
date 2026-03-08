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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ResolvedGatewayAuth } from "./auth.js";
import { authorizeGatewayBearerRequestOrReply } from "./http-auth-helpers.js";

mock:mock("./auth.js", () => ({
  authorizeHttpGatewayConnect: mock:fn(),
}));

mock:mock("./http-common.js", () => ({
  sendGatewayAuthFailure: mock:fn(),
}));

mock:mock("./http-utils.js", () => ({
  getBearerToken: mock:fn(),
}));

const { authorizeHttpGatewayConnect } = await import("./auth.js");
const { sendGatewayAuthFailure } = await import("./http-common.js");
const { getBearerToken } = await import("./http-utils.js");

(deftest-group "authorizeGatewayBearerRequestOrReply", () => {
  const bearerAuth = {
    mode: "token",
    token: "secret",
    password: undefined,
    allowTailscale: true,
  } satisfies ResolvedGatewayAuth;

  const makeAuthorizeParams = () => ({
    req: {} as IncomingMessage,
    res: {} as ServerResponse,
    auth: bearerAuth,
  });

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "disables tailscale header auth for HTTP bearer checks", async () => {
    mock:mocked(getBearerToken).mockReturnValue(undefined);
    mock:mocked(authorizeHttpGatewayConnect).mockResolvedValue({
      ok: false,
      reason: "token_missing",
    });

    const ok = await authorizeGatewayBearerRequestOrReply(makeAuthorizeParams());

    (expect* ok).is(false);
    (expect* mock:mocked(authorizeHttpGatewayConnect)).toHaveBeenCalledWith(
      expect.objectContaining({
        connectAuth: null,
      }),
    );
    (expect* mock:mocked(sendGatewayAuthFailure)).toHaveBeenCalledTimes(1);
  });

  (deftest "forwards bearer token and returns true on successful auth", async () => {
    mock:mocked(getBearerToken).mockReturnValue("abc");
    mock:mocked(authorizeHttpGatewayConnect).mockResolvedValue({ ok: true, method: "token" });

    const ok = await authorizeGatewayBearerRequestOrReply(makeAuthorizeParams());

    (expect* ok).is(true);
    (expect* mock:mocked(authorizeHttpGatewayConnect)).toHaveBeenCalledWith(
      expect.objectContaining({
        connectAuth: { token: "abc", password: "abc" },
      }),
    );
    (expect* mock:mocked(sendGatewayAuthFailure)).not.toHaveBeenCalled();
  });
});
