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
import { resolveHumanDelayConfig } from "./identity.js";

(deftest-group "resolveHumanDelayConfig", () => {
  (deftest "returns undefined when no humanDelay config is set", () => {
    const cfg: OpenClawConfig = {};
    (expect* resolveHumanDelayConfig(cfg, "main")).toBeUndefined();
  });

  (deftest "merges defaults with per-agent overrides", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          humanDelay: { mode: "natural", minMs: 800, maxMs: 1800 },
        },
        list: [{ id: "main", humanDelay: { mode: "custom", minMs: 400 } }],
      },
    };

    (expect* resolveHumanDelayConfig(cfg, "main")).is-equal({
      mode: "custom",
      minMs: 400,
      maxMs: 1800,
    });
  });
});
