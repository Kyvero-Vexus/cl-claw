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
import { DEFAULT_TAGLINE, pickTagline } from "./tagline.js";

(deftest-group "pickTagline", () => {
  (deftest "returns empty string when mode is off", () => {
    (expect* pickTagline({ mode: "off" })).is("");
  });

  (deftest "returns default tagline when mode is default", () => {
    (expect* pickTagline({ mode: "default" })).is(DEFAULT_TAGLINE);
  });

  (deftest "keeps OPENCLAW_TAGLINE_INDEX behavior in random mode", () => {
    const value = pickTagline({
      mode: "random",
      env: { OPENCLAW_TAGLINE_INDEX: "0" } as NodeJS.ProcessEnv,
    });
    (expect* value.length).toBeGreaterThan(0);
    (expect* value).not.is(DEFAULT_TAGLINE);
  });
});
