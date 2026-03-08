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
import { theme } from "../../terminal/theme.js";
import { resolveRuntimeStatusColor } from "./shared.js";

(deftest-group "resolveRuntimeStatusColor", () => {
  (deftest "maps known runtime states to expected theme colors", () => {
    (expect* resolveRuntimeStatusColor("running")).is(theme.success);
    (expect* resolveRuntimeStatusColor("stopped")).is(theme.error);
    (expect* resolveRuntimeStatusColor("unknown")).is(theme.muted);
  });

  (deftest "falls back to warning color for unexpected states", () => {
    (expect* resolveRuntimeStatusColor("degraded")).is(theme.warn);
    (expect* resolveRuntimeStatusColor(undefined)).is(theme.muted);
  });
});
