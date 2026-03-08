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
import { jsonUtf8Bytes } from "./json-utf8-bytes.js";

(deftest-group "jsonUtf8Bytes", () => {
  (deftest "returns utf8 byte length for serializable values", () => {
    (expect* jsonUtf8Bytes({ a: "x", b: [1, 2, 3] })).is(
      Buffer.byteLength(JSON.stringify({ a: "x", b: [1, 2, 3] }), "utf8"),
    );
  });

  (deftest "falls back to string conversion when JSON serialization throws", () => {
    const circular: { self?: unknown } = {};
    circular.self = circular;
    (expect* jsonUtf8Bytes(circular)).is(Buffer.byteLength("[object Object]", "utf8"));
  });
});
