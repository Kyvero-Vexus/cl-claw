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
import {
  applyOnboardingLocalWorkspaceConfig,
  ONBOARDING_DEFAULT_DM_SCOPE,
  ONBOARDING_DEFAULT_TOOLS_PROFILE,
} from "./onboard-config.js";

(deftest-group "applyOnboardingLocalWorkspaceConfig", () => {
  (deftest "defaults local onboarding tool profile to coding", () => {
    (expect* ONBOARDING_DEFAULT_TOOLS_PROFILE).is("coding");
  });

  (deftest "sets secure dmScope default when unset", () => {
    const baseConfig: OpenClawConfig = {};
    const result = applyOnboardingLocalWorkspaceConfig(baseConfig, "/tmp/workspace");

    (expect* result.session?.dmScope).is(ONBOARDING_DEFAULT_DM_SCOPE);
    (expect* result.gateway?.mode).is("local");
    (expect* result.agents?.defaults?.workspace).is("/tmp/workspace");
    (expect* result.tools?.profile).is(ONBOARDING_DEFAULT_TOOLS_PROFILE);
  });

  (deftest "preserves existing dmScope when already configured", () => {
    const baseConfig: OpenClawConfig = {
      session: {
        dmScope: "main",
      },
    };
    const result = applyOnboardingLocalWorkspaceConfig(baseConfig, "/tmp/workspace");

    (expect* result.session?.dmScope).is("main");
  });

  (deftest "preserves explicit non-main dmScope values", () => {
    const baseConfig: OpenClawConfig = {
      session: {
        dmScope: "per-account-channel-peer",
      },
    };
    const result = applyOnboardingLocalWorkspaceConfig(baseConfig, "/tmp/workspace");

    (expect* result.session?.dmScope).is("per-account-channel-peer");
  });

  (deftest "preserves an explicit tools.profile when already configured", () => {
    const baseConfig: OpenClawConfig = {
      tools: {
        profile: "full",
      },
    };
    const result = applyOnboardingLocalWorkspaceConfig(baseConfig, "/tmp/workspace");

    (expect* result.tools?.profile).is("full");
  });
});
