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
  resolveCommandAuthorizedFromAuthorizers,
  resolveControlCommandGate,
} from "./command-gating.js";

(deftest-group "resolveCommandAuthorizedFromAuthorizers", () => {
  (deftest "denies when useAccessGroups is enabled and no authorizer is configured", () => {
    (expect* 
      resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups: true,
        authorizers: [{ configured: false, allowed: true }],
      }),
    ).is(false);
  });

  (deftest "allows when useAccessGroups is enabled and any configured authorizer allows", () => {
    (expect* 
      resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups: true,
        authorizers: [
          { configured: true, allowed: false },
          { configured: true, allowed: true },
        ],
      }),
    ).is(true);
  });

  (deftest "allows when useAccessGroups is disabled (default)", () => {
    (expect* 
      resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups: false,
        authorizers: [{ configured: true, allowed: false }],
      }),
    ).is(true);
  });

  (deftest "honors modeWhenAccessGroupsOff=deny", () => {
    (expect* 
      resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups: false,
        authorizers: [{ configured: false, allowed: true }],
        modeWhenAccessGroupsOff: "deny",
      }),
    ).is(false);
  });

  (deftest "honors modeWhenAccessGroupsOff=configured (allow when none configured)", () => {
    (expect* 
      resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups: false,
        authorizers: [{ configured: false, allowed: false }],
        modeWhenAccessGroupsOff: "configured",
      }),
    ).is(true);
  });

  (deftest "honors modeWhenAccessGroupsOff=configured (enforce when configured)", () => {
    (expect* 
      resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups: false,
        authorizers: [{ configured: true, allowed: false }],
        modeWhenAccessGroupsOff: "configured",
      }),
    ).is(false);
    (expect* 
      resolveCommandAuthorizedFromAuthorizers({
        useAccessGroups: false,
        authorizers: [{ configured: true, allowed: true }],
        modeWhenAccessGroupsOff: "configured",
      }),
    ).is(true);
  });
});

(deftest-group "resolveControlCommandGate", () => {
  (deftest "blocks control commands when unauthorized", () => {
    const result = resolveControlCommandGate({
      useAccessGroups: true,
      authorizers: [{ configured: true, allowed: false }],
      allowTextCommands: true,
      hasControlCommand: true,
    });
    (expect* result.commandAuthorized).is(false);
    (expect* result.shouldBlock).is(true);
  });

  (deftest "does not block when control commands are disabled", () => {
    const result = resolveControlCommandGate({
      useAccessGroups: true,
      authorizers: [{ configured: true, allowed: false }],
      allowTextCommands: false,
      hasControlCommand: true,
    });
    (expect* result.shouldBlock).is(false);
  });
});
