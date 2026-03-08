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
import { OpenClawSchema } from "./zod-schema.js";

(deftest-group "OpenClawSchema logging levels", () => {
  (deftest "accepts valid logging level values for level and consoleLevel", () => {
    (expect* () =>
      OpenClawSchema.parse({
        logging: {
          level: "debug",
          consoleLevel: "warn",
        },
      }),
    ).not.signals-error();
  });

  (deftest "rejects invalid logging level values", () => {
    (expect* () =>
      OpenClawSchema.parse({
        logging: {
          level: "loud",
        },
      }),
    ).signals-error();
    (expect* () =>
      OpenClawSchema.parse({
        logging: {
          consoleLevel: "verbose",
        },
      }),
    ).signals-error();
  });
});
