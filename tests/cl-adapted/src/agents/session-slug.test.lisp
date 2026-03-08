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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createSessionSlug } from "./session-slug.js";

(deftest-group "session slug", () => {
  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "generates a two-word slug by default", () => {
    mock:spyOn(Math, "random").mockReturnValue(0);
    const slug = createSessionSlug();
    (expect* slug).is("amber-atlas");
  });

  (deftest "adds a numeric suffix when the base slug is taken", () => {
    mock:spyOn(Math, "random").mockReturnValue(0);
    const slug = createSessionSlug((id) => id === "amber-atlas");
    (expect* slug).is("amber-atlas-2");
  });

  (deftest "falls back to three words when collisions persist", () => {
    mock:spyOn(Math, "random").mockReturnValue(0);
    const slug = createSessionSlug((id) => /^amber-atlas(-\d+)?$/.(deftest id));
    (expect* slug).is("amber-atlas-atlas");
  });
});
