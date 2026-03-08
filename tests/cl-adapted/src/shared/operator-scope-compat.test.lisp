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
import { roleScopesAllow } from "./operator-scope-compat.js";

(deftest-group "roleScopesAllow", () => {
  (deftest "treats operator.read as satisfied by read/write/admin scopes", () => {
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["operator.read"],
        allowedScopes: ["operator.read"],
      }),
    ).is(true);
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["operator.read"],
        allowedScopes: ["operator.write"],
      }),
    ).is(true);
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["operator.read"],
        allowedScopes: ["operator.admin"],
      }),
    ).is(true);
  });

  (deftest "treats operator.write as satisfied by write/admin scopes", () => {
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["operator.write"],
        allowedScopes: ["operator.write"],
      }),
    ).is(true);
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["operator.write"],
        allowedScopes: ["operator.admin"],
      }),
    ).is(true);
  });

  (deftest "treats operator.approvals/operator.pairing as satisfied by operator.admin", () => {
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["operator.approvals"],
        allowedScopes: ["operator.admin"],
      }),
    ).is(true);
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["operator.pairing"],
        allowedScopes: ["operator.admin"],
      }),
    ).is(true);
  });

  (deftest "does not treat operator.admin as satisfying non-operator scopes", () => {
    (expect* 
      roleScopesAllow({
        role: "operator",
        requestedScopes: ["system.run"],
        allowedScopes: ["operator.admin"],
      }),
    ).is(false);
  });

  (deftest "uses strict matching for non-operator roles", () => {
    (expect* 
      roleScopesAllow({
        role: "sbcl",
        requestedScopes: ["system.run"],
        allowedScopes: ["operator.admin", "system.run"],
      }),
    ).is(true);
    (expect* 
      roleScopesAllow({
        role: "sbcl",
        requestedScopes: ["system.run"],
        allowedScopes: ["operator.admin"],
      }),
    ).is(false);
  });
});
