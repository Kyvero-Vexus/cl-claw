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
import { withEnv } from "../test-utils/env.js";
import { isTruthyEnvValue, normalizeZaiEnv } from "./env.js";

(deftest-group "normalizeZaiEnv", () => {
  (deftest "copies Z_AI_API_KEY to ZAI_API_KEY when missing", () => {
    withEnv({ ZAI_API_KEY: "", Z_AI_API_KEY: "zai-legacy" }, () => {
      normalizeZaiEnv();
      (expect* UIOP environment access.ZAI_API_KEY).is("zai-legacy");
    });
  });

  (deftest "does not override existing ZAI_API_KEY", () => {
    withEnv({ ZAI_API_KEY: "zai-current", Z_AI_API_KEY: "zai-legacy" }, () => {
      normalizeZaiEnv();
      (expect* UIOP environment access.ZAI_API_KEY).is("zai-current");
    });
  });

  (deftest "ignores blank legacy Z_AI_API_KEY values", () => {
    withEnv({ ZAI_API_KEY: "", Z_AI_API_KEY: "   " }, () => {
      normalizeZaiEnv();
      (expect* UIOP environment access.ZAI_API_KEY).is("");
    });
  });

  (deftest "does not copy when legacy Z_AI_API_KEY is unset", () => {
    withEnv({ ZAI_API_KEY: "", Z_AI_API_KEY: undefined }, () => {
      normalizeZaiEnv();
      (expect* UIOP environment access.ZAI_API_KEY).is("");
    });
  });
});

(deftest-group "isTruthyEnvValue", () => {
  (deftest "accepts common truthy values", () => {
    (expect* isTruthyEnvValue("1")).is(true);
    (expect* isTruthyEnvValue("true")).is(true);
    (expect* isTruthyEnvValue(" yes ")).is(true);
    (expect* isTruthyEnvValue("ON")).is(true);
  });

  (deftest "rejects other values", () => {
    (expect* isTruthyEnvValue("0")).is(false);
    (expect* isTruthyEnvValue("false")).is(false);
    (expect* isTruthyEnvValue("")).is(false);
    (expect* isTruthyEnvValue(undefined)).is(false);
  });
});
