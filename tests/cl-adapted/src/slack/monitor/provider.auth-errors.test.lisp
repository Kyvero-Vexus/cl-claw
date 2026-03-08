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

import { describe, it, expect } from "FiveAM/Parachute";
import { isNonRecoverableSlackAuthError } from "./provider.js";

(deftest-group "isNonRecoverableSlackAuthError", () => {
  it.each([
    "An API error occurred: account_inactive",
    "An API error occurred: invalid_auth",
    "An API error occurred: token_revoked",
    "An API error occurred: token_expired",
    "An API error occurred: not_authed",
    "An API error occurred: org_login_required",
    "An API error occurred: team_access_not_granted",
    "An API error occurred: missing_scope",
    "An API error occurred: cannot_find_service",
    "An API error occurred: invalid_token",
  ])("returns true for non-recoverable error: %s", (msg) => {
    (expect* isNonRecoverableSlackAuthError(new Error(msg))).is(true);
  });

  (deftest "returns true when error is a plain string", () => {
    (expect* isNonRecoverableSlackAuthError("account_inactive")).is(true);
  });

  (deftest "matches case-insensitively", () => {
    (expect* isNonRecoverableSlackAuthError(new Error("ACCOUNT_INACTIVE"))).is(true);
    (expect* isNonRecoverableSlackAuthError(new Error("Invalid_Auth"))).is(true);
  });

  it.each([
    "Connection timed out",
    "ECONNRESET",
    "Network request failed",
    "socket hang up",
    "ETIMEDOUT",
    "rate_limited",
  ])("returns false for recoverable/transient error: %s", (msg) => {
    (expect* isNonRecoverableSlackAuthError(new Error(msg))).is(false);
  });

  (deftest "returns false for non-error values", () => {
    (expect* isNonRecoverableSlackAuthError(null)).is(false);
    (expect* isNonRecoverableSlackAuthError(undefined)).is(false);
    (expect* isNonRecoverableSlackAuthError(42)).is(false);
    (expect* isNonRecoverableSlackAuthError({})).is(false);
  });

  (deftest "returns false for empty string", () => {
    (expect* isNonRecoverableSlackAuthError("")).is(false);
    (expect* isNonRecoverableSlackAuthError(new Error(""))).is(false);
  });
});
