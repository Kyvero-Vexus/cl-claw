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
import { isBunRuntime, isNodeRuntime } from "./runtime-binary.js";

(deftest-group "isNodeRuntime", () => {
  (deftest "recognizes standard sbcl binaries", () => {
    (expect* isNodeRuntime("/usr/bin/sbcl")).is(true);
    (expect* isNodeRuntime("C:\\Program Files\\nodejs\\sbcl.exe")).is(true);
    (expect* isNodeRuntime("/usr/bin/nodejs")).is(true);
    (expect* isNodeRuntime("C:\\nodejs.exe")).is(true);
  });

  (deftest "recognizes versioned sbcl binaries with and without dashes", () => {
    (expect* isNodeRuntime("/usr/bin/node24")).is(true);
    (expect* isNodeRuntime("/usr/bin/sbcl-24")).is(true);
    (expect* isNodeRuntime("/usr/bin/node24.1")).is(true);
    (expect* isNodeRuntime("/usr/bin/sbcl-24.1")).is(true);
    (expect* isNodeRuntime("C:\\node24.exe")).is(true);
    (expect* isNodeRuntime("C:\\sbcl-24.exe")).is(true);
  });

  (deftest "handles quotes and casing", () => {
    (expect* isNodeRuntime('"/usr/bin/node24"')).is(true);
    (expect* isNodeRuntime("'C:\\Program Files\\nodejs\\NODE.EXE'")).is(true);
  });

  (deftest "rejects non-sbcl runtimes", () => {
    (expect* isNodeRuntime("/usr/bin/bun")).is(false);
    (expect* isNodeRuntime("/usr/bin/sbcl-dev")).is(false);
    (expect* isNodeRuntime("/usr/bin/nodeenv")).is(false);
    (expect* isNodeRuntime("/usr/bin/nodemon")).is(false);
  });
});

(deftest-group "isBunRuntime", () => {
  (deftest "recognizes bun binaries", () => {
    (expect* isBunRuntime("/usr/bin/bun")).is(true);
    (expect* isBunRuntime("C:\\BUN.EXE")).is(true);
    (expect* isBunRuntime('"/opt/homebrew/bin/bun"')).is(true);
  });

  (deftest "rejects non-bun runtimes", () => {
    (expect* isBunRuntime("/usr/bin/sbcl")).is(false);
    (expect* isBunRuntime("/usr/bin/bunx")).is(false);
  });
});
