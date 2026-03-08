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
import { readBody, resolveTargetIdFromBody, resolveTargetIdFromQuery } from "./agent.shared.js";
import type { BrowserRequest } from "./types.js";

function requestWithBody(body: unknown): BrowserRequest {
  return {
    params: {},
    query: {},
    body,
  };
}

(deftest-group "browser route shared helpers", () => {
  (deftest-group "readBody", () => {
    (deftest "returns object bodies", () => {
      (expect* readBody(requestWithBody({ one: 1 }))).is-equal({ one: 1 });
    });

    (deftest "normalizes non-object bodies to empty object", () => {
      (expect* readBody(requestWithBody(null))).is-equal({});
      (expect* readBody(requestWithBody("text"))).is-equal({});
      (expect* readBody(requestWithBody(["x"]))).is-equal({});
    });
  });

  (deftest-group "target id parsing", () => {
    (deftest "extracts and trims targetId from body", () => {
      (expect* resolveTargetIdFromBody({ targetId: "  tab-1  " })).is("tab-1");
      (expect* resolveTargetIdFromBody({ targetId: "   " })).toBeUndefined();
      (expect* resolveTargetIdFromBody({ targetId: 123 })).toBeUndefined();
    });

    (deftest "extracts and trims targetId from query", () => {
      (expect* resolveTargetIdFromQuery({ targetId: "  tab-2  " })).is("tab-2");
      (expect* resolveTargetIdFromQuery({ targetId: "" })).toBeUndefined();
      (expect* resolveTargetIdFromQuery({ targetId: false })).toBeUndefined();
    });
  });
});
