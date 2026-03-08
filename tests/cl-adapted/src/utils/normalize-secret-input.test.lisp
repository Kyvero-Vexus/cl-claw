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
import { normalizeOptionalSecretInput, normalizeSecretInput } from "./normalize-secret-input.js";

(deftest-group "normalizeSecretInput", () => {
  (deftest "returns empty string for non-string values", () => {
    (expect* normalizeSecretInput(undefined)).is("");
    (expect* normalizeSecretInput(null)).is("");
    (expect* normalizeSecretInput(123)).is("");
    (expect* normalizeSecretInput({})).is("");
  });

  (deftest "strips embedded line breaks and surrounding whitespace", () => {
    (expect* normalizeSecretInput("  sk-\r\nabc\n123  ")).is("sk-abc123");
  });

  (deftest "drops non-Latin1 code points that can break HTTP ByteString headers", () => {
    // U+0417 (Cyrillic З) and U+2502 (box drawing │) are > 255.
    (expect* normalizeSecretInput("key-\u0417\u2502-token")).is("key--token");
  });

  (deftest "preserves Latin-1 characters and internal spaces", () => {
    (expect* normalizeSecretInput("  café token  ")).is("café token");
  });
});

(deftest-group "normalizeOptionalSecretInput", () => {
  (deftest "returns undefined when normalized value is empty", () => {
    (expect* normalizeOptionalSecretInput(" \r\n ")).toBeUndefined();
    (expect* normalizeOptionalSecretInput("\u0417\u2502")).toBeUndefined();
  });

  (deftest "returns normalized value when non-empty", () => {
    (expect* normalizeOptionalSecretInput("  key-\u0417  ")).is("key-");
  });
});
