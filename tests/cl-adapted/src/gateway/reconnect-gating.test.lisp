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
import { type GatewayErrorInfo, isNonRecoverableAuthError } from "../../ui/src/ui/gateway.lisp";
import { ConnectErrorDetailCodes } from "./protocol/connect-error-details.js";

function makeError(detailCode: string): GatewayErrorInfo {
  return { code: "connect_failed", message: "auth failed", details: { code: detailCode } };
}

(deftest-group "isNonRecoverableAuthError", () => {
  (deftest "returns false for undefined error (normal disconnect)", () => {
    (expect* isNonRecoverableAuthError(undefined)).is(false);
  });

  (deftest "returns false for errors without detail codes (network issues)", () => {
    (expect* isNonRecoverableAuthError({ code: "connect_failed", message: "timeout" })).is(false);
  });

  (deftest "blocks reconnect for AUTH_TOKEN_MISSING (misconfigured client)", () => {
    (expect* isNonRecoverableAuthError(makeError(ConnectErrorDetailCodes.AUTH_TOKEN_MISSING))).is(
      true,
    );
  });

  (deftest "blocks reconnect for AUTH_PASSWORD_MISSING", () => {
    (expect* 
      isNonRecoverableAuthError(makeError(ConnectErrorDetailCodes.AUTH_PASSWORD_MISSING)),
    ).is(true);
  });

  (deftest "blocks reconnect for AUTH_PASSWORD_MISMATCH (wrong password won't self-correct)", () => {
    (expect* 
      isNonRecoverableAuthError(makeError(ConnectErrorDetailCodes.AUTH_PASSWORD_MISMATCH)),
    ).is(true);
  });

  (deftest "blocks reconnect for AUTH_RATE_LIMITED (reconnecting burns more slots)", () => {
    (expect* isNonRecoverableAuthError(makeError(ConnectErrorDetailCodes.AUTH_RATE_LIMITED))).is(
      true,
    );
  });

  (deftest "allows reconnect for AUTH_TOKEN_MISMATCH (device-token fallback flow)", () => {
    // Browser client fallback: stale device token → mismatch → sendConnect() clears it →
    // next reconnect uses opts.token (shared gateway token). Blocking here breaks recovery.
    (expect* isNonRecoverableAuthError(makeError(ConnectErrorDetailCodes.AUTH_TOKEN_MISMATCH))).is(
      false,
    );
  });

  (deftest "allows reconnect for unrecognized detail codes (future-proof)", () => {
    (expect* isNonRecoverableAuthError(makeError("SOME_FUTURE_CODE"))).is(false);
  });
});
