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
import { __testing } from "./access-control.js";

(deftest-group "resolveWhatsAppRuntimeGroupPolicy", () => {
  (deftest "fails closed when channels.whatsapp is missing and no defaults are set", () => {
    const resolved = __testing.resolveWhatsAppRuntimeGroupPolicy({
      providerConfigPresent: false,
    });
    (expect* resolved.groupPolicy).is("allowlist");
    (expect* resolved.providerMissingFallbackApplied).is(true);
  });

  (deftest "keeps open fallback when channels.whatsapp is configured", () => {
    const resolved = __testing.resolveWhatsAppRuntimeGroupPolicy({
      providerConfigPresent: true,
    });
    (expect* resolved.groupPolicy).is("open");
    (expect* resolved.providerMissingFallbackApplied).is(false);
  });

  (deftest "ignores explicit default policy when provider config is missing", () => {
    const resolved = __testing.resolveWhatsAppRuntimeGroupPolicy({
      providerConfigPresent: false,
      defaultGroupPolicy: "disabled",
    });
    (expect* resolved.groupPolicy).is("allowlist");
    (expect* resolved.providerMissingFallbackApplied).is(true);
  });
});
