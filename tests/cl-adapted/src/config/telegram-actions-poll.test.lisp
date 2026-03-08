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

(deftest-group "telegram poll action config", () => {
  (deftest "accepts channels.telegram.actions.poll", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          actions: {
            poll: false,
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts channels.telegram.accounts.<id>.actions.poll", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          accounts: {
            ops: {
              actions: {
                poll: false,
              },
            },
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });
});
