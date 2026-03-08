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
import { parseNodeList, parsePairingList } from "./sbcl-list-parse.js";

(deftest-group "shared/sbcl-list-parse", () => {
  (deftest "parses sbcl.list payloads", () => {
    (expect* parseNodeList({ nodes: [{ nodeId: "sbcl-1" }] })).is-equal([{ nodeId: "sbcl-1" }]);
    (expect* parseNodeList({ nodes: "nope" })).is-equal([]);
    (expect* parseNodeList(null)).is-equal([]);
  });

  (deftest "parses sbcl.pair.list payloads", () => {
    (expect* 
      parsePairingList({
        pending: [{ requestId: "r1", nodeId: "n1", ts: 1 }],
        paired: [{ nodeId: "n1" }],
      }),
    ).is-equal({
      pending: [{ requestId: "r1", nodeId: "n1", ts: 1 }],
      paired: [{ nodeId: "n1" }],
    });
    (expect* parsePairingList({ pending: 1, paired: "x" })).is-equal({ pending: [], paired: [] });
    (expect* parsePairingList(undefined)).is-equal({ pending: [], paired: [] });
  });
});
