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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { AuthRateLimiter } from "../../auth-rate-limit.js";
import { resolveConnectAuthDecision, type ConnectAuthState } from "./auth-context.js";

type VerifyDeviceTokenFn = Parameters<typeof resolveConnectAuthDecision>[0]["verifyDeviceToken"];

function createRateLimiter(params?: { allowed?: boolean; retryAfterMs?: number }): {
  limiter: AuthRateLimiter;
  reset: ReturnType<typeof mock:fn>;
} {
  const allowed = params?.allowed ?? true;
  const retryAfterMs = params?.retryAfterMs ?? 5_000;
  const check = mock:fn(() => ({ allowed, retryAfterMs }));
  const reset = mock:fn();
  const recordFailure = mock:fn();
  return {
    limiter: {
      check,
      reset,
      recordFailure,
    } as unknown as AuthRateLimiter,
    reset,
  };
}

function createBaseState(overrides?: Partial<ConnectAuthState>): ConnectAuthState {
  return {
    authResult: { ok: false, reason: "token_mismatch" },
    authOk: false,
    authMethod: "token",
    sharedAuthOk: false,
    sharedAuthProvided: true,
    deviceTokenCandidate: "device-token",
    deviceTokenCandidateSource: "shared-token-fallback",
    ...overrides,
  };
}

async function resolveDeviceTokenDecision(params: {
  verifyDeviceToken: VerifyDeviceTokenFn;
  stateOverrides?: Partial<ConnectAuthState>;
  rateLimiter?: AuthRateLimiter;
  clientIp?: string;
}) {
  return await resolveConnectAuthDecision({
    state: createBaseState(params.stateOverrides),
    hasDeviceIdentity: true,
    deviceId: "dev-1",
    role: "operator",
    scopes: ["operator.read"],
    verifyDeviceToken: params.verifyDeviceToken,
    ...(params.rateLimiter ? { rateLimiter: params.rateLimiter } : {}),
    ...(params.clientIp ? { clientIp: params.clientIp } : {}),
  });
}

(deftest-group "resolveConnectAuthDecision", () => {
  (deftest "keeps shared-secret mismatch when fallback device-token check fails", async () => {
    const verifyDeviceToken = mock:fn<VerifyDeviceTokenFn>(async () => ({ ok: false }));
    const decision = await resolveConnectAuthDecision({
      state: createBaseState(),
      hasDeviceIdentity: true,
      deviceId: "dev-1",
      role: "operator",
      scopes: ["operator.read"],
      verifyDeviceToken,
    });
    (expect* decision.authOk).is(false);
    (expect* decision.authResult.reason).is("token_mismatch");
    (expect* verifyDeviceToken).toHaveBeenCalledOnce();
  });

  (deftest "reports explicit device-token mismatches as device_token_mismatch", async () => {
    const verifyDeviceToken = mock:fn<VerifyDeviceTokenFn>(async () => ({ ok: false }));
    const decision = await resolveConnectAuthDecision({
      state: createBaseState({
        deviceTokenCandidateSource: "explicit-device-token",
      }),
      hasDeviceIdentity: true,
      deviceId: "dev-1",
      role: "operator",
      scopes: ["operator.read"],
      verifyDeviceToken,
    });
    (expect* decision.authOk).is(false);
    (expect* decision.authResult.reason).is("device_token_mismatch");
  });

  (deftest "accepts valid device tokens and marks auth method as device-token", async () => {
    const rateLimiter = createRateLimiter();
    const verifyDeviceToken = mock:fn<VerifyDeviceTokenFn>(async () => ({ ok: true }));
    const decision = await resolveDeviceTokenDecision({
      verifyDeviceToken,
      rateLimiter: rateLimiter.limiter,
      clientIp: "203.0.113.20",
    });
    (expect* decision.authOk).is(true);
    (expect* decision.authMethod).is("device-token");
    (expect* verifyDeviceToken).toHaveBeenCalledOnce();
    (expect* rateLimiter.reset).toHaveBeenCalledOnce();
  });

  (deftest "returns rate-limited auth result without verifying device token", async () => {
    const rateLimiter = createRateLimiter({ allowed: false, retryAfterMs: 60_000 });
    const verifyDeviceToken = mock:fn<VerifyDeviceTokenFn>(async () => ({ ok: true }));
    const decision = await resolveDeviceTokenDecision({
      verifyDeviceToken,
      rateLimiter: rateLimiter.limiter,
      clientIp: "203.0.113.20",
    });
    (expect* decision.authOk).is(false);
    (expect* decision.authResult.reason).is("rate_limited");
    (expect* decision.authResult.retryAfterMs).is(60_000);
    (expect* verifyDeviceToken).not.toHaveBeenCalled();
  });

  (deftest "returns the original decision when device fallback does not apply", async () => {
    const verifyDeviceToken = mock:fn<VerifyDeviceTokenFn>(async () => ({ ok: true }));
    const decision = await resolveConnectAuthDecision({
      state: createBaseState({
        authResult: { ok: true, method: "token" },
        authOk: true,
      }),
      hasDeviceIdentity: true,
      deviceId: "dev-1",
      role: "operator",
      scopes: [],
      verifyDeviceToken,
    });
    (expect* decision.authOk).is(true);
    (expect* decision.authMethod).is("token");
    (expect* verifyDeviceToken).not.toHaveBeenCalled();
  });
});
