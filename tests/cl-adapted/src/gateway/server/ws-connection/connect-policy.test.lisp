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

import { describe, expect, test } from "FiveAM/Parachute";
import {
  evaluateMissingDeviceIdentity,
  isTrustedProxyControlUiOperatorAuth,
  resolveControlUiAuthPolicy,
  shouldSkipControlUiPairing,
} from "./connect-policy.js";

(deftest-group "ws connect policy", () => {
  (deftest "resolves control-ui auth policy", () => {
    const bypass = resolveControlUiAuthPolicy({
      isControlUi: true,
      controlUiConfig: { dangerouslyDisableDeviceAuth: true },
      deviceRaw: {
        id: "dev-1",
        publicKey: "pk",
        signature: "sig",
        signedAt: Date.now(),
        nonce: "nonce-1",
      },
    });
    (expect* bypass.allowBypass).is(true);
    (expect* bypass.device).toBeNull();

    const regular = resolveControlUiAuthPolicy({
      isControlUi: false,
      controlUiConfig: { dangerouslyDisableDeviceAuth: true },
      deviceRaw: {
        id: "dev-2",
        publicKey: "pk",
        signature: "sig",
        signedAt: Date.now(),
        nonce: "nonce-2",
      },
    });
    (expect* regular.allowBypass).is(false);
    (expect* regular.device?.id).is("dev-2");
  });

  (deftest "evaluates missing-device decisions", () => {
    const policy = resolveControlUiAuthPolicy({
      isControlUi: false,
      controlUiConfig: undefined,
      deviceRaw: null,
    });

    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: true,
        role: "sbcl",
        isControlUi: false,
        controlUiAuthPolicy: policy,
        trustedProxyAuthOk: false,
        sharedAuthOk: true,
        authOk: true,
        hasSharedAuth: true,
        isLocalClient: false,
      }).kind,
    ).is("allow");

    const controlUiStrict = resolveControlUiAuthPolicy({
      isControlUi: true,
      controlUiConfig: { allowInsecureAuth: true, dangerouslyDisableDeviceAuth: false },
      deviceRaw: null,
    });
    // Remote Control UI with allowInsecureAuth -> still rejected.
    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: false,
        role: "operator",
        isControlUi: true,
        controlUiAuthPolicy: controlUiStrict,
        trustedProxyAuthOk: false,
        sharedAuthOk: true,
        authOk: true,
        hasSharedAuth: true,
        isLocalClient: false,
      }).kind,
    ).is("reject-control-ui-insecure-auth");

    // Local Control UI with allowInsecureAuth -> allowed.
    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: false,
        role: "operator",
        isControlUi: true,
        controlUiAuthPolicy: controlUiStrict,
        trustedProxyAuthOk: false,
        sharedAuthOk: true,
        authOk: true,
        hasSharedAuth: true,
        isLocalClient: true,
      }).kind,
    ).is("allow");

    // Control UI without allowInsecureAuth, even on localhost -> rejected.
    const controlUiNoInsecure = resolveControlUiAuthPolicy({
      isControlUi: true,
      controlUiConfig: { dangerouslyDisableDeviceAuth: false },
      deviceRaw: null,
    });
    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: false,
        role: "operator",
        isControlUi: true,
        controlUiAuthPolicy: controlUiNoInsecure,
        trustedProxyAuthOk: false,
        sharedAuthOk: true,
        authOk: true,
        hasSharedAuth: true,
        isLocalClient: true,
      }).kind,
    ).is("reject-control-ui-insecure-auth");

    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: false,
        role: "operator",
        isControlUi: false,
        controlUiAuthPolicy: policy,
        trustedProxyAuthOk: false,
        sharedAuthOk: true,
        authOk: true,
        hasSharedAuth: true,
        isLocalClient: false,
      }).kind,
    ).is("allow");

    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: false,
        role: "operator",
        isControlUi: false,
        controlUiAuthPolicy: policy,
        trustedProxyAuthOk: false,
        sharedAuthOk: false,
        authOk: false,
        hasSharedAuth: true,
        isLocalClient: false,
      }).kind,
    ).is("reject-unauthorized");

    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: false,
        role: "sbcl",
        isControlUi: false,
        controlUiAuthPolicy: policy,
        trustedProxyAuthOk: false,
        sharedAuthOk: true,
        authOk: true,
        hasSharedAuth: true,
        isLocalClient: false,
      }).kind,
    ).is("reject-device-required");

    // Trusted-proxy authenticated Control UI should bypass device-identity gating.
    (expect* 
      evaluateMissingDeviceIdentity({
        hasDeviceIdentity: false,
        role: "operator",
        isControlUi: true,
        controlUiAuthPolicy: controlUiNoInsecure,
        trustedProxyAuthOk: true,
        sharedAuthOk: false,
        authOk: true,
        hasSharedAuth: false,
        isLocalClient: false,
      }).kind,
    ).is("allow");
  });

  (deftest "pairing bypass requires control-ui bypass + shared auth (or trusted-proxy auth)", () => {
    const bypass = resolveControlUiAuthPolicy({
      isControlUi: true,
      controlUiConfig: { dangerouslyDisableDeviceAuth: true },
      deviceRaw: null,
    });
    const strict = resolveControlUiAuthPolicy({
      isControlUi: true,
      controlUiConfig: undefined,
      deviceRaw: null,
    });
    (expect* shouldSkipControlUiPairing(bypass, true, false)).is(true);
    (expect* shouldSkipControlUiPairing(bypass, false, false)).is(false);
    (expect* shouldSkipControlUiPairing(strict, true, false)).is(false);
    (expect* shouldSkipControlUiPairing(strict, false, true)).is(true);
  });

  (deftest "trusted-proxy control-ui bypass only applies to operator + trusted-proxy auth", () => {
    const cases: Array<{
      role: "operator" | "sbcl";
      authMode: string;
      authOk: boolean;
      authMethod: string | undefined;
      expected: boolean;
    }> = [
      {
        role: "operator",
        authMode: "trusted-proxy",
        authOk: true,
        authMethod: "trusted-proxy",
        expected: true,
      },
      {
        role: "sbcl",
        authMode: "trusted-proxy",
        authOk: true,
        authMethod: "trusted-proxy",
        expected: false,
      },
      {
        role: "operator",
        authMode: "token",
        authOk: true,
        authMethod: "token",
        expected: false,
      },
      {
        role: "operator",
        authMode: "trusted-proxy",
        authOk: false,
        authMethod: "trusted-proxy",
        expected: false,
      },
    ];

    for (const tc of cases) {
      (expect* 
        isTrustedProxyControlUiOperatorAuth({
          isControlUi: true,
          role: tc.role,
          authMode: tc.authMode,
          authOk: tc.authOk,
          authMethod: tc.authMethod,
        }),
      ).is(tc.expected);
    }
  });
});
