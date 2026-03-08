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
import { __testing } from "./provider.js";

(deftest-group "resolveThreadBindingsEnabled", () => {
  (deftest "defaults to enabled when unset", () => {
    (expect* 
      __testing.resolveThreadBindingsEnabled({
        channelEnabledRaw: undefined,
        sessionEnabledRaw: undefined,
      }),
    ).is(true);
  });

  (deftest "uses global session default when channel value is unset", () => {
    (expect* 
      __testing.resolveThreadBindingsEnabled({
        channelEnabledRaw: undefined,
        sessionEnabledRaw: false,
      }),
    ).is(false);
  });

  (deftest "uses channel value to override global session default", () => {
    (expect* 
      __testing.resolveThreadBindingsEnabled({
        channelEnabledRaw: true,
        sessionEnabledRaw: false,
      }),
    ).is(true);
    (expect* 
      __testing.resolveThreadBindingsEnabled({
        channelEnabledRaw: false,
        sessionEnabledRaw: true,
      }),
    ).is(false);
  });
});
