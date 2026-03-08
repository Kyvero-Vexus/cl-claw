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
import { getDmHistoryLimitFromSessionKey } from "./pi-embedded-runner.js";

(deftest-group "getDmHistoryLimitFromSessionKey", () => {
  (deftest "keeps backward compatibility for dm/direct session kinds", () => {
    const config = {
      channels: { telegram: { dmHistoryLimit: 10 } },
    } as OpenClawConfig;

    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).is(10);
    (expect* getDmHistoryLimitFromSessionKey("telegram:direct:123", config)).is(10);
  });

  (deftest "returns historyLimit for channel and group session kinds", () => {
    const config = {
      channels: { discord: { historyLimit: 12, dmHistoryLimit: 5 } },
    } as OpenClawConfig;

    (expect* getDmHistoryLimitFromSessionKey("discord:channel:123", config)).is(12);
    (expect* getDmHistoryLimitFromSessionKey("discord:group:456", config)).is(12);
  });

  (deftest "returns undefined for unsupported session kinds", () => {
    const config = {
      channels: { discord: { historyLimit: 12, dmHistoryLimit: 5 } },
    } as OpenClawConfig;

    (expect* getDmHistoryLimitFromSessionKey("discord:slash:123", config)).toBeUndefined();
  });
});
