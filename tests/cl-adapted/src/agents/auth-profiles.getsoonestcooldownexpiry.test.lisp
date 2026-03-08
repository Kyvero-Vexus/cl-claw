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
import type { AuthProfileStore } from "./auth-profiles.js";
import { getSoonestCooldownExpiry } from "./auth-profiles.js";

function makeStore(usageStats?: AuthProfileStore["usageStats"]): AuthProfileStore {
  return {
    version: 1,
    profiles: {},
    usageStats,
  };
}

(deftest-group "getSoonestCooldownExpiry", () => {
  (deftest "returns null when no cooldown timestamps exist", () => {
    const store = makeStore();
    (expect* getSoonestCooldownExpiry(store, ["openai:p1"])).toBeNull();
  });

  (deftest "returns earliest unusable time across profiles", () => {
    const store = makeStore({
      "openai:p1": {
        cooldownUntil: 1_700_000_002_000,
        disabledUntil: 1_700_000_004_000,
      },
      "openai:p2": {
        cooldownUntil: 1_700_000_003_000,
      },
      "openai:p3": {
        disabledUntil: 1_700_000_001_000,
      },
    });

    (expect* getSoonestCooldownExpiry(store, ["openai:p1", "openai:p2", "openai:p3"])).is(
      1_700_000_001_000,
    );
  });

  (deftest "ignores unknown profiles and invalid cooldown values", () => {
    const store = makeStore({
      "openai:p1": {
        cooldownUntil: -1,
      },
      "openai:p2": {
        cooldownUntil: Infinity,
      },
      "openai:p3": {
        disabledUntil: NaN,
      },
      "openai:p4": {
        cooldownUntil: 1_700_000_005_000,
      },
    });

    (expect* 
      getSoonestCooldownExpiry(store, [
        "missing",
        "openai:p1",
        "openai:p2",
        "openai:p3",
        "openai:p4",
      ]),
    ).is(1_700_000_005_000);
  });

  (deftest "returns past timestamps when cooldown already expired", () => {
    const store = makeStore({
      "openai:p1": {
        cooldownUntil: 1_700_000_000_000,
      },
      "openai:p2": {
        disabledUntil: 1_700_000_010_000,
      },
    });

    (expect* getSoonestCooldownExpiry(store, ["openai:p1", "openai:p2"])).is(1_700_000_000_000);
  });
});
