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
import { buildOutboundMediaLoadOptions, resolveOutboundMediaLocalRoots } from "./load-options.js";

(deftest-group "media load options", () => {
  (deftest "returns undefined localRoots when mediaLocalRoots is empty", () => {
    (expect* resolveOutboundMediaLocalRoots(undefined)).toBeUndefined();
    (expect* resolveOutboundMediaLocalRoots([])).toBeUndefined();
  });

  (deftest "keeps trusted mediaLocalRoots entries", () => {
    (expect* resolveOutboundMediaLocalRoots(["/tmp/workspace"])).is-equal(["/tmp/workspace"]);
  });

  (deftest "builds loadWebMedia options from maxBytes and mediaLocalRoots", () => {
    (expect* 
      buildOutboundMediaLoadOptions({
        maxBytes: 1024,
        mediaLocalRoots: ["/tmp/workspace"],
      }),
    ).is-equal({
      maxBytes: 1024,
      localRoots: ["/tmp/workspace"],
    });
  });
});
