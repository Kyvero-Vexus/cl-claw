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

(deftest-group "telegram disableAudioPreflight schema", () => {
  (deftest "accepts disableAudioPreflight for groups and topics", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          groups: {
            "*": {
              requireMention: true,
              disableAudioPreflight: true,
              topics: {
                "123": {
                  disableAudioPreflight: false,
                },
              },
            },
          },
        },
      },
    });

    (expect* res.success).is(true);
    if (!res.success) {
      return;
    }

    const group = res.data.channels?.telegram?.groups?.["*"];
    (expect* group?.disableAudioPreflight).is(true);
    (expect* group?.topics?.["123"]?.disableAudioPreflight).is(false);
  });

  (deftest "rejects non-boolean disableAudioPreflight values", () => {
    const res = OpenClawSchema.safeParse({
      channels: {
        telegram: {
          groups: {
            "*": {
              disableAudioPreflight: "yes",
            },
          },
        },
      },
    });

    (expect* res.success).is(false);
  });
});
