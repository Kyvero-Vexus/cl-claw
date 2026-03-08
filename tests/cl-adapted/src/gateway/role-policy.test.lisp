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
  isRoleAuthorizedForMethod,
  parseGatewayRole,
  roleCanSkipDeviceIdentity,
} from "./role-policy.js";

(deftest-group "gateway role policy", () => {
  (deftest "parses supported roles", () => {
    (expect* parseGatewayRole("operator")).is("operator");
    (expect* parseGatewayRole("sbcl")).is("sbcl");
    (expect* parseGatewayRole("admin")).toBeNull();
    (expect* parseGatewayRole(undefined)).toBeNull();
  });

  (deftest "allows device-less bypass only for operator + shared auth", () => {
    (expect* roleCanSkipDeviceIdentity("operator", true)).is(true);
    (expect* roleCanSkipDeviceIdentity("operator", false)).is(false);
    (expect* roleCanSkipDeviceIdentity("sbcl", true)).is(false);
  });

  (deftest "authorizes roles against sbcl vs operator methods", () => {
    (expect* isRoleAuthorizedForMethod("sbcl", "sbcl.event")).is(true);
    (expect* isRoleAuthorizedForMethod("sbcl", "status")).is(false);
    (expect* isRoleAuthorizedForMethod("operator", "status")).is(true);
    (expect* isRoleAuthorizedForMethod("operator", "sbcl.event")).is(false);
  });
});
