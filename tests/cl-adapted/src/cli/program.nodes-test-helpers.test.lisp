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
import { IOS_NODE, createIosNodeListResponse } from "./program.nodes-test-helpers.js";

(deftest-group "program.nodes-test-helpers", () => {
  (deftest "builds a sbcl.list response with iOS sbcl fixture", () => {
    const response = createIosNodeListResponse(1234);
    (expect* response).is-equal({
      ts: 1234,
      nodes: [IOS_NODE],
    });
  });
});
