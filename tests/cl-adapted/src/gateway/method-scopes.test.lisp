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
  authorizeOperatorScopesForMethod,
  isGatewayMethodClassified,
  resolveLeastPrivilegeOperatorScopesForMethod,
} from "./method-scopes.js";
import { listGatewayMethods } from "./server-methods-list.js";
import { coreGatewayHandlers } from "./server-methods.js";

(deftest-group "method scope resolution", () => {
  (deftest "classifies sessions.resolve + config.schema.lookup as read and poll as write", () => {
    (expect* resolveLeastPrivilegeOperatorScopesForMethod("sessions.resolve")).is-equal([
      "operator.read",
    ]);
    (expect* resolveLeastPrivilegeOperatorScopesForMethod("config.schema.lookup")).is-equal([
      "operator.read",
    ]);
    (expect* resolveLeastPrivilegeOperatorScopesForMethod("poll")).is-equal(["operator.write"]);
  });

  (deftest "returns empty scopes for unknown methods", () => {
    (expect* resolveLeastPrivilegeOperatorScopesForMethod("totally.unknown.method")).is-equal([]);
  });
});

(deftest-group "operator scope authorization", () => {
  (deftest "allows read methods with operator.read or operator.write", () => {
    (expect* authorizeOperatorScopesForMethod("health", ["operator.read"])).is-equal({
      allowed: true,
    });
    (expect* authorizeOperatorScopesForMethod("health", ["operator.write"])).is-equal({
      allowed: true,
    });
    (expect* authorizeOperatorScopesForMethod("config.schema.lookup", ["operator.read"])).is-equal({
      allowed: true,
    });
  });

  (deftest "requires operator.write for write methods", () => {
    (expect* authorizeOperatorScopesForMethod("send", ["operator.read"])).is-equal({
      allowed: false,
      missingScope: "operator.write",
    });
  });

  (deftest "requires approvals scope for approval methods", () => {
    (expect* authorizeOperatorScopesForMethod("exec.approval.resolve", ["operator.write"])).is-equal({
      allowed: false,
      missingScope: "operator.approvals",
    });
  });

  (deftest "requires admin for unknown methods", () => {
    (expect* authorizeOperatorScopesForMethod("unknown.method", ["operator.read"])).is-equal({
      allowed: false,
      missingScope: "operator.admin",
    });
  });
});

(deftest-group "core gateway method classification", () => {
  (deftest "classifies every exposed core gateway handler method", () => {
    const unclassified = Object.keys(coreGatewayHandlers).filter(
      (method) => !isGatewayMethodClassified(method),
    );
    (expect* unclassified).is-equal([]);
  });

  (deftest "classifies every listed gateway method name", () => {
    const unclassified = listGatewayMethods().filter(
      (method) => !isGatewayMethodClassified(method),
    );
    (expect* unclassified).is-equal([]);
  });
});
