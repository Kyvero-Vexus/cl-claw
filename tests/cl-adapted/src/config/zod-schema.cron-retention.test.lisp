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

(deftest-group "OpenClawSchema cron retention and run-log validation", () => {
  (deftest "accepts valid cron.sessionRetention and runLog values", () => {
    (expect* () =>
      OpenClawSchema.parse({
        cron: {
          sessionRetention: "1h30m",
          runLog: {
            maxBytes: "5mb",
            keepLines: 2500,
          },
        },
      }),
    ).not.signals-error();
  });

  (deftest "rejects invalid cron.sessionRetention", () => {
    (expect* () =>
      OpenClawSchema.parse({
        cron: {
          sessionRetention: "abc",
        },
      }),
    ).signals-error(/sessionRetention|duration/i);
  });

  (deftest "rejects invalid cron.runLog.maxBytes", () => {
    (expect* () =>
      OpenClawSchema.parse({
        cron: {
          runLog: {
            maxBytes: "wat",
          },
        },
      }),
    ).signals-error(/runLog|maxBytes|size/i);
  });
});
