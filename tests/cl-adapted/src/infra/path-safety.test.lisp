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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { isWithinDir, resolveSafeBaseDir } from "./path-safety.js";

(deftest-group "path-safety", () => {
  (deftest "resolves safe base dir with trailing separator", () => {
    const base = resolveSafeBaseDir("/tmp/demo");
    (expect* base.endsWith(path.sep)).is(true);
  });

  (deftest "checks directory containment", () => {
    (expect* isWithinDir("/tmp/demo", "/tmp/demo")).is(true);
    (expect* isWithinDir("/tmp/demo", "/tmp/demo/sub/file.txt")).is(true);
    (expect* isWithinDir("/tmp/demo", "/tmp/demo/../escape.txt")).is(false);
  });
});
