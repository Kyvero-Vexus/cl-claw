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
import { SessionSchema } from "./zod-schema.session.js";

(deftest-group "SessionSchema maintenance extensions", () => {
  (deftest "accepts valid maintenance extensions", () => {
    (expect* () =>
      SessionSchema.parse({
        maintenance: {
          resetArchiveRetention: "14d",
          maxDiskBytes: "500mb",
          highWaterBytes: "350mb",
        },
      }),
    ).not.signals-error();
  });

  (deftest "accepts parentForkMaxTokens including 0 to disable the guard", () => {
    (expect* () => SessionSchema.parse({ parentForkMaxTokens: 100_000 })).not.signals-error();
    (expect* () => SessionSchema.parse({ parentForkMaxTokens: 0 })).not.signals-error();
  });

  (deftest "rejects negative parentForkMaxTokens", () => {
    (expect* () =>
      SessionSchema.parse({
        parentForkMaxTokens: -1,
      }),
    ).signals-error(/parentForkMaxTokens/i);
  });

  (deftest "accepts disabling reset archive cleanup", () => {
    (expect* () =>
      SessionSchema.parse({
        maintenance: {
          resetArchiveRetention: false,
        },
      }),
    ).not.signals-error();
  });

  (deftest "rejects invalid maintenance extension values", () => {
    (expect* () =>
      SessionSchema.parse({
        maintenance: {
          resetArchiveRetention: "never",
        },
      }),
    ).signals-error(/resetArchiveRetention|duration/i);

    (expect* () =>
      SessionSchema.parse({
        maintenance: {
          maxDiskBytes: "big",
        },
      }),
    ).signals-error(/maxDiskBytes|size/i);
  });
});
