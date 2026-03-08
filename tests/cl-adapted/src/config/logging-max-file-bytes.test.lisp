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
import { validateConfigObject } from "./config.js";

(deftest-group "logging.maxFileBytes config", () => {
  (deftest "accepts a positive maxFileBytes", () => {
    const res = validateConfigObject({
      logging: {
        maxFileBytes: 1024,
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects non-positive maxFileBytes", () => {
    const res = validateConfigObject({
      logging: {
        maxFileBytes: 0,
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((issue) => issue.path === "logging.maxFileBytes")).is(true);
    }
  });
});
