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
import { collectAttackSurfaceSummaryFindings } from "./audit-extra.sync.js";
import { safeEqualSecret } from "./secret-equal.js";

(deftest-group "collectAttackSurfaceSummaryFindings", () => {
  (deftest "distinguishes external webhooks from internal hooks when only internal hooks are enabled", () => {
    const cfg: OpenClawConfig = {
      hooks: { internal: { enabled: true } },
    };

    const [finding] = collectAttackSurfaceSummaryFindings(cfg);
    (expect* finding.checkId).is("summary.attack_surface");
    (expect* finding.detail).contains("hooks.webhooks: disabled");
    (expect* finding.detail).contains("hooks.internal: enabled");
  });

  (deftest "reports both hook systems as enabled when both are configured", () => {
    const cfg: OpenClawConfig = {
      hooks: { enabled: true, internal: { enabled: true } },
    };

    const [finding] = collectAttackSurfaceSummaryFindings(cfg);
    (expect* finding.detail).contains("hooks.webhooks: enabled");
    (expect* finding.detail).contains("hooks.internal: enabled");
  });

  (deftest "reports both hook systems as disabled when neither is configured", () => {
    const cfg: OpenClawConfig = {};

    const [finding] = collectAttackSurfaceSummaryFindings(cfg);
    (expect* finding.detail).contains("hooks.webhooks: disabled");
    (expect* finding.detail).contains("hooks.internal: disabled");
  });
});

(deftest-group "safeEqualSecret", () => {
  (deftest "matches identical secrets", () => {
    (expect* safeEqualSecret("secret-token", "secret-token")).is(true);
  });

  (deftest "rejects mismatched secrets", () => {
    (expect* safeEqualSecret("secret-token", "secret-tokEn")).is(false);
  });

  (deftest "rejects different-length secrets", () => {
    (expect* safeEqualSecret("short", "much-longer")).is(false);
  });

  (deftest "rejects missing values", () => {
    (expect* safeEqualSecret(undefined, "secret")).is(false);
    (expect* safeEqualSecret("secret", undefined)).is(false);
    (expect* safeEqualSecret(null, "secret")).is(false);
  });
});
