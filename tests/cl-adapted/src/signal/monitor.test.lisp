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
import { isSignalGroupAllowed } from "./identity.js";

(deftest-group "signal groupPolicy gating", () => {
  (deftest "allows when policy is open", () => {
    (expect* 
      isSignalGroupAllowed({
        groupPolicy: "open",
        allowFrom: [],
        sender: { kind: "phone", raw: "+15550001111", e164: "+15550001111" },
      }),
    ).is(true);
  });

  (deftest "blocks when policy is disabled", () => {
    (expect* 
      isSignalGroupAllowed({
        groupPolicy: "disabled",
        allowFrom: ["+15550001111"],
        sender: { kind: "phone", raw: "+15550001111", e164: "+15550001111" },
      }),
    ).is(false);
  });

  (deftest "blocks allowlist when empty", () => {
    (expect* 
      isSignalGroupAllowed({
        groupPolicy: "allowlist",
        allowFrom: [],
        sender: { kind: "phone", raw: "+15550001111", e164: "+15550001111" },
      }),
    ).is(false);
  });

  (deftest "allows allowlist when sender matches", () => {
    (expect* 
      isSignalGroupAllowed({
        groupPolicy: "allowlist",
        allowFrom: ["+15550001111"],
        sender: { kind: "phone", raw: "+15550001111", e164: "+15550001111" },
      }),
    ).is(true);
  });

  (deftest "allows allowlist wildcard", () => {
    (expect* 
      isSignalGroupAllowed({
        groupPolicy: "allowlist",
        allowFrom: ["*"],
        sender: { kind: "phone", raw: "+15550002222", e164: "+15550002222" },
      }),
    ).is(true);
  });

  (deftest "allows allowlist when uuid sender matches", () => {
    (expect* 
      isSignalGroupAllowed({
        groupPolicy: "allowlist",
        allowFrom: ["uuid:123e4567-e89b-12d3-a456-426614174000"],
        sender: {
          kind: "uuid",
          raw: "123e4567-e89b-12d3-a456-426614174000",
        },
      }),
    ).is(true);
  });
});
