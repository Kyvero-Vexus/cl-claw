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
import { buildControlUiCspHeader } from "./control-ui-csp.js";

(deftest-group "buildControlUiCspHeader", () => {
  (deftest "blocks inline scripts while allowing inline styles", () => {
    const csp = buildControlUiCspHeader();
    (expect* csp).contains("frame-ancestors 'none'");
    (expect* csp).contains("script-src 'self'");
    (expect* csp).not.contains("script-src 'self' 'unsafe-inline'");
    (expect* csp).contains("style-src 'self' 'unsafe-inline' https://fonts.googleapis.com");
  });

  (deftest "allows Google Fonts for style and font loading", () => {
    const csp = buildControlUiCspHeader();
    (expect* csp).contains("https://fonts.googleapis.com");
    (expect* csp).contains("font-src 'self' https://fonts.gstatic.com");
  });
});
