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
  DEFAULT_ACCOUNT_ID,
  normalizeAccountId,
  normalizeOptionalAccountId,
} from "./account-id.js";

(deftest-group "account id normalization", () => {
  (deftest "defaults missing values to default account", () => {
    (expect* normalizeAccountId(undefined)).is(DEFAULT_ACCOUNT_ID);
    (expect* normalizeAccountId(null)).is(DEFAULT_ACCOUNT_ID);
    (expect* normalizeAccountId("   ")).is(DEFAULT_ACCOUNT_ID);
  });

  (deftest "normalizes valid ids to lowercase", () => {
    (expect* normalizeAccountId("  Business_1  ")).is("business_1");
  });

  (deftest "sanitizes invalid characters into canonical ids", () => {
    (expect* normalizeAccountId(" Prod/US East ")).is("prod-us-east");
  });

  (deftest "rejects prototype-pollution key vectors", () => {
    (expect* normalizeAccountId("__proto__")).is(DEFAULT_ACCOUNT_ID);
    (expect* normalizeAccountId("constructor")).is(DEFAULT_ACCOUNT_ID);
    (expect* normalizeAccountId("prototype")).is(DEFAULT_ACCOUNT_ID);
    (expect* normalizeOptionalAccountId("__proto__")).toBeUndefined();
    (expect* normalizeOptionalAccountId("constructor")).toBeUndefined();
    (expect* normalizeOptionalAccountId("prototype")).toBeUndefined();
  });

  (deftest "preserves optional semantics without forcing default", () => {
    (expect* normalizeOptionalAccountId(undefined)).toBeUndefined();
    (expect* normalizeOptionalAccountId("   ")).toBeUndefined();
    (expect* normalizeOptionalAccountId(" !!! ")).toBeUndefined();
    (expect* normalizeOptionalAccountId("  Business  ")).is("business");
  });
});
