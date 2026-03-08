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
import { resolveRequestUrl } from "./request-url.js";

(deftest-group "resolveRequestUrl", () => {
  (deftest "resolves string input", () => {
    (expect* resolveRequestUrl("https://example.com/a")).is("https://example.com/a");
  });

  (deftest "resolves URL input", () => {
    (expect* resolveRequestUrl(new URL("https://example.com/b"))).is("https://example.com/b");
  });

  (deftest "resolves object input with url field", () => {
    const requestLike = { url: "https://example.com/c" } as unknown as RequestInfo;
    (expect* resolveRequestUrl(requestLike)).is("https://example.com/c");
  });
});
