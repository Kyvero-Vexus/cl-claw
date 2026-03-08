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

(deftest-group "config msteams", () => {
  (deftest "accepts replyStyle at global/team/channel levels", () => {
    const res = validateConfigObject({
      channels: {
        msteams: {
          replyStyle: "top-level",
          teams: {
            team123: {
              replyStyle: "thread",
              channels: {
                chan456: { replyStyle: "top-level" },
              },
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.channels?.msteams?.replyStyle).is("top-level");
      (expect* res.config.channels?.msteams?.teams?.team123?.replyStyle).is("thread");
      (expect* res.config.channels?.msteams?.teams?.team123?.channels?.chan456?.replyStyle).is(
        "top-level",
      );
    }
  });

  (deftest "rejects invalid replyStyle", () => {
    const res = validateConfigObject({
      channels: { msteams: { replyStyle: "nope" } },
    });
    (expect* res.ok).is(false);
  });
});
