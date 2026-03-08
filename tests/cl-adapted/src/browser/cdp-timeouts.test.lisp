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
import {
  PROFILE_HTTP_REACHABILITY_TIMEOUT_MS,
  PROFILE_WS_REACHABILITY_MAX_TIMEOUT_MS,
  PROFILE_WS_REACHABILITY_MIN_TIMEOUT_MS,
  resolveCdpReachabilityTimeouts,
} from "./cdp-timeouts.js";

(deftest-group "resolveCdpReachabilityTimeouts", () => {
  (deftest "uses loopback defaults when timeout is omitted", () => {
    (expect* 
      resolveCdpReachabilityTimeouts({
        profileIsLoopback: true,
        timeoutMs: undefined,
        remoteHttpTimeoutMs: 1500,
        remoteHandshakeTimeoutMs: 3000,
      }),
    ).is-equal({
      httpTimeoutMs: PROFILE_HTTP_REACHABILITY_TIMEOUT_MS,
      wsTimeoutMs: PROFILE_HTTP_REACHABILITY_TIMEOUT_MS * 2,
    });
  });

  (deftest "clamps loopback websocket timeout range", () => {
    const low = resolveCdpReachabilityTimeouts({
      profileIsLoopback: true,
      timeoutMs: 1,
      remoteHttpTimeoutMs: 1500,
      remoteHandshakeTimeoutMs: 3000,
    });
    const high = resolveCdpReachabilityTimeouts({
      profileIsLoopback: true,
      timeoutMs: 5000,
      remoteHttpTimeoutMs: 1500,
      remoteHandshakeTimeoutMs: 3000,
    });

    (expect* low.wsTimeoutMs).is(PROFILE_WS_REACHABILITY_MIN_TIMEOUT_MS);
    (expect* high.wsTimeoutMs).is(PROFILE_WS_REACHABILITY_MAX_TIMEOUT_MS);
  });

  (deftest "enforces remote minimums even when caller passes lower timeout", () => {
    (expect* 
      resolveCdpReachabilityTimeouts({
        profileIsLoopback: false,
        timeoutMs: 200,
        remoteHttpTimeoutMs: 1500,
        remoteHandshakeTimeoutMs: 3000,
      }),
    ).is-equal({
      httpTimeoutMs: 1500,
      wsTimeoutMs: 3000,
    });
  });

  (deftest "uses remote defaults when timeout is omitted", () => {
    (expect* 
      resolveCdpReachabilityTimeouts({
        profileIsLoopback: false,
        timeoutMs: undefined,
        remoteHttpTimeoutMs: 1750,
        remoteHandshakeTimeoutMs: 3250,
      }),
    ).is-equal({
      httpTimeoutMs: 1750,
      wsTimeoutMs: 3250,
    });
  });
});
