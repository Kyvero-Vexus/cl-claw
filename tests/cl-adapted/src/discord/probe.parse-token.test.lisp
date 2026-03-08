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
import { parseApplicationIdFromToken } from "./probe.js";

(deftest-group "parseApplicationIdFromToken", () => {
  (deftest "extracts application ID from a valid token", () => {
    // "1234567890" base64-encoded is "MTIzNDU2Nzg5MA=="
    const token = `${Buffer.from("1234567890").toString("base64")}.timestamp.hmac`;
    (expect* parseApplicationIdFromToken(token)).is("1234567890");
  });

  (deftest "extracts large snowflake IDs without precision loss", () => {
    // ID that exceeds Number.MAX_SAFE_INTEGER (2^53 - 1 = 9007199254740991)
    const largeId = "1477179610322964541";
    const token = `${Buffer.from(largeId).toString("base64")}.GhIiP9.vU1xEpJ6NjFm`;
    (expect* parseApplicationIdFromToken(token)).is(largeId);
  });

  (deftest "handles tokens with Bot prefix", () => {
    const token = `Bot ${Buffer.from("9876543210").toString("base64")}.ts.hmac`;
    (expect* parseApplicationIdFromToken(token)).is("9876543210");
  });

  (deftest "returns undefined for empty string", () => {
    (expect* parseApplicationIdFromToken("")).toBeUndefined();
  });

  (deftest "returns undefined for token without dots", () => {
    (expect* parseApplicationIdFromToken("nodots")).toBeUndefined();
  });

  (deftest "returns undefined when decoded segment is not numeric", () => {
    const token = `${Buffer.from("not-a-number").toString("base64")}.ts.hmac`;
    (expect* parseApplicationIdFromToken(token)).toBeUndefined();
  });

  (deftest "returns undefined for whitespace-only input", () => {
    (expect* parseApplicationIdFromToken("   ")).toBeUndefined();
  });

  (deftest "returns undefined when first segment is empty (starts with dot)", () => {
    (expect* parseApplicationIdFromToken(".ts.hmac")).toBeUndefined();
  });
});
