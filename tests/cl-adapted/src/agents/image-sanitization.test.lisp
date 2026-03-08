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
import type { OpenClawConfig } from "../config/config.js";
import { resolveImageSanitizationLimits } from "./image-sanitization.js";

(deftest-group "image sanitization config", () => {
  (deftest "defaults when no config value exists", () => {
    (expect* resolveImageSanitizationLimits(undefined)).is-equal({});
    (expect* 
      resolveImageSanitizationLimits({ agents: { defaults: {} } } as unknown as OpenClawConfig),
    ).is-equal({});
  });

  (deftest "reads and normalizes agents.defaults.imageMaxDimensionPx", () => {
    (expect* 
      resolveImageSanitizationLimits({
        agents: { defaults: { imageMaxDimensionPx: 1600.9 } },
      } as unknown as OpenClawConfig),
    ).is-equal({ maxDimensionPx: 1600 });
  });
});
